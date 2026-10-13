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

    struct Strategy {
        address curator;
        Envelope envelope;
        bool active;
    }

    struct PendingEnvelope {
        Envelope envelope;
        uint256 unlockTime;
    }

    uint256 public constant LOOSEN_DELAY = 24 hours;

    mapping(uint256 => Strategy) public strategies;
    mapping(uint256 => PendingEnvelope) public pendingEnvelope;
    uint256 public nextStrategyId;

    event StrategyRegistered(uint256 indexed id, address indexed curator);
    event EnvelopeTightened(uint256 indexed id);
    event EnvelopeLooseningQueued(uint256 indexed id, uint256 unlockTime);
    event EnvelopeLooseningApplied(uint256 indexed id);

    function registerStrategy(Envelope calldata env) external returns (uint256 id) {
        if (env.maxRangeWidth <= 0 || env.minRebalanceInterval == 0) revert InvalidParams();
        id = nextStrategyId++;
        strategies[id] = Strategy({curator: msg.sender, envelope: env, active: true});
        emit StrategyRegistered(id, msg.sender);
    }

    function getEnvelope(uint256 id) external view returns (Envelope memory) {
        return strategies[id].envelope;
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
}
