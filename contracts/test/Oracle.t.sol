// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {RudderIntegrationBase} from "./RudderIntegrationBase.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {TestERC20} from "v4-core/test/TestERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract DecimalsToken is TestERC20 {
    uint8 private immutable tokenDecimals;

    constructor(uint256 supply, uint8 decimals_) TestERC20(supply) {
        tokenDecimals = decimals_;
    }

    function decimals() external view returns (uint8) {
        return tokenDecimals;
    }
}

/// @title OracleTest
/// @notice Values the hook's cumulative-tick oracle on pools away from tick 0: constant-price TWAPs,
///         step changes, interpolation, ring wrap-around, fuzz bounds and mixed-decimal assets.
contract OracleTest is RudderIntegrationBase {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    uint256 internal constant DEP = 100_000e18;
    uint16 internal constant CAPACITY = 2048;
    address internal lp = address(0x1D0);

    function _prime() internal {
        vm.prank(curator);
        uint256 id = registry.registerStrategy(_envelope());
        vm.prank(curator);
        RudderVault v = RudderVault(factory.createVault(id, key, 1000));
        vm.prank(curator);
        v.rebalance(-3000, 3000);
        token0.mint(lp, DEP);
        token1.mint(lp, DEP);
        vm.startPrank(lp);
        IERC20(address(token0)).approve(address(v), type(uint256).max);
        IERC20(address(token1)).approve(address(v), type(uint256).max);
        vm.stopPrank();
        vm.prank(lp);
        v.deposit(DEP, DEP, lp);
    }

    /// @dev Record exactly one sample at the current block, then advance the clock so the next swap
    ///      records again.
    function _sample() internal {
        _swap(true, -int256(1e6));
        vm.warp(block.timestamp + 1);
    }

    function _consultGas() internal view returns (uint256 g) {
        uint256 start = gasleft();
        hook.consult(key, 1800);
        g = start - gasleft();
    }

    function test_ConsultRequiresTwoSamples() public {
        _prime();
        assertEq(hook.observationCount(key), 0, "no samples before any swap");
        assertEq(hook.consult(key, 1800), 0, "no samples -> no twap");

        _sample();
        assertEq(hook.observationCount(key), 1, "one sample recorded");
        assertEq(hook.consult(key, 1800), 0, "one sample -> no twap");

        _sample();
        assertEq(hook.observationCount(key), 2, "two samples recorded");
        assertGt(hook.consult(key, 1800), 0, "two samples -> twap");
    }

    /// @notice A same-block push and reverse still records only the pre-swap price.
    function test_OneSamplePerBlock() public {
        _prime();
        _swap(true, -int256(1));
        _swap(false, -int256(1));
        _swap(true, -int256(1));
        assertEq(hook.observationCount(key), 1, "later swaps in the same block must not add samples");
    }

    // ------------------------------------------------------------------
    // pools away from tick 0
    // ------------------------------------------------------------------

    function _altKey(uint24 fee) internal view returns (PoolKey memory alt) {
        alt = PoolKey({currency0: key.currency0, currency1: key.currency1, fee: fee, tickSpacing: 60, hooks: key.hooks});
    }

    function _initAlt(int24 tick, uint24 fee) internal returns (PoolKey memory alt) {
        alt = _altKey(fee);
        manager.initialize(alt, TickMath.getSqrtPriceAtTick(tick));
    }

    function _vaultFor(PoolKey memory pool) internal returns (RudderVault v) {
        vm.prank(curator);
        uint256 id = registry.registerStrategy(_envelope());
        vm.prank(curator);
        v = RudderVault(factory.createVault(id, pool, 1000));
    }

    function _seed(RudderVault v, int24 lo, int24 hi) internal {
        vm.prank(curator);
        v.rebalance(lo, hi);
        token0.mint(lp, DEP);
        token1.mint(lp, DEP);
        vm.startPrank(lp);
        IERC20(address(token0)).approve(address(v), type(uint256).max);
        IERC20(address(token1)).approve(address(v), type(uint256).max);
        vm.stopPrank();
        vm.prank(lp);
        v.deposit(DEP, DEP, lp);
    }

    function _sampleAt(PoolKey memory pool, bool zeroForOne, uint256 amount, uint32 spacing) internal {
        uint160 limit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        router.swap(pool, zeroForOne, -int256(amount), limit);
        vm.warp(block.timestamp + spacing);
    }

    function _tick(PoolKey memory pool) internal view returns (int24) {
        (, int24 t,,) = IPoolManager(address(manager)).getSlot0(pool.toId());
        return t;
    }

    function _twapTick(PoolKey memory pool, uint32 secondsAgo) internal view returns (int24) {
        return TickMath.getTickAtSqrtPrice(hook.consult(pool, secondsAgo));
    }

    function test_ConstantTickHeldThirtyMinutesPositive() public {
        PoolKey memory pool = _initAlt(816, 500);
        _seed(_vaultFor(pool), 600, 1200);

        for (uint256 i = 0; i < 30; i++) {
            _sampleAt(pool, i % 2 == 0, 1e6, 60);
        }

        assertEq(hook.observationCount(pool), 30, "one sample per minute");
        assertApproxEqAbs(int256(_tick(pool)), int256(816), 2, "spot held at the starting tick");
        assertApproxEqAbs(int256(_twapTick(pool, 1800)), int256(816), 2, "thirty-minute twap at 816");
    }

    function test_ConstantTickHeldThirtyMinutesNegative() public {
        PoolKey memory pool = _initAlt(-816, 10_000);
        _seed(_vaultFor(pool), -1200, -600);

        for (uint256 i = 0; i < 30; i++) {
            _sampleAt(pool, i % 2 == 0, 1e6, 60);
        }

        assertApproxEqAbs(int256(_tick(pool)), int256(-816), 2, "spot held at the starting tick");
        assertApproxEqAbs(int256(_twapTick(pool, 1800)), int256(-816), 2, "thirty-minute twap at -816");
    }

    function test_StepFromZeroTo816AveragesAbout136() public {
        PoolKey memory pool = _initAlt(0, 15_000);
        _seed(_vaultFor(pool), -3000, 3000);

        for (uint256 i = 0; i < 25; i++) {
            _sampleAt(pool, i % 2 == 0, 1e6, 60);
        }
        assertApproxEqAbs(int256(_tick(pool)), 0, 2, "first twenty-five minutes at tick 0");

        _sampleAt(pool, false, 30_400e18, 0);
        int24 pushed = _tick(pool);
        emit log_named_int("tick after push", pushed);
        assertApproxEqAbs(int256(pushed), int256(816), 40, "large exact-input swap reaches tick 816");

        for (uint256 i = 0; i < 5; i++) {
            _sampleAt(pool, i % 2 == 0, 1e6, 60);
        }

        int24 twap = _twapTick(pool, 1800);
        emit log_named_int("step twap tick", twap);
        assertApproxEqAbs(int256(twap), int256(136), 2, "twenty-five minutes at 0 plus five at 816");
    }

    function test_WindowStartBetweenSamplesAndLongerThanHistory() public {
        PoolKey memory pool = _initAlt(816, 20_000);
        _seed(_vaultFor(pool), 600, 1200);

        for (uint256 i = 0; i < 30; i++) {
            _sampleAt(pool, i % 2 == 0, 1e6, 60);
        }

        assertApproxEqAbs(int256(_twapTick(pool, 1790)), int256(816), 2, "start between the first two samples");

        PoolKey memory short = _initAlt(-600, 25_000);
        _seed(_vaultFor(short), -1200, 0);
        _sampleAt(short, true, 1e6, 60);
        _sampleAt(short, true, 1e6, 60);
        assertApproxEqAbs(int256(_twapTick(short, 3600)), int256(-600), 2, "window beyond the whole history");
    }

    function test_RingWrapKeepsTheConstantValue() public {
        PoolKey memory pool = _initAlt(816, 30_000);
        _seed(_vaultFor(pool), 600, 1200);

        for (uint256 i = 0; i < uint256(CAPACITY) + 5; i++) {
            _sampleAt(pool, i % 2 == 0, 1e6, 1);
        }

        assertEq(hook.observationCount(pool), CAPACITY, "count caps at capacity");
        (uint32 ts,) = hook.getLastObservation(pool);
        assertEq(ts, uint32(block.timestamp - 1), "newest sample is the most recent block");
        assertApproxEqAbs(int256(_twapTick(pool, 1800)), int256(816), 2, "wrap-around keeps the tick value");
    }

    function test_FuzzTwapBetweenObservedTicks(uint256 seed) public {
        PoolKey memory pool = _initAlt(0, 35_000);
        _seed(_vaultFor(pool), -3000, 3000);

        int24 minTick = _tick(pool);
        int24 maxTick = minTick;
        uint256 x = seed;
        for (uint256 i = 0; i < 12; i++) {
            x = uint256(keccak256(abi.encode(x, i)));
            bool zeroForOne = x & 1 == 0;
            uint256 amount = 1e15 + (x >> 8) % 1e18;
            _sampleAt(pool, zeroForOne, amount, 60);
            int24 observed = _tick(pool);
            if (observed < minTick) minTick = observed;
            if (observed > maxTick) maxTick = observed;
        }
        int24 current = _tick(pool);
        if (current < minTick) minTick = current;
        if (current > maxTick) maxTick = current;

        int24 twap = _twapTick(pool, 1800);
        assertGe(twap, minTick, "twap below the observed range");
        assertLe(twap, maxTick, "twap above the observed range");
    }

    function test_MixedDecimalsNonOneToOneLifecycle() public {
        uint256 supply = 1e30;
        DecimalsToken six = new DecimalsToken(supply, 6);
        DecimalsToken eighteen = new DecimalsToken(supply, 18);
        (DecimalsToken tokenA, DecimalsToken tokenB) =
            address(six) < address(eighteen) ? (six, eighteen) : (eighteen, six);

        PoolKey memory pool = PoolKey({
            currency0: Currency.wrap(address(tokenA)),
            currency1: Currency.wrap(address(tokenB)),
            fee: 40_000,
            tickSpacing: 60,
            hooks: key.hooks
        });
        manager.initialize(pool, TickMath.getSqrtPriceAtTick(-1200));

        uint256 amount0 = 1000e18;
        uint256 amount1 = 1000e18;
        RudderVault v = _vaultFor(pool);
        vm.prank(curator);
        v.rebalance(-1800, -600);
        tokenA.mint(lp, amount0);
        tokenB.mint(lp, amount1);
        tokenA.mint(address(router), amount0);
        tokenB.mint(address(router), amount1);
        vm.startPrank(lp);
        IERC20(address(tokenA)).approve(address(v), type(uint256).max);
        IERC20(address(tokenB)).approve(address(v), type(uint256).max);
        vm.stopPrank();
        vm.prank(lp);
        uint256 shares = v.deposit(amount0, amount1, lp);

        _sampleAt(pool, true, amount0 / 1000, 10);
        _sampleAt(pool, false, amount1 / 1000, 10);
        assertTrue(hook.isOracleReady(pool), "mixed-decimal oracle is ready");
        assertGt(hook.consult(pool, 1800), 0, "mixed-decimal twap exists");

        vm.prank(curator);
        v.rebalance(-1500, -900);
        assertEq(v.tickLower(), -1500);
        assertEq(v.tickUpper(), -900);

        uint256 before0 = IERC20(address(tokenA)).balanceOf(lp);
        uint256 before1 = IERC20(address(tokenB)).balanceOf(lp);
        vm.prank(lp);
        v.withdraw(shares, lp);
        assertEq(v.balanceOf(lp), 0, "all LP shares redeemed");
        assertGt(
            IERC20(address(tokenA)).balanceOf(lp) + IERC20(address(tokenB)).balanceOf(lp),
            before0 + before1,
            "withdrawal returned assets"
        );
        assertEq(v.totalSupply(), 1000, "only the minimum-liquidity lock remains");
    }
}
