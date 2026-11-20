// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {RudderIntegrationBase} from "./RudderIntegrationBase.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {FullMath} from "v4-core/libraries/FullMath.sol";
import {Envelope} from "../src/libraries/EnvelopeLib.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title EvidenceTest
/// @notice Measures the numbers cited in the README and writes each measurement under evidence/.
contract EvidenceTest is RudderIntegrationBase {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    uint256 internal constant BIG = 10_000e18;
    uint256 internal clock;

    function _advance(uint256 spacing) internal {
        if (clock == 0) clock = block.timestamp;
        clock += spacing;
        vm.warp(clock);
    }

    function _sample(uint256 amount, uint256 spacing) internal {
        _swap(true, -int256(amount));
        _advance(spacing);
    }

    function _sampleAt(PoolKey memory pool, bool zeroForOne, uint256 amount, uint256 spacing) internal {
        uint160 limit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        router.swap(pool, zeroForOne, -int256(amount), limit);
        _advance(spacing);
    }

    function _tick(PoolKey memory pool) internal view returns (int24 tick) {
        (, tick,,) = IPoolManager(address(manager)).getSlot0(pool.toId());
    }

    function _consultGas() internal view returns (uint256 gasUsed) {
        uint256 start = gasleft();
        hook.consult(key, hook.TWAP_WINDOW());
        gasUsed = start - gasleft();
    }

    function _deviationBps(uint160 a, uint160 b) internal pure returns (uint256) {
        uint256 diff = a > b ? uint256(a - b) : uint256(b - a);
        return FullMath.mulDiv(diff, 10_000, b);
    }

    function _abs(int256 x) internal pure returns (uint256) {
        return x < 0 ? uint256(-x) : uint256(x);
    }

    function _navChangeBps(uint256 beforeNav, uint256 afterNav) internal pure returns (int256) {
        if (beforeNav == 0) return 0;
        if (afterNav >= beforeNav) return int256(FullMath.mulDiv(afterNav - beforeNav, 10_000, beforeNav));
        return -int256(FullMath.mulDiv(beforeNav - afterNav, 10_000, beforeNav));
    }

    function _newVault(Envelope memory env) internal returns (RudderVault v) {
        vm.prank(curator);
        uint256 id = registry.registerStrategy(env);
        vm.prank(curator);
        v = RudderVault(factory.createVault(id, key, 1000));
    }

    function _fundVault(RudderVault v, address who, uint256 amount0, uint256 amount1) internal {
        token0.mint(who, amount0);
        token1.mint(who, amount1);
        vm.startPrank(who);
        IERC20(address(token0)).approve(address(v), type(uint256).max);
        IERC20(address(token1)).approve(address(v), type(uint256).max);
        vm.stopPrank();
    }

    function _seed(RudderVault v, address who, int24 lo, int24 hi, uint256 amount) internal {
        vm.prank(curator);
        v.rebalance(lo, hi);
        token0.mint(who, amount);
        token1.mint(who, amount);
        vm.startPrank(who);
        IERC20(address(token0)).approve(address(v), type(uint256).max);
        IERC20(address(token1)).approve(address(v), type(uint256).max);
        vm.stopPrank();
        vm.prank(who);
        v.deposit(amount, amount, who);
    }

    function test_OracleGasEvidence() public {
        _seed(vault, alice, -600, 600, BIG);
        _sample(1e6, 10);
        _sample(1e6, 10);

        uint256 earlyGas = _consultGas();
        uint256 earlyCount = hook.observationCount(key);
        uint16 capacity = hook.CAPACITY();

        while (hook.observationCount(key) < capacity) {
            _sample(1, 1);
        }

        uint256 lateGas = _consultGas();
        (uint32 lastTs,) = hook.getLastObservation(key);
        string memory obj = "oracleGas";
        vm.serializeUint(obj, "earlyGas", earlyGas);
        vm.serializeUint(obj, "lateGas", lateGas);
        vm.serializeUint(obj, "earlyObservations", earlyCount);
        vm.serializeUint(obj, "lateObservations", hook.observationCount(key));
        vm.serializeUint(obj, "capacity", capacity);
        vm.serializeUint(obj, "twapWindow", hook.TWAP_WINDOW());
        vm.serializeUint(obj, "maxObservationAge", hook.MAX_OBSERVATION_AGE());
        vm.serializeUint(obj, "lastObservationAge", block.timestamp - lastTs);
        string memory json = vm.serializeBool(obj, "oracleReady", hook.isOracleReady(key));
        vm.writeJson(json, "evidence/oracle_gas.json");

        assertEq(hook.observationCount(key), capacity, "ring must reach capacity");
        assertTrue(hook.isOracleReady(key), "oracle must stay ready");
    }

    function test_TwapAccuracyEvidence() public {
        PoolKey memory pool = PoolKey({
            currency0: key.currency0, currency1: key.currency1, fee: 15_000, tickSpacing: 60, hooks: key.hooks
        });
        manager.initialize(pool, TickMath.getSqrtPriceAtTick(0));
        vm.prank(curator);
        uint256 id = registry.registerStrategy(_envelope());
        vm.prank(curator);
        RudderVault v = RudderVault(factory.createVault(id, pool, 1000));
        _seed(v, bob, -3000, 3000, 100_000e18);

        int24 minTick = _tick(pool);
        int24 maxTick = minTick;
        for (uint256 i = 0; i < 25; i++) {
            _sampleAt(pool, i % 2 == 0, 1e6, 60);
            int24 observed = _tick(pool);
            if (observed < minTick) minTick = observed;
            if (observed > maxTick) maxTick = observed;
        }
        int24 startTick = _tick(pool);

        _sampleAt(pool, false, 30_400e18, 0);
        int24 pushedTick = _tick(pool);
        if (pushedTick < minTick) minTick = pushedTick;
        if (pushedTick > maxTick) maxTick = pushedTick;

        for (uint256 i = 0; i < 5; i++) {
            _sampleAt(pool, i % 2 == 0, 1e6, 60);
            int24 observed = _tick(pool);
            if (observed < minTick) minTick = observed;
            if (observed > maxTick) maxTick = observed;
        }

        int24 spotTick = _tick(pool);
        uint160 twapSqrt = hook.consult(pool, hook.TWAP_WINDOW());
        int24 twapTick = TickMath.getTickAtSqrtPrice(twapSqrt);
        string memory obj = "twapAccuracy";
        vm.serializeInt(obj, "startTick", startTick);
        vm.serializeInt(obj, "pushedTick", pushedTick);
        vm.serializeInt(obj, "spotTick", spotTick);
        vm.serializeInt(obj, "twapTick", twapTick);
        vm.serializeInt(obj, "minObservedTick", minTick);
        vm.serializeInt(obj, "maxObservedTick", maxTick);
        vm.serializeInt(obj, "tickError", int256(spotTick) - int256(twapTick));
        vm.serializeUint(obj, "sqrtDeviationBps", _deviationBps(_sqrtPrice(), twapSqrt));
        vm.serializeUint(obj, "observations", hook.observationCount(pool));
        string memory json = vm.serializeBool(obj, "oracleReady", hook.isOracleReady(pool));
        vm.writeJson(json, "evidence/twap_accuracy.json");

        assertGe(twapTick, minTick, "twap below observed ticks");
        assertLe(twapTick, maxTick, "twap above observed ticks");
    }

    function test_RebalanceBoundsEvidence() public {
        _seed(vault, alice, -600, 600, BIG);
        _sample(1e6, 10);
        _sample(1e6, 10);

        Envelope memory env = registry.getEnvelope(strategyId);
        int24 oldCenter = (vault.tickLower() + vault.tickUpper()) / 2;
        uint160 spot = _sqrtPrice();
        uint160 twap = hook.consult(key, hook.TWAP_WINDOW());
        uint256 preNav = vault.totalAssetsValue();
        uint256 previousRebalance = vault.lastRebalanceTimestamp();
        uint256 earliest = previousRebalance + env.minRebalanceInterval;
        if (block.timestamp < earliest) vm.warp(earliest + 1);
        uint256 elapsed = block.timestamp - previousRebalance;
        vm.prank(curator);
        vault.rebalance(-300, 300);
        uint256 postNav = vault.totalAssetsValue();
        int24 newCenter = (vault.tickLower() + vault.tickUpper()) / 2;

        string memory obj = "rebalanceBounds";
        vm.serializeInt(obj, "lower", vault.tickLower());
        vm.serializeInt(obj, "upper", vault.tickUpper());
        vm.serializeUint(obj, "width", uint256(int256(vault.tickUpper() - vault.tickLower())));
        vm.serializeInt(obj, "centerShift", int256(newCenter) - int256(oldCenter));
        vm.serializeUint(obj, "elapsed", elapsed);
        vm.serializeUint(obj, "spotTwapDeviationBps", _deviationBps(spot, twap));
        vm.serializeInt(obj, "navChangeBps", _navChangeBps(preNav, postNav));
        vm.serializeInt(obj, "maxRangeWidth", env.maxRangeWidth);
        vm.serializeInt(obj, "maxCenterShift", env.maxCenterShift);
        vm.serializeInt(obj, "maxTwapDistanceTicks", env.maxTwapDistanceTicks);
        vm.serializeInt(obj, "maxNavLossBps", env.maxNavLossBps);
        vm.serializeUint(obj, "minRebalanceInterval", env.minRebalanceInterval);
        vm.serializeUint(obj, "maxPriceImpactBps", env.maxPriceImpactBps);
        string memory json = vm.serializeUint(obj, "liquidity", vault.positionLiquidity());
        vm.writeJson(json, "evidence/rebalance_bounds.json");

        assertLe(uint256(int256(vault.tickUpper() - vault.tickLower())), uint256(int256(env.maxRangeWidth)));
        assertLe(_abs(int256(newCenter) - int256(oldCenter)), uint256(int256(env.maxCenterShift)));
        assertGe(elapsed, env.minRebalanceInterval);
    }

    function test_DepositGuardEvidence() public {
        Envelope memory env = _envelope();
        env.maxPriceImpactBps = 500;
        RudderVault v = _newVault(env);
        _seed(v, bob, -3000, 3000, BIG);
        _sample(1e6, 10);
        _sample(1e6, 10);
        assertTrue(hook.isOracleReady(key), "oracle must be ready");

        uint160 twap = hook.consult(key, 1);
        _swap(true, -int256(800e18));
        uint160 manipulated = _sqrtPrice();
        uint256 deviation = _deviationBps(manipulated, twap);
        uint256 cap = env.maxPriceImpactBps < v.PROTOCOL_MAX_PRICE_IMPACT_BPS()
            ? env.maxPriceImpactBps
            : v.PROTOCOL_MAX_PRICE_IMPACT_BPS();

        string memory obj = "depositGuard";
        vm.serializeUint(obj, "deviationBps", deviation);
        vm.serializeUint(obj, "capBps", cap);
        vm.serializeUint(obj, "protocolCapBps", v.PROTOCOL_MAX_PRICE_IMPACT_BPS());
        vm.serializeUint(obj, "observations", hook.observationCount(key));
        vm.serializeBool(obj, "oracleReady", hook.isOracleReady(key));
        string memory json = vm.serializeString(obj, "revertSelector", "SpotTwapDeviation");
        vm.writeJson(json, "evidence/deposit_guard.json");

        assertGt(deviation, cap, "spot must deviate beyond the cap");
        _fundVault(v, alice, BIG, BIG);
        vm.prank(alice);
        vm.expectRevert(RudderVault.SpotTwapDeviation.selector);
        v.deposit(BIG, BIG, alice);
    }

    function test_FlowInvarianceEvidence() public {
        RudderVault small = _newVault(_envelope());
        vm.prank(curator);
        vault.rebalance(-600, 600);
        vm.prank(curator);
        small.rebalance(-600, 600);

        _fund(alice, BIG, BIG);
        _deposit(alice, BIG, BIG);
        _fund(bob, BIG / 100, BIG / 100);
        vm.startPrank(bob);
        IERC20(address(token0)).approve(address(small), type(uint256).max);
        IERC20(address(token1)).approve(address(small), type(uint256).max);
        vm.stopPrank();
        vm.prank(bob);
        small.deposit(BIG / 100, BIG / 100, bob);

        _swap(true, -int256(1e18));
        vm.warp(block.timestamp + 10);
        _swap(true, -int256(1e18));
        vm.warp(block.timestamp + 10);

        _fund(bob, BIG, BIG);
        _deposit(bob, BIG, BIG);
        _fundVault(small, bob, BIG / 100, BIG / 100);
        vm.prank(bob);
        small.deposit(BIG / 100, BIG / 100, bob);

        int256 bigBefore = vault.cumulativeAlpha();
        int256 smallBefore = small.cumulativeAlpha();
        token0.mint(address(vault), 100e18);
        token0.mint(address(small), 1e18);
        _fund(alice, 1e18, 1e18);
        _deposit(alice, 1e18, 1e18);
        _fundVault(small, bob, 1e16, 1e16);
        vm.prank(bob);
        small.deposit(1e16, 1e16, bob);
        int256 bigDelta = vault.cumulativeAlpha() - bigBefore;
        int256 smallDelta = small.cumulativeAlpha() - smallBefore;

        int256 beforeFlows = vault.cumulativeAlpha();
        _fund(bob, BIG, BIG);
        _deposit(bob, BIG, BIG);
        int256 afterDeposit = vault.cumulativeAlpha();
        uint256 shares = vault.balanceOf(bob);
        vm.prank(bob);
        vault.withdraw(shares / 4, bob);
        int256 afterWithdraw = vault.cumulativeAlpha();

        uint256 sizeDiff = _abs(bigDelta - smallDelta);
        uint256 relativeDiffBps = bigDelta == 0 ? 0 : fullDiv(sizeDiff, _abs(bigDelta));
        string memory obj = "flowInvariance";
        vm.serializeInt(obj, "bigAlphaDelta", bigDelta);
        vm.serializeInt(obj, "smallAlphaDelta", smallDelta);
        vm.serializeUint(obj, "relativeDifferenceBps", relativeDiffBps);
        vm.serializeInt(obj, "alphaBeforeFlows", beforeFlows);
        vm.serializeInt(obj, "alphaAfterDeposit", afterDeposit);
        vm.serializeInt(obj, "alphaAfterWithdraw", afterWithdraw);
        vm.serializeInt(obj, "depositAlphaDelta", afterDeposit - beforeFlows);
        string memory json = vm.serializeInt(obj, "withdrawAlphaDelta", afterWithdraw - afterDeposit);
        vm.writeJson(json, "evidence/flow_invariance.json");

        assertGt(bigDelta, 0, "large vault must accrue alpha");
        assertGt(smallDelta, 0, "small vault must accrue alpha");
        assertApproxEqRel(bigDelta, smallDelta, 0.02e18, "alpha must not depend on vault size");
        assertEq(afterDeposit, beforeFlows, "deposit must not change alpha");
        assertEq(afterWithdraw, afterDeposit, "withdraw must not change alpha");
    }

    function _depthVault(uint256 amount) internal {
        RudderVault deep = _newVault(_envelope());
        _seed(deep, address(0x1D0), -600, 600, amount);
    }

    function _baselineDeposit(RudderVault v, address who) internal {
        _fundVault(v, who, 1e18, 1e18);
        vm.prank(who);
        v.deposit(1e18, 1e18, who);
    }

    function _swapOn(PoolKey memory pool, bool zeroForOne, uint256 amount) internal {
        uint160 limit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        router.swap(pool, zeroForOne, -int256(amount), limit);
    }

    function test_RebalanceCostEvidence() public {
        RudderVault v = _newVault(_envelope());
        _seed(v, alice, -600, 600, 100e18);
        _depthVault(100_000e18);
        _sample(1e6, 10);
        _sample(1e6, 10);
        _baselineDeposit(v, bob);

        uint256 navBefore = v.totalAssetsValue();
        int256 alphaBefore = v.cumulativeAlpha();
        (uint256 hold0Before, uint256 hold1Before) = v.totalHold();
        vm.prank(curator);
        v.rebalance(600, 1200);
        uint256 navAfter = v.totalAssetsValue();
        int256 alphaCost = alphaBefore - v.cumulativeAlpha();
        (uint256 hold0After, uint256 hold1After) = v.totalHold();
        bool holdUnchanged = hold0Before == hold0After && hold1Before == hold1After;

        uint256 navLossBps = navBefore > navAfter ? fullDiv(navBefore - navAfter, navBefore) : 0;
        uint256 alphaCostBps = alphaCost > 0 ? fullDiv(uint256(alphaCost), 1e18) : 0;

        string memory obj = "rebalanceAlphaCost";
        vm.serializeUint(obj, "navLossBps", navLossBps);
        vm.serializeUint(obj, "alphaCostBps", alphaCostBps);
        vm.serializeInt(obj, "alphaCostWei", alphaCost);
        string memory json = vm.serializeBool(obj, "holdBasketUnchanged", holdUnchanged);
        vm.writeJson(json, "evidence/rebalance_alpha_cost.json");

        assertTrue(holdUnchanged, "rebalance must not change the hold basket");
        assertGt(alphaCost, 0, "rebalance cost must reduce alpha");
        assertApproxEqRel(
            uint256(alphaCost), FullMath.mulDiv(navBefore - navAfter, 1e18, navBefore), 0.2e18, "cost mismatch"
        );

        PoolKey memory other = PoolKey({
            currency0: key.currency0, currency1: key.currency1, fee: 10_000, tickSpacing: 60, hooks: key.hooks
        });
        manager.initialize(other, SQRT_1_1);
        (RudderVault churn, uint256 churnId) = _newVaultOn(other);
        (RudderVault still, uint256 stillId) = _newVaultOn(key);
        _seed(churn, alice, -600, 600, 100e18);
        _seed(still, alice, -600, 600, 100e18);
        _depthVaultOn(other, 100_000e18);
        _depthVaultOn(key, 100_000e18);
        _readyPool(other);
        _readyPool(key);
        _baselineDeposit(churn, bob);
        _baselineDeposit(still, bob);

        int256 churnStart = registry.getAlpha(churnId);
        int256 stillStart = registry.getAlpha(stillId);
        uint256 summedCost;
        for (uint256 i = 0; i < 3; i++) {
            bool zeroForOne = i % 2 == 0;
            _swapOn(other, zeroForOne, 5e18);
            _swapOn(key, zeroForOne, 5e18);
            vm.warp(block.timestamp + 10);
            int24 lo = zeroForOne ? int24(-1200) : int24(600);
            int24 hi = zeroForOne ? int24(-600) : int24(1200);
            uint256 pre = churn.totalAssetsValue();
            vm.prank(curator);
            churn.rebalance(lo, hi);
            uint256 post = churn.totalAssetsValue();
            summedCost += FullMath.mulDiv(pre > post ? pre - post : 0, 1e18, pre);
            _fundVault(still, address(0x1D0), 1e16, 1e16);
            vm.prank(address(0x1D0));
            still.deposit(1e16, 1e16, address(0x1D0));
        }

        int256 gap = (registry.getAlpha(stillId) - stillStart) - (registry.getAlpha(churnId) - churnStart);
        uint256 summedCostBps = fullDiv(summedCost, 1e18);
        uint256 rankingGapBps = gap > 0 ? fullDiv(uint256(gap), 1e18) : 0;
        string memory churnObj = "churnerAlpha";
        vm.serializeUint(churnObj, "rebalanceCount", 3);
        vm.serializeUint(churnObj, "summedCostBps", summedCostBps);
        vm.serializeUint(churnObj, "rankingGapBps", rankingGapBps);
        string memory churnJson = vm.serializeInt(churnObj, "rankingGapWei", gap);
        vm.writeJson(churnJson, "evidence/churner_alpha.json");

        assertGt(gap, 0, "churner must rank below the static vault");
        assertApproxEqRel(uint256(gap), summedCost, 0.4e18, "ranking gap must match summed cost");
    }

    function _newVaultOn(PoolKey memory pool) internal returns (RudderVault v, uint256 id) {
        vm.prank(curator);
        id = registry.registerStrategy(_envelope());
        vm.prank(curator);
        v = RudderVault(factory.createVault(id, pool, 1000));
    }

    function _depthVaultOn(PoolKey memory pool, uint256 amount) internal {
        (RudderVault deep,) = _newVaultOn(pool);
        _seed(deep, address(0x1D0), -600, 600, amount);
    }

    function _readyPool(PoolKey memory pool) internal {
        _swapOn(pool, true, 1);
        vm.warp(block.timestamp + 10);
        _swapOn(pool, true, 1);
        vm.warp(block.timestamp + 10);
    }

    function fullDiv(uint256 x, uint256 y) internal pure returns (uint256) {
        if (y == 0) return 0;
        return FullMath.mulDiv(x, 10_000, y);
    }
}
