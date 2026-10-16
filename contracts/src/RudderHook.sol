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
/// @notice Gates vault liquidity and maintains a manipulation-resistant TWAP. Prices are sampled in
///         `beforeSwap` (the pre-swap price), so a swap can never choose the price it is recorded at;
///         intra-block pushes are collapsed to a single sample per timestamp so a same-block
///         push-and-reverse cannot move the oracle.
contract RudderHook is IHooks, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    error OnlyVault();
    error Paused();
    error Unauthorized();
    error FactoryAlreadySet();

    uint16 public constant CAPACITY = 2048;
    uint256 public constant MIN_OBSERVATIONS = 2;

    struct Observation {
        uint32 timestamp;
        uint160 sqrtPriceX96;
    }

    /// @dev Fixed-capacity ring buffer per pool. Storage is only paid for the slots actually written.
    struct Oracle {
        Observation[CAPACITY] buf;
        uint16 next;
        uint16 count;
    }

    uint256 public constant MAX_OBSERVATION_AGE = 1 hours;

    mapping(PoolId => Oracle) internal _oracle;

    IPoolManager public immutable poolManager;
    /// @notice The factory whose vaults are allowed to add liquidity. Set exactly once by `owner`.
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

    /// @notice Bind the vault factory. Callable once by the owner; keeps the hook's factory link
    ///         from being front-run or replaced.
    function setVaultFactory(address _factory) external onlyOwner {
        if (vaultFactory != address(0)) revert FactoryAlreadySet();
        vaultFactory = _factory;
    }

    /// @notice Pause/unpause deposit and rebalance. Withdrawals are never gated by `paused`.
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert Unauthorized();
        _;
    }

    // ---------------------------------------------------------------------
    // Oracle
    // ---------------------------------------------------------------------

    function isOracleReady(PoolKey calldata key) public view returns (bool) {
        Oracle storage o = _oracle[key.toId()];
        if (o.count < MIN_OBSERVATIONS) return false;
        Observation storage last = _newest(o);
        if (block.timestamp - last.timestamp > MAX_OBSERVATION_AGE) return false;
        return true;
    }

    function getLastObservation(PoolKey calldata key) external view returns (uint32 ts, uint160 sqrtPriceX96) {
        Oracle storage o = _oracle[key.toId()];
        if (o.count == 0) return (0, 0);
        Observation storage last = _newest(o);
        return (last.timestamp, last.sqrtPriceX96);
    }

    /// @notice Number of samples currently held for a pool.
    function observationCount(PoolKey calldata key) external view returns (uint256) {
        return _oracle[key.toId()].count;
    }

    /// @notice Time-weighted average sqrtPriceX96 over the last `secondsAgo`. Each sample's price is
    ///         credited for the time until the next sample (or until now for the newest), clamped to
    ///         the window. Returns the newest sample if the window holds no interval.
    function consult(PoolKey calldata key, uint32 secondsAgo) external view returns (uint160 sqrtPriceX96) {
        Oracle storage o = _oracle[key.toId()];
        uint16 count = o.count;
        if (count == 0) return 0;

        uint256 windowStart = block.timestamp > secondsAgo ? block.timestamp - secondsAgo : 0;
        uint16 oldest = _oldestIndex(o);
        uint256 sumWeighted;
        uint256 sumDt;

        for (uint16 k = 0; k < count; k++) {
            uint16 idx = oldest + k;
            if (idx >= CAPACITY) idx -= CAPACITY;

            uint256 tEnd;
            if (k + 1 < count) {
                uint16 nidx = idx + 1;
                if (nidx >= CAPACITY) nidx -= CAPACITY;
                tEnd = o.buf[nidx].timestamp;
            } else {
                tEnd = block.timestamp;
            }
            if (tEnd <= windowStart) continue;

            uint256 tStart = o.buf[idx].timestamp > windowStart ? o.buf[idx].timestamp : windowStart;
            if (tEnd <= tStart) continue;

            uint256 dt = tEnd - tStart;
            sumWeighted += uint256(o.buf[idx].sqrtPriceX96) * dt;
            sumDt += dt;
        }

        if (sumDt == 0) return _newest(o).sqrtPriceX96;
        return uint160(sumWeighted / sumDt);
    }

    function _record(PoolKey calldata key) internal {
        PoolId id = key.toId();
        Oracle storage o = _oracle[id];

        // One sample per timestamp: the first swap of a block fixes the sample at the pre-swap
        // price, and any later swap in the same block cannot overwrite it.
        if (o.count > 0 && _newest(o).timestamp == uint32(block.timestamp)) return;

        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(id);
        o.buf[o.next] = Observation({timestamp: uint32(block.timestamp), sqrtPriceX96: sqrtPriceX96});
        o.next = o.next + 1 == CAPACITY ? 0 : o.next + 1;
        if (o.count < CAPACITY) o.count += 1;
    }

    function _newest(Oracle storage o) internal view returns (Observation storage) {
        uint16 idx = o.next == 0 ? CAPACITY - 1 : o.next - 1;
        return o.buf[idx];
    }

    function _oldestIndex(Oracle storage o) internal view returns (uint16) {
        if (o.count < CAPACITY) return 0;
        return o.next;
    }

    // ---------------------------------------------------------------------
    // Hook permissions and callbacks
    // ---------------------------------------------------------------------

    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
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

    /// @dev Records the pre-swap price. Runs before the swap executes, so the sample is the price
    ///      that was already in force, never one the caller produced.
    function beforeSwap(address, PoolKey calldata key, SwapParams calldata, bytes calldata)
        external
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        _record(key);
        return (IHooks.beforeSwap.selector, BeforeSwapDelta.wrap(0), 0);
    }

    function afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata)
        external
        pure
        returns (bytes4, int128)
    {
        return (IHooks.afterSwap.selector, 0);
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return IHooks.beforeDonate.selector;
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return IHooks.afterDonate.selector;
    }
}
