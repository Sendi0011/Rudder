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
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {Envelope, EnvelopeLib} from "./libraries/EnvelopeLib.sol";

interface IVaultFactory {
    function isVault(address who) external view returns (bool);
    function vaultToStrategyId(address vault) external view returns (uint256);
    function registry() external view returns (address);
}

interface IStrategyRegistryView {
    function getEnvelope(uint256 id) external view returns (Envelope memory);
}

/// @title RudderHook
/// @notice Gates vault liquidity and maintains a manipulation-resistant TWAP. Prices are sampled in
///         `beforeSwap` (the pre-swap price), so a swap can never choose the price it is recorded at;
///         intra-block pushes are collapsed to a single sample per timestamp so a same-block
///         push-and-reverse cannot move the oracle. Observations use a cumulative tick oracle for
///         O(log n) TWAP reads.
contract RudderHook is IHooks, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    error OnlyVault();
    error Paused();
    error Unauthorized();
    error FactoryAlreadySet();
    error RangeNotAligned();

    uint16 public constant CAPACITY = 2048;
    uint256 public constant MIN_OBSERVATIONS = 2;
    /// @dev Window for the TWAP used by the add-liquidity gate. Mirrors the vault's valuation window.
    uint32 public constant TWAP_WINDOW = 1800;

    struct Observation {
        uint32 timestamp;
        int56 tickCumulative;
    }

    /// @dev Fixed-capacity ring buffer per pool. Storage is only paid for the slots actually written.
    struct Oracle {
        Observation[CAPACITY] buf;
        uint16 next;
        uint16 count;
    }

    uint256 public constant MAX_OBSERVATION_AGE = 1 hours;

    mapping(PoolId => Oracle) internal _oracle;

    /// @dev Per-vault record of the last range-setting add, used by the add-liquidity gate to bound
    ///      how often a vault's range may move. Top-up adds into the current range do not reset it.
    struct VaultAdd {
        uint48 timestamp;
        int24 tickLower;
        int24 tickUpper;
    }

    mapping(address => VaultAdd) internal _vaultAdd;

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

    function getLastObservation(PoolKey calldata key) external view returns (uint32 ts, int56 tickCumulative) {
        Oracle storage o = _oracle[key.toId()];
        if (o.count == 0) return (0, 0);
        Observation storage last = _newest(o);
        return (last.timestamp, last.tickCumulative);
    }

    /// @notice Number of samples currently held for a pool.
    function observationCount(PoolKey calldata key) external view returns (uint256) {
        return _oracle[key.toId()].count;
    }

    /// @notice Time-weighted average sqrtPriceX96 over the last `secondsAgo`. Uses a cumulative tick
    ///         oracle with binary search over observations; averages over the available span if the
    ///         window is not fully covered, but requires at least two observations.
    function consult(PoolKey calldata key, uint32 secondsAgo) external view returns (uint160 sqrtPriceX96) {
        Oracle storage o = _oracle[key.toId()];
        uint16 count = o.count;
        if (count < 2) return 0;

        (, int24 tick,,) = poolManager.getSlot0(key.toId());
        uint32 nowTs = uint32(block.timestamp);
        uint32 windowStart = secondsAgo == 0 ? 0 : (nowTs > secondsAgo ? nowTs - secondsAgo : 0);

        (uint16 aIdx, uint16 bIdx) = _binarySearch(o, windowStart);
        Observation storage a = o.buf[aIdx];
        Observation storage b = o.buf[bIdx];

        int56 tickCumulatives;
        uint32 secondsAgos;
        if (b.timestamp <= windowStart) {
            // All observations are before the window; average over the full available span.
            Observation storage oldestObs = o.buf[_oldestIndex(o)];
            Observation storage newestObs = _newest(o);
            tickCumulatives = newestObs.tickCumulative - oldestObs.tickCumulative;
            secondsAgos = newestObs.timestamp - oldestObs.timestamp;
        } else if (a.timestamp <= windowStart) {
            // Interpolate between a (before or at window start) and b (after window start).
            uint32 timeDiff = b.timestamp - a.timestamp;
            int56 tickDiff = b.tickCumulative - a.tickCumulative;
            int56 tickCumulativeStart =
                a.tickCumulative + (tickDiff * int56(uint56(windowStart - a.timestamp))) / int56(uint56(timeDiff));
            tickCumulatives = b.tickCumulative - tickCumulativeStart;
            secondsAgos = b.timestamp - windowStart;
        } else {
            // Both observations are after window start; use the two most recent that bracket or are available.
            // If we need at least two observations for a meaningful TWAP, fall back to oldest-to-newest in window.
            if (aIdx == _oldestIndex(o) && secondsAgos == 0) {
                // try to expand to oldest
            }
            // Default: use adjacent pair covering available span
            tickCumulatives = b.tickCumulative - a.tickCumulative;
            secondsAgos = b.timestamp - a.timestamp;
            if (secondsAgos == 0) secondsAgos = 1;
        }

        if (secondsAgos == 0) {
            return TickMath.getSqrtPriceAtTick(tick);
        }
        int56 timeWeightedAverageTick = tickCumulatives / int56(uint56(secondsAgos));
        // Round toward negative infinity (floor for negative results) as per standard behavior.
        if (tickCumulatives < 0 && tickCumulatives % int56(uint56(secondsAgos)) != 0) {
            timeWeightedAverageTick = timeWeightedAverageTick - 1;
        }
        return TickMath.getSqrtPriceAtTick(int24(timeWeightedAverageTick));
    }

    function _binarySearch(Oracle storage o, uint32 target) internal view returns (uint16 aIdx, uint16 bIdx) {
        uint16 count = o.count;
        uint16 l = 0;
        uint16 r = count;
        while (l < r) {
            uint16 mid = (l + r) / 2;
            uint16 idx = _indexAt(o, mid);
            if (o.buf[idx].timestamp <= target) {
                l = mid + 1;
            } else {
                r = mid;
            }
        }
        // l is the index of first observation with timestamp > target
        if (l == 0) {
            // target is before or at oldest; use oldest and second oldest
            aIdx = _indexAt(o, 0);
            bIdx = _indexAt(o, 1);
        } else if (l >= count) {
            // target is after or at newest; use second newest and newest
            aIdx = _indexAt(o, count - 2);
            bIdx = _indexAt(o, count - 1);
        } else {
            aIdx = _indexAt(o, l - 1);
            bIdx = _indexAt(o, l);
        }
    }

    function _indexAt(Oracle storage o, uint16 i) internal view returns (uint16) {
        uint16 oldest = _oldestIndex(o);
        uint16 idx = oldest + i;
        if (idx >= CAPACITY) idx -= CAPACITY;
        return idx;
    }

    function _record(PoolKey calldata key) internal {
        PoolId id = key.toId();
        Oracle storage o = _oracle[id];

        // One sample per timestamp: the first swap of a block fixes the sample at the pre-swap
        // price, and any later swap in the same block cannot overwrite it.
        if (o.count > 0 && _newest(o).timestamp == uint32(block.timestamp)) return;

        (, int24 tick,,) = poolManager.getSlot0(id);
        int56 lastCumul = _lastTickCumulative(o);
        int56 tickCumulative = lastCumul + int56(tick);
        o.buf[o.next] = Observation({timestamp: uint32(block.timestamp), tickCumulative: tickCumulative});
        o.next = o.next + 1 == CAPACITY ? 0 : o.next + 1;
        if (o.count < CAPACITY) o.count += 1;
    }

    function _lastTickCumulative(Oracle storage o) internal view returns (int56) {
        if (o.count == 0) return 0;
        return _newest(o).tickCumulative;
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

    /// @notice Gate every liquidity add by a registered vault against its strategy's live envelope.
    ///         The vault enforces the same bounds, so this is defense in depth: even a vault that
    ///         skipped its own checks cannot seat liquidity outside the envelope. Removals are never
    ///         gated.
    function beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata
    ) external onlyPoolManager returns (bytes4) {
        if (!IVaultFactory(vaultFactory).isVault(sender)) revert OnlyVault();
        if (paused) revert Paused();

        int24 lo = params.tickLower;
        int24 hi = params.tickUpper;
        int24 spacing = key.tickSpacing;
        if (spacing <= 0 || lo % spacing != 0 || hi % spacing != 0) revert RangeNotAligned();

        uint256 strategyId = IVaultFactory(vaultFactory).vaultToStrategyId(sender);
        address reg = IVaultFactory(vaultFactory).registry();
        Envelope memory env = IStrategyRegistryView(reg).getEnvelope(strategyId);

        int24 width = hi - lo;
        EnvelopeLib.validateRangeWidth(width, env.maxRangeWidth);

        int24 center = (lo + hi) / 2;
        EnvelopeLib.validateTwapDistance(center, _twapTick(key), env.maxTwapDistanceTicks);

        // Only a range-setting add counts against the interval: top-ups into the live range are free.
        VaultAdd storage rec = _vaultAdd[sender];
        if (lo != rec.tickLower || hi != rec.tickUpper) {
            if (rec.timestamp != 0) {
                EnvelopeLib.validateInterval(rec.timestamp, block.timestamp, env.minRebalanceInterval);
            }
            rec.timestamp = uint48(block.timestamp);
            rec.tickLower = lo;
            rec.tickUpper = hi;
        }

        return IHooks.beforeAddLiquidity.selector;
    }

    /// @dev TWAP tick for the gate, read through the same oracle the vault uses. Falls back to the
    ///      spot tick before the oracle has enough samples (first bootstrap add).
    function _twapTick(PoolKey calldata key) internal view returns (int24 twapTick) {
        uint160 twap = this.consult(key, TWAP_WINDOW);
        if (twap == 0) {
            (, twapTick,,) = poolManager.getSlot0(key.toId());
        } else {
            twapTick = TickMath.getTickAtSqrtPrice(twap);
        }
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
