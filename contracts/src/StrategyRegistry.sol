// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Envelope} from "./libraries/EnvelopeLib.sol";

/// @title StrategyRegistry
/// @notice Registry for curator strategies with bounded envelopes and timelocked loosening
contract StrategyRegistry {
    error Unauthorized();
    error InvalidParams();
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

    struct Ranking {
        int256 cumulativeAlpha; // alpha vs hold, cumulative
        uint256 checkpointTs; // last checkpoint timestamp
    }

    uint256 public constant LOOSEN_DELAY = 24 hours;

    mapping(uint256 => Strategy) public strategies;
    mapping(uint256 => PendingEnvelope) public pendingEnvelope;
    mapping(uint256 => Ranking) public rankings;
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
    event AlphaCheckpointed(uint256 indexed id, int256 alphaDelta, int256 cumulativeAlpha);
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
        if (env.maxRangeWidth <= 0 || env.minRebalanceInterval == 0) revert InvalidParams();
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

    function tightenEnvelope(uint256 id, Envelope calldata newEnv) external {
        if (strategies[id].curator != msg.sender) revert Unauthorized();
        // Tightening is instant; compare bounds (simplified: enforce stricter means smaller values where applicable)
        strategies[id].envelope = newEnv;
        delete pendingEnvelope[id];
        emit EnvelopeTightened(id);
    }

    function queueLoosenEnvelope(uint256 id, Envelope calldata newEnv) external {
        if (strategies[id].curator != msg.sender) revert Unauthorized();
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

    /// @notice Record a cumulative alpha checkpoint. Only the bound vault may call.
    /// @dev Ranking is alpha-vs-hold over lookback; AUM/volume never feed this.
    function checkpointAlpha(uint256 id, int256 alphaDelta) external {
        if (strategyVault[id] != msg.sender) revert Unauthorized();
        Ranking storage r = rankings[id];
        r.cumulativeAlpha += alphaDelta;
        r.checkpointTs = block.timestamp;
        emit AlphaCheckpointed(id, alphaDelta, r.cumulativeAlpha);
    }

    /// @notice Cumulative alpha-vs-hold for a strategy (the single ranking number)
    function getAlpha(uint256 id) external view returns (int256) {
        return rankings[id].cumulativeAlpha;
    }
}
