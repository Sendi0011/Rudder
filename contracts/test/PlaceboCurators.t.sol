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
import {LiquidityLib} from "../src/libraries/LiquidityLib.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract PlaceboCuratorsTest is RudderIntegrationBase {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    uint256 internal constant DEPOSIT = 100e18;
    uint256 internal constant DEPTH = 100_000e18;
    uint256 internal constant STEPS = 8;
    uint256 internal constant SCENARIOS = 6;
    int256 internal constant Z_SCORE_SCALE = 100;

    int256[] internal placeboAlphas;
    int256[SCENARIOS] internal reactiveAlphas;
    int256[SCENARIOS] internal staticAlphas;
    mapping(address => uint256) internal peakRatio;
    mapping(PoolId => bool) internal poolInitialized;
    uint256 internal worstLossBps;
    uint256 internal lossBoundBps;
    uint256 internal maxDrawdownBps;

    function test_PlaceboCuratorDistribution() public {
        uint256 k = vm.envOr("K", uint256(30));
        require(k > 0 && k <= 30, "K must be between 1 and 30");

        Envelope memory conservative = Envelope({
            maxRangeWidth: 600,
            maxCenterShift: 120,
            maxTwapDistanceTicks: 600,
            minRebalanceInterval: 60,
            maxPriceImpactBps: 1000,
            maxNavLossBps: -100,
            maxDailyNavLossBps: 200
        });
        Envelope memory widest = _envelope();

        PoolKey memory trending = _pool(100);
        PoolKey memory choppy = _pool(500);
        PoolKey memory jump = _pool(10_000);

        _runScenario(0, trending, conservative, uint256(keccak256("trending")), 0, k);
        _runScenario(1, trending, widest, uint256(keccak256("trending")), 1, k);
        _runScenario(2, choppy, conservative, uint256(keccak256("choppy")), 0, k);
        _runScenario(3, choppy, widest, uint256(keccak256("choppy")), 1, k);
        _runScenario(4, jump, conservative, uint256(keccak256("jump")), 0, k);
        _runScenario(5, jump, widest, uint256(keccak256("jump")), 1, k);

        int256 reactiveMean = _mean(reactiveAlphas);
        int256 staticMean = _mean(staticAlphas);
        (int256 pMean, uint256 pStd, int256 pMin, int256 pMax, int256 p25, int256 p50, int256 p75) =
            _stats(placeboAlphas);
        bool reactiveWins = reactiveMean > pMean;
        int256 zScoreTimes100 = pStd == 0 ? int256(0) : ((reactiveMean - pMean) * Z_SCORE_SCALE) / int256(pStd);

        string memory obj = "placeboCurators";
        vm.serializeUint(obj, "k", k);
        vm.serializeUint(obj, "placeboSamples", placeboAlphas.length);
        vm.serializeUint(obj, "regimes", uint256(3));
        vm.serializeUint(obj, "envelopes", uint256(2));
        vm.serializeInt(obj, "reactiveMeanBps", reactiveMean);
        vm.serializeInt(obj, "staticMeanBps", staticMean);
        vm.serializeInt(obj, "placeboMeanBps", pMean);
        vm.serializeUint(obj, "zScoreScale", uint256(Z_SCORE_SCALE));
        vm.serializeInt(obj, "reactiveVsPlaceboZScoreTimes100", zScoreTimes100);
        vm.serializeUint(obj, "placeboStdBps", pStd);
        vm.serializeInt(obj, "placeboMinBps", pMin);
        vm.serializeInt(obj, "placeboMaxBps", pMax);
        vm.serializeInt(obj, "placeboP25Bps", p25);
        vm.serializeInt(obj, "placeboP50Bps", p50);
        vm.serializeInt(obj, "placeboP75Bps", p75);
        vm.serializeBool(obj, "reactiveBeatsPlaceboMean", reactiveWins);
        vm.serializeUint(obj, "worstRebalanceLossBps", worstLossBps);
        vm.serializeUint(obj, "lossBoundBps", lossBoundBps);
        string memory json = vm.serializeUint(obj, "maxDrawdownVsHoldBps", maxDrawdownBps);
        if (vm.envOr("WRITE_EVIDENCE", uint256(0)) != 0) {
            vm.writeJson(json, "evidence/placebo_curators.json");
        }

        assertGt(placeboAlphas.length, 0, "placebo sample must not be empty");
        assertLe(worstLossBps, lossBoundBps, "rebalance loss must fit the compounded envelope bound");
    }

    function _pool(uint24 fee) internal view returns (PoolKey memory pool) {
        pool =
            PoolKey({currency0: key.currency0, currency1: key.currency1, fee: fee, tickSpacing: 60, hooks: key.hooks});
    }

    function _runScenario(
        uint256 index,
        PoolKey memory pool,
        Envelope memory env,
        uint256 seed,
        uint256 regime,
        uint256 k
    ) internal {
        PoolId id = pool.toId();
        if (!poolInitialized[id]) {
            manager.initialize(pool, SQRT_1_1);
            poolInitialized[id] = true;
        }
        _depthVault(pool, env);
        _readyPool(pool);

        uint256 start = block.timestamp;
        (RudderVault staticVault, uint256 staticId) = _newVault(pool, env);
        _seedVault(staticVault);
        (RudderVault reactiveVault, uint256 reactiveId) = _newVault(pool, env);
        _seedVault(reactiveVault);
        int256 staticStart = registry.getAlpha(staticId);
        int256 reactiveStart = registry.getAlpha(reactiveId);
        peakRatio[address(staticVault)] = 1e18;
        peakRatio[address(reactiveVault)] = 1e18;

        RudderVault[] memory placebos = new RudderVault[](k);
        uint256[] memory placeboIds = new uint256[](k);
        int256[] memory placeboStarts = new int256[](k);
        for (uint256 i = 0; i < k; i++) {
            (placebos[i], placeboIds[i]) = _newVault(pool, env);
            _seedVault(placebos[i]);
            placeboStarts[i] = registry.getAlpha(placeboIds[i]);
            peakRatio[address(placebos[i])] = 1e18;
        }

        for (uint256 step = 0; step < STEPS; step++) {
            bool direction = _direction(regime, step);
            uint256 amount = regime == 2 && step == 3 ? 20e18 : 5e18;
            _swapOn(pool, direction, amount);
            vm.warp(block.timestamp + env.minRebalanceInterval);

            staticVault.pokeAlpha();
            reactiveVault.pokeAlpha();
            for (uint256 i = 0; i < k; i++) {
                placebos[i].pokeAlpha();
            }

            int24 center = _reactiveCenter(reactiveVault, pool, env, regime, step, direction);
            _tryRebalance(reactiveVault, pool, center);
            _observe(reactiveVault, pool);

            for (uint256 i = 0; i < k; i++) {
                uint256 r = uint256(keccak256(abi.encode(seed, step, i)));
                if (r % 3 == 0) {
                    center = _placeboCenter(placebos[i], pool, env, r >> 8);
                    _tryRebalance(placebos[i], pool, center);
                }
                _observe(placebos[i], pool);
            }
            _observe(staticVault, pool);
        }

        staticAlphas[index] = _bps(registry.getAlpha(staticId) - staticStart);
        reactiveAlphas[index] = _bps(registry.getAlpha(reactiveId) - reactiveStart);
        for (uint256 i = 0; i < k; i++) {
            placeboAlphas.push(_bps(registry.getAlpha(placeboIds[i]) - placeboStarts[i]));
        }

        uint256 elapsed = block.timestamp - start;
        uint256 count = elapsed / env.minRebalanceInterval + 1;
        uint256 scenarioBound = _compoundBound(_abs(env.maxNavLossBps), count);
        if (scenarioBound > lossBoundBps) lossBoundBps = scenarioBound;
    }

    function _direction(uint256 regime, uint256 step) internal pure returns (bool) {
        if (regime == 1) return step % 2 == 0;
        if (regime == 2) return step == 3;
        return true;
    }

    function _newVault(PoolKey memory pool, Envelope memory env) internal returns (RudderVault v, uint256 id) {
        vm.prank(curator);
        id = registry.registerStrategy(env);
        vm.prank(curator);
        v = RudderVault(factory.createVault(id, pool, 1000));
    }

    function _seedVault(RudderVault v) internal {
        vm.prank(curator);
        v.rebalance(-300, 300);
        token0.mint(alice, DEPOSIT);
        token1.mint(alice, DEPOSIT);
        vm.startPrank(alice);
        IERC20(address(token0)).approve(address(v), type(uint256).max);
        IERC20(address(token1)).approve(address(v), type(uint256).max);
        vm.stopPrank();
        vm.prank(alice);
        v.deposit(DEPOSIT, DEPOSIT, alice);
    }

    function _depthVault(PoolKey memory pool, Envelope memory env) internal {
        (RudderVault deep,) = _newVault(pool, env);
        _seedVault(deep);
    }

    function _readyPool(PoolKey memory pool) internal {
        _swapOn(pool, true, 1e12);
        vm.warp(block.timestamp + 10);
        _swapOn(pool, false, 1e12);
        vm.warp(block.timestamp + 10);
    }

    function _swapOn(PoolKey memory pool, bool zeroForOne, uint256 amount) internal {
        uint160 limit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        router.swap(pool, zeroForOne, int256(amount), limit);
    }

    function _reactiveCenter(
        RudderVault v,
        PoolKey memory pool,
        Envelope memory env,
        uint256 regime,
        uint256 step,
        bool direction
    ) internal view returns (int24) {
        if (regime == 2 && step != 3) return _currentCenter(v);
        int256 magnitude = int256(uint256(uint24(env.maxCenterShift)));
        if (magnitude > 600) magnitude = 600;
        magnitude = (magnitude / 60) * 60;
        int256 delta = direction ? magnitude : -magnitude;
        return _clampCenter(_currentCenter(v) + int24(delta), pool, env);
    }

    function _placeboCenter(RudderVault v, PoolKey memory pool, Envelope memory env, uint256 random)
        internal
        view
        returns (int24)
    {
        uint256 span = uint256(uint24(env.maxCenterShift));
        if (span > 600) span = 600;
        uint256 units = span / 60;
        if (units == 0) return _currentCenter(v);
        int256 steps = int256(random % (2 * units + 1)) - int256(units);
        return _clampCenter(_currentCenter(v) + int24(steps * 60), pool, env);
    }

    function _currentCenter(RudderVault v) internal view returns (int24) {
        return (v.tickLower() + v.tickUpper()) / 2;
    }

    function _align(int24 tick) internal pure returns (int24) {
        return int24((int256(tick) / 60) * 60);
    }

    function _clampCenter(int24 center, PoolKey memory pool, Envelope memory env) internal view returns (int24) {
        uint160 twap = hook.consult(pool, hook.TWAP_WINDOW());
        int24 twapTick = TickMath.getTickAtSqrtPrice(twap);
        int24 limit = env.maxTwapDistanceTicks;
        if (center > twapTick + limit) return _align(twapTick + limit);
        if (center < twapTick - limit) return _align(twapTick - limit);
        return _align(center);
    }

    function _tryRebalance(RudderVault v, PoolKey memory pool, int24 center) internal {
        uint256 pre = v.totalAssetsValue();
        vm.prank(curator);
        v.rebalance(center - 300, center + 300);
        uint256 post = v.totalAssetsValue();
        uint256 loss = pre > post ? FullMath.mulDiv(pre - post, 10_000, pre) : 0;
        if (loss > worstLossBps) worstLossBps = loss;
        _observe(v, pool);
    }

    function _observe(RudderVault v, PoolKey memory pool) internal {
        uint256 value = v.totalAssetsValue();
        (uint256 hold0, uint256 hold1) = v.totalHold();
        (uint160 spot,,,) = IPoolManager(address(manager)).getSlot0(pool.toId());
        uint256 holdValue = LiquidityLib.valueInToken0(hold0, hold1, spot);
        if (holdValue == 0) return;
        uint256 ratio = FullMath.mulDiv(value, 1e18, holdValue);
        uint256 peak = peakRatio[address(v)];
        if (ratio > peak) {
            peakRatio[address(v)] = ratio;
            return;
        }
        uint256 drawdown = FullMath.mulDiv(peak - ratio, 10_000, peak);
        if (drawdown > maxDrawdownBps) maxDrawdownBps = drawdown;
    }

    function _bps(int256 alpha) internal pure returns (int256) {
        uint256 magnitude = _abs(alpha);
        uint256 bps = FullMath.mulDiv(magnitude, 10_000, 1e18);
        return alpha < 0 ? -int256(bps) : int256(bps);
    }

    function _abs(int256 value) internal pure returns (uint256) {
        return value < 0 ? uint256(-value) : uint256(value);
    }

    function _mean(int256[SCENARIOS] storage values) internal view returns (int256) {
        int256 sum;
        for (uint256 i = 0; i < SCENARIOS; i++) {
            sum += values[i];
        }
        return sum / int256(SCENARIOS);
    }

    function _stats(int256[] storage values)
        internal
        returns (int256 mean, uint256 std, int256 min, int256 max, int256 p25, int256 p50, int256 p75)
    {
        uint256 n = values.length;
        require(n > 0, "empty sample");
        int256 sum;
        for (uint256 i = 0; i < n; i++) {
            sum += values[i];
        }
        mean = sum / int256(n);
        uint256 variance;
        for (uint256 i = 0; i < n; i++) {
            int256 diff = values[i] - mean;
            uint256 squared = _abs(diff);
            variance += squared * squared;
        }
        std = _sqrt(variance / n);

        for (uint256 i = 1; i < n; i++) {
            int256 current = values[i];
            uint256 j = i;
            while (j > 0 && values[j - 1] > current) {
                values[j] = values[j - 1];
                j--;
            }
            values[j] = current;
        }
        min = values[0];
        max = values[n - 1];
        p25 = values[((n - 1) * 25) / 100];
        p50 = values[((n - 1) * 50) / 100];
        p75 = values[((n - 1) * 75) / 100];
    }

    function _sqrt(uint256 value) internal pure returns (uint256) {
        if (value == 0) return 0;
        uint256 lo = 1;
        uint256 hi = value;
        while (lo < hi) {
            uint256 mid = lo + (hi - lo) / 2;
            if (mid * mid <= value) lo = mid + 1;
            else hi = mid;
        }
        return lo - 1;
    }

    function _compoundBound(uint256 lossCapBps, uint256 count) internal pure returns (uint256) {
        uint256 surviving = 10_000;
        for (uint256 i = 0; i < count; i++) {
            surviving = FullMath.mulDiv(surviving, 10_000 - lossCapBps, 10_000);
        }
        return 10_000 - surviving;
    }
}
