// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Envelope, EnvelopeLib} from "./libraries/EnvelopeLib.sol";

/// @title StrategyRegistry
/// @notice Registry for curator strategies with bounded envelopes and timelocked loosening.
/// @dev    Ranking is alpha-vs-hold only (AUM and volume never feed it): the vault records its
///         cumulative alpha-per-share on each LP action, and the score is the change over a rolling
///         lookback window, so a strategy is ranked on per-interval performance rather than a
///         since-inception total that stale history could inflate.
contract StrategyRegistry {
    error Unauthorized();
    error TimelockNotReady();
    error NoPendingChange();
    error FactoryAlreadySet();
    error StrategyAlreadyBound();
    error UnknownStrategy();

    struct Strategy {
        address curator;
        Envelope envelope;
        bool active;
    }

    struct PendingEnvelope {
        Envelope envelope;
        uint256 unlockTime;
    }

    /// @dev A recorded (timestamp, cumulative alpha-per-share) sample. Score = newest minus the
    ///      oldest sample still inside the lookback window.
    struct Checkpoint {
        uint64 ts;
        int256 alphaPerShare;
    }

    uint256 public constant LOOSEN_DELAY = 24 hours;
    /// @notice Rolling window over which per-interval alpha is measured.
    uint32 public constant ALPHA_LOOKBACK = 30 days;

    mapping(uint256 => Strategy) public strategies;
    mapping(uint256 => PendingEnvelope) public pendingEnvelope;
    mapping(uint256 => Checkpoint[]) internal _alphaHistory;
    mapping(uint256 => address) public strategyVault;
    uint256 public nextStrategyId;

    /// @notice Deployer; may set the factory address exactly once.
    address public owner;
    /// @notice The only address allowed to bind a vault to a strategy.
    address public factory;

    event StrategyRegistered(uint256 indexed id, address indexed curator);
    event EnvelopeTightened(uint256 indexed id);
    event EnvelopeLooseningQueued(uint256 indexed id, uint256 unlockTime);
    event EnvelopeLooseningApplied(uint256 indexed id);
    event AlphaCheckpointed(uint256 indexed id, int256 alphaPerShare);
    event FactorySet(address indexed factory);
    event StrategyVaultBound(uint256 indexed id, address indexed vault);

    constructor() {
        owner = msg.sender;
    }

    /// @notice Set the factory that may bind vaults. Callable once by the deployer.
    function setFactory(address _factory) external {
        if (msg.sender != owner) revert Unauthorized();
        if (factory != address(0) || _factory == address(0)) revert FactoryAlreadySet();
        factory = _factory;
        emit FactorySet(_factory);
    }

    function registerStrategy(Envelope calldata env) external returns (uint256 id) {
        EnvelopeLib.validate(env);
        id = nextStrategyId++;
        strategies[id] = Strategy({curator: msg.sender, envelope: env, active: true});
        emit StrategyRegistered(id, msg.sender);
    }

    function getEnvelope(uint256 id) external view returns (Envelope memory) {
        return strategies[id].envelope;
    }

    function getCurator(uint256 id) external view returns (address) {
        return strategies[id].curator;
    }

    function isCurator(uint256 id, address who) external view returns (bool) {
        return strategies[id].curator == who && strategies[id].active;
    }

    /// @notice Apply a strictly-tighter envelope immediately. Reverts if any field is looser.
    function tightenEnvelope(uint256 id, Envelope calldata newEnv) external {
        if (strategies[id].curator != msg.sender) revert Unauthorized();
        EnvelopeLib.validate(newEnv);
        if (!EnvelopeLib.isTighter(strategies[id].envelope, newEnv)) revert EnvelopeLib.NotTighter();
        strategies[id].envelope = newEnv;
        delete pendingEnvelope[id];
        emit EnvelopeTightened(id);
    }

    function queueLoosenEnvelope(uint256 id, Envelope calldata newEnv) external {
        if (strategies[id].curator != msg.sender) revert Unauthorized();
        EnvelopeLib.validate(newEnv);
        uint256 unlockTime = block.timestamp + LOOSEN_DELAY;
        pendingEnvelope[id] = PendingEnvelope({envelope: newEnv, unlockTime: unlockTime});
        emit EnvelopeLooseningQueued(id, unlockTime);
    }

    function applyLoosenEnvelope(uint256 id) external {
        PendingEnvelope memory p = pendingEnvelope[id];
        if (p.unlockTime == 0) revert NoPendingChange();
        if (block.timestamp < p.unlockTime) revert TimelockNotReady();
        if (strategies[id].curator != msg.sender) revert Unauthorized();
        strategies[id].envelope = p.envelope;
        delete pendingEnvelope[id];
        emit EnvelopeLooseningApplied(id);
    }

    /// @notice Bind a vault to a strategy. Only the factory may call, exactly once per strategy.
    /// @dev Called by VaultFactory during `createVault`, atomically with initialization. Reverts if
    ///      the strategy already has a vault, so a strategy can never be hijacked to a second vault.
    function setStrategyVault(uint256 id, address vault) external {
        if (msg.sender != factory) revert Unauthorized();
        if (strategies[id].curator == address(0)) revert UnknownStrategy();
        if (strategyVault[id] != address(0)) revert StrategyAlreadyBound();
        strategyVault[id] = vault;
        emit StrategyVaultBound(id, vault);
    }

    /// @notice Record the vault's current cumulative alpha-per-share. Only the bound vault may call.
    function checkpointAlpha(uint256 id, int256 alphaPerShare) external {
        if (strategyVault[id] != msg.sender) revert Unauthorized();
        _alphaHistory[id].push(Checkpoint({ts: uint64(block.timestamp), alphaPerShare: alphaPerShare}));
        _prune(id);
        emit AlphaCheckpointed(id, alphaPerShare);
    }

    /// @notice Time-weighted per-interval alpha over the lookback window: the change in cumulative
    ///         alpha-per-share between the newest sample and the oldest sample still in the window.
    ///         Zero when a strategy has fewer than two samples in the window.
    function getAlpha(uint256 id) public view returns (int256) {
        Checkpoint[] storage h = _alphaHistory[id];
        uint256 len = h.length;
        if (len < 2) return 0;
        return h[len - 1].alphaPerShare - h[0].alphaPerShare;
    }

    /// @notice Number of samples currently retained for a strategy (bounded by the lookback).
    function alphaSamples(uint256 id) external view returns (uint256) {
        return _alphaHistory[id].length;
    }

    /// @notice Top `limit` active strategies by per-interval alpha, descending. Ties keep id order.
    function leaderboard(uint256 limit) external view returns (uint256[] memory ids, int256[] memory scores) {
        uint256 n = nextStrategyId;
        uint256 count;
        for (uint256 i = 0; i < n; i++) {
            if (strategies[i].active && strategyVault[i] != address(0)) count++;
        }
        if (limit > count) limit = count;

        uint256[] memory allIds = new uint256[](count);
        int256[] memory allScores = new int256[](count);
        uint256 k;
        for (uint256 i = 0; i < n; i++) {
            if (strategies[i].active && strategyVault[i] != address(0)) {
                allIds[k] = i;
                allScores[k] = getAlpha(i);
                k++;
            }
        }

        for (uint256 i = 0; i < limit; i++) {
            for (uint256 j = i + 1; j < count; j++) {
                if (allScores[j] > allScores[i]) {
                    (allScores[i], allScores[j]) = (allScores[j], allScores[i]);
                    (allIds[i], allIds[j]) = (allIds[j], allIds[i]);
                }
            }
        }

        ids = new uint256[](limit);
        scores = new int256[](limit);
        for (uint256 i = 0; i < limit; i++) {
            ids[i] = allIds[i];
            scores[i] = allScores[i];
        }
    }

    /// @dev Drop samples older than the lookback, keeping the newest sample before the cutoff as the
    ///      window anchor so the score still spans the full lookback.
    function _prune(uint256 id) internal {
        Checkpoint[] storage h = _alphaHistory[id];
        uint64 cutoff = block.timestamp > ALPHA_LOOKBACK ? uint64(block.timestamp - ALPHA_LOOKBACK) : 0;
        if (cutoff == 0) return;
        uint256 drop;
        while (drop + 1 < h.length && h[drop + 1].ts <= cutoff) drop++;
        if (drop == 0) return;
        for (uint256 i = drop; i < h.length; i++) {
            h[i - drop] = h[i];
        }
        for (uint256 j = 0; j < drop; j++) {
            h.pop();
        }
    }
}
