// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Envelope, EnvelopeLib} from "./libraries/EnvelopeLib.sol";

/// @title StrategyRegistry
/// @notice Registry for curator strategies with bounded envelopes and timelocked loosening.
/// @dev    Ranking is alpha-vs-hold only (AUM and volume never feed it): each vault reports its
///         running alpha accumulator on every LP action, and the score is that accumulator minus the
///         oldest sample still inside the lookback window, so a strategy is ranked on per-interval
///         performance rather than a since-inception total that stale history could inflate. Samples
///         are persisted at most once per `CHECKPOINT_INTERVAL` into a fixed-capacity ring, so the
///         history can never grow unbounded no matter how often a vault acts.
contract StrategyRegistry {
    error Unauthorized();
    error TimelockNotReady();
    error NoPendingChange();
    error FactoryAlreadySet();
    error StrategyAlreadyBound();
    error UnknownStrategy();

    uint256 public constant LOOSEN_DELAY = 24 hours;
    /// @notice Rolling window over which per-interval alpha is measured.
    uint32 public constant ALPHA_LOOKBACK = 30 days;
    /// @notice Minimum time between persisted alpha samples. `MAX_CHECKPOINTS * CHECKPOINT_INTERVAL`
    ///         spans the lookback, so the fixed ring always covers the whole window.
    uint32 public constant CHECKPOINT_INTERVAL = 1 hours;
    /// @notice Fixed number of alpha samples retained per strategy (ring buffer, oldest overwritten).
    uint256 public constant MAX_CHECKPOINTS = 720;

    struct Strategy {
        address curator;
        Envelope envelope;
        bool active;
    }

    struct PendingEnvelope {
        Envelope envelope;
        uint256 unlockTime;
    }

    /// @dev A recorded (timestamp, cumulative alpha) sample. The score is the vault's live
    ///      accumulator minus the oldest sample still inside the lookback window.
    struct Checkpoint {
        uint64 ts;
        int256 cumulativeAlpha;
    }

    /// @dev Fixed-capacity ring of checkpoints. `head` is the next write slot; once `count` reaches
    ///      `MAX_CHECKPOINTS` the oldest sample is overwritten, so the history is hard-bounded.
    struct AlphaHistory {
        Checkpoint[MAX_CHECKPOINTS] samples;
        uint256 head;
        uint256 count;
    }

    mapping(uint256 => Strategy) public strategies;
    mapping(uint256 => PendingEnvelope) public pendingEnvelope;
    /// @notice Latest cumulative alpha reported by each strategy's vault (updated on every action).
    mapping(uint256 => int256) public alphaAccumulator;
    mapping(uint256 => AlphaHistory) internal _alphaHistory;
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
    event AlphaCheckpointed(uint256 indexed id, int256 cumulativeAlpha);
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

    /// @notice Record the vault's running alpha accumulator. Only the bound vault may call. The live
    ///         accumulator is updated on every call, but a durable sample is appended at most once
    ///         per `CHECKPOINT_INTERVAL`, so a vault acting on every block cannot grow the ring.
    function checkpointAlpha(uint256 id, int256 cumulativeAlpha) external {
        if (strategyVault[id] != msg.sender) revert Unauthorized();
        alphaAccumulator[id] = cumulativeAlpha;
        AlphaHistory storage h = _alphaHistory[id];
        if (h.count == 0 || block.timestamp - _newestTs(h) >= CHECKPOINT_INTERVAL) {
            h.samples[h.head] = Checkpoint({ts: uint64(block.timestamp), cumulativeAlpha: cumulativeAlpha});
            h.head = h.head + 1 == MAX_CHECKPOINTS ? 0 : h.head + 1;
            if (h.count < MAX_CHECKPOINTS) h.count += 1;
        }
        emit AlphaCheckpointed(id, cumulativeAlpha);
    }

    /// @notice Per-interval alpha over the lookback window: the vault's live accumulator minus the
    ///         oldest sample still inside the window. The anchor is the newest sample when every
    ///         retained sample predates the window (a dormant strategy), which yields zero.
    function getAlpha(uint256 id) public view returns (int256) {
        AlphaHistory storage h = _alphaHistory[id];
        uint256 n = h.count;
        if (n == 0) return 0;
        uint256 cutoff = block.timestamp > ALPHA_LOOKBACK ? block.timestamp - ALPHA_LOOKBACK : 0;
        uint256 oldest = _oldestIndex(h);
        uint256 anchor = _newestIndex(h);
        for (uint256 i = 0; i < n; i++) {
            uint256 idx = oldest + i;
            if (idx >= MAX_CHECKPOINTS) idx -= MAX_CHECKPOINTS;
            if (h.samples[idx].ts >= cutoff) {
                anchor = idx;
                break;
            }
        }
        return alphaAccumulator[id] - h.samples[anchor].cumulativeAlpha;
    }

    /// @notice Number of samples currently retained for a strategy (hard-bounded by `MAX_CHECKPOINTS`).
    function alphaSamples(uint256 id) external view returns (uint256) {
        return _alphaHistory[id].count;
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

    /// @dev Index of the oldest valid sample. While the ring is not yet full, samples occupy
    ///      `samples[0..count-1]`; once full, `head` points at the oldest (next write) slot.
    function _oldestIndex(AlphaHistory storage h) internal view returns (uint256) {
        return h.count < MAX_CHECKPOINTS ? 0 : h.head;
    }

    /// @dev Index of the newest valid sample. Only meaningful when `count > 0`.
    function _newestIndex(AlphaHistory storage h) internal view returns (uint256 idx) {
        idx = _oldestIndex(h) + h.count - 1;
        if (idx >= MAX_CHECKPOINTS) idx -= MAX_CHECKPOINTS;
    }

    function _newestTs(AlphaHistory storage h) internal view returns (uint64) {
        return h.samples[_newestIndex(h)].ts;
    }
}
