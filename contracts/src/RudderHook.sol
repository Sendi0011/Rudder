// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/types/PoolOperation.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

interface IVaultFactory {
    function isVault(address who) external view returns (bool);
}

/// @title RudderHook
contract RudderHook is IHooks, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    error OnlyVault();
    error Paused();
    error Unauthorized();
    error FactoryAlreadySet();

    struct Observation {
        uint32 timestamp;
        uint160 sqrtPriceX96;
    }

    uint256 public constant MIN_OBSERVATIONS = 2;
    uint256 public constant MAX_OBSERVATION_AGE = 1 hours;

    mapping(PoolId => Observation[]) internal _observations;

    IPoolManager public immutable poolManager;
    address public vaultFactory;
    address public owner;
    bool public paused;

    constructor(IPoolManager _manager, address _owner) {
        if (_owner == address(0)) revert Unauthorized();
        poolManager = _manager;
        owner = _owner;
        Hooks.validateHookPermissions(this, getHookPermissions());
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    /// @notice Pause/unpause deposit and rebalance. Withdrawals are never gated by `paused`.
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }

    /// @notice Bind the single vault factory allowed to add liquidity. Callable once.
    function setVaultFactory(address _factory) external onlyOwner {
        if (vaultFactory != address(0)) revert FactoryAlreadySet();
        vaultFactory = _factory;
    }

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert Unauthorized();
        _;
    }

    function isOracleReady(PoolKey calldata key) public view returns (bool) {
        PoolId id = key.toId();
        Observation[] storage obs = _observations[id];
        if (obs.length < MIN_OBSERVATIONS) return false;
        Observation storage last = obs[obs.length - 1];
        if (block.timestamp - last.timestamp > MAX_OBSERVATION_AGE) return false;
        return true;
    }

    function getLastObservation(PoolKey calldata key) external view returns (uint32 ts, uint160 sqrtPriceX96) {
        PoolId id = key.toId();
        Observation[] storage obs = _observations[id];
        if (obs.length == 0) return (0, 0);
        Observation storage last = obs[obs.length - 1];
        return (last.timestamp, last.sqrtPriceX96);
    }

    /// @notice Time-weighted average sqrtPriceX96 over the last `secondsAgo`, built from the
    ///         afterSwap observation ring buffer. Values each stored sample by the duration it
    ///         was the last observed price. Reverts nothing; returns the latest sample if the
    ///         window contains no observations.
    function consult(PoolKey calldata key, uint32 secondsAgo) external view returns (uint160 sqrtPriceX96) {
        Observation[] storage obs = _observations[key.toId()];
        uint256 n = obs.length;
        if (n == 0) return 0;

        uint256 windowStart = block.timestamp > secondsAgo ? block.timestamp - secondsAgo : 0;
        uint256 prevTs = block.timestamp;
        uint256 sumDt;
        uint256 sumWeighted;
        // Walk backwards from newest until we pass the start of the window.
        for (uint256 i = n; i > 0; i--) {
            Observation storage o = obs[i - 1];
            if (o.timestamp <= windowStart) break;
            uint256 dt = prevTs - o.timestamp;
            sumWeighted += uint256(o.sqrtPriceX96) * dt;
            sumDt += dt;
            prevTs = o.timestamp;
        }
        if (sumDt == 0) return obs[n - 1].sqrtPriceX96;
        return uint160(sumWeighted / sumDt);
    }

    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function beforeInitialize(address, PoolKey calldata, uint160) external pure returns (bytes4) {
        return IHooks.beforeInitialize.selector;
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure returns (bytes4) {
        return IHooks.afterInitialize.selector;
    }

    function beforeAddLiquidity(address sender, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        onlyPoolManager
        returns (bytes4)
    {
        if (!IVaultFactory(vaultFactory).isVault(sender)) revert OnlyVault();
        if (paused) revert Paused();
        return IHooks.beforeAddLiquidity.selector;
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4, BalanceDelta) {
        return (IHooks.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IHooks.beforeRemoveLiquidity.selector;
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4, BalanceDelta) {
        return (IHooks.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    function beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata)
        external
        pure
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        return (IHooks.beforeSwap.selector, BeforeSwapDelta.wrap(0), 0);
    }

    function afterSwap(address, PoolKey calldata key, SwapParams calldata, BalanceDelta, bytes calldata)
        external
        onlyPoolManager
        returns (bytes4, int128)
    {
        PoolId id = key.toId();
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(id);
        Observation[] storage obs = _observations[id];
        if (obs.length == 0 || (block.timestamp != obs[obs.length - 1].timestamp)) {
            obs.push(Observation({timestamp: uint32(block.timestamp), sqrtPriceX96: sqrtPriceX96}));
            if (obs.length > 1440) {
                for (uint256 i = 0; i < 720; i++) {
                    obs[i] = obs[i + 720];
                }
                assembly {
                    sstore(obs.slot, sub(mload(obs.slot), 720))
                }
            }
        }
        return (IHooks.afterSwap.selector, 0);
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return IHooks.beforeDonate.selector;
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return IHooks.afterDonate.selector;
    }
}
