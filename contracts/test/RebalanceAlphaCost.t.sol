// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {RudderIntegrationBase} from "./RudderIntegrationBase.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {FullMath} from "v4-core/libraries/FullMath.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title RebalanceAlphaCostTest
/// @notice Prices the swap cost of a rebalance into alpha. A static comparator follows the same
///         external swaps without moving its range; the gap in ranking scores is the cost charged
///         to the curator.
contract RebalanceAlphaCostTest is RudderIntegrationBase {
    uint256 internal constant SMALL = 100e18;
    uint256 internal constant DEEP = 100_000e18;
    address internal lp = address(0x1D0);

    function _newVaultOn(PoolKey memory pool) internal returns (RudderVault v, uint256 id) {
        vm.prank(curator);
        id = registry.registerStrategy(_envelope());
        vm.prank(curator);
        v = RudderVault(factory.createVault(id, pool, 1000));
    }

    function _fundVault(RudderVault v, address who, uint256 amount0, uint256 amount1) internal {
        token0.mint(who, amount0);
        token1.mint(who, amount1);
        vm.startPrank(who);
        IERC20(address(token0)).approve(address(v), type(uint256).max);
        IERC20(address(token1)).approve(address(v), type(uint256).max);
        vm.stopPrank();
    }

    function _seed(RudderVault v, address who, uint256 amount) internal {
        vm.prank(curator);
        v.rebalance(-3000, 3000);
        _fundVault(v, who, amount, amount);
        vm.prank(who);
        v.deposit(amount, amount, who);
    }

    function _depth(PoolKey memory pool, uint256 amount) internal {
        (RudderVault deep,) = _newVaultOn(pool);
        _seed(deep, lp, amount);
    }

    function _swapOn(PoolKey memory pool, bool zeroForOne, uint256 amount) internal {
        uint160 limit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        router.swap(pool, zeroForOne, -int256(amount), limit);
    }

    function _ready(PoolKey memory pool) internal {
        _swapOn(pool, true, 1);
        vm.warp(block.timestamp + 10);
        _swapOn(pool, true, 1);
        vm.warp(block.timestamp + 10);
    }

    function _baseline(RudderVault v, address who) internal {
        _fundVault(v, who, 1e18, 1e18);
        vm.prank(who);
        v.deposit(1e18, 1e18, who);
    }

    function test_CostlyRebalanceChargesAlphaForNavLoss() public {
        (RudderVault v,) = _newVaultOn(key);
        _seed(v, alice, SMALL);
        _depth(key, DEEP);
        _ready(key);
        _baseline(v, bob);

        uint256 navBefore = v.totalAssetsValue();
        int256 alphaBefore = v.cumulativeAlpha();
        (uint256 hold0Before, uint256 hold1Before) = v.totalHold();

        vm.prank(curator);
        v.rebalance(600, 1200);

        uint256 navAfter = v.totalAssetsValue();
        int256 alphaDelta = v.cumulativeAlpha() - alphaBefore;
        (uint256 hold0After, uint256 hold1After) = v.totalHold();
        assertEq(hold0Before, hold0After, "rebalance must not change the hold basket");
        assertEq(hold1Before, hold1After, "rebalance must not change the hold basket");

        uint256 loss = navBefore > navAfter ? navBefore - navAfter : 0;
        uint256 lossFraction = FullMath.mulDiv(loss, 1e18, navBefore);
        assertGt(lossFraction, 0, "the rebalance must have a measurable cost");
        assertLt(alphaDelta, 0, "alpha must fall by the rebalance cost");
        assertApproxEqRel(uint256(-alphaDelta), lossFraction, 0.2e18, "alpha loss must track NAV loss");
    }

    function test_ChurnerRankingTracksSummedRebalanceCosts() public {
        PoolKey memory other = PoolKey({
            currency0: key.currency0, currency1: key.currency1, fee: 10_000, tickSpacing: 60, hooks: key.hooks
        });
        manager.initialize(other, SQRT_1_1);

        (RudderVault churn, uint256 churnId) = _newVaultOn(key);
        (RudderVault still, uint256 stillId) = _newVaultOn(other);
        _seed(churn, alice, SMALL);
        _seed(still, alice, SMALL);
        _depth(key, DEEP);
        _depth(other, DEEP);
        _ready(key);
        _ready(other);
        _baseline(churn, bob);
        _baseline(still, bob);

        int256 churnStart = registry.getAlpha(churnId);
        int256 stillStart = registry.getAlpha(stillId);
        uint256 summedCost;

        for (uint256 i = 0; i < 3; i++) {
            bool zeroForOne = i % 2 == 0;
            _swapOn(key, zeroForOne, 5e18);
            _swapOn(other, zeroForOne, 5e18);
            vm.warp(block.timestamp + 10);

            int24 lo = zeroForOne ? int24(-1200) : int24(600);
            int24 hi = zeroForOne ? int24(-600) : int24(1200);
            uint256 pre = churn.totalAssetsValue();
            vm.warp(block.timestamp + 10);
            vm.prank(curator);
            churn.rebalance(lo, hi);
            uint256 post = churn.totalAssetsValue();
            summedCost += FullMath.mulDiv(pre > post ? pre - post : 0, 1e18, pre);

            _fundVault(still, lp, 1e16, 1e16);
            vm.prank(lp);
            still.deposit(1e16, 1e16, lp);
        }

        int256 churnAlpha = registry.getAlpha(churnId) - churnStart;
        int256 stillAlpha = registry.getAlpha(stillId) - stillStart;
        int256 gap = stillAlpha - churnAlpha;
        assertGt(gap, 0, "the churner must rank below the static vault");
        assertApproxEqRel(uint256(gap), summedCost, 0.4e18, "ranking gap must track summed costs");
    }

    function test_FirstRebalanceWithoutOracleKeepsBootstrap() public {
        (RudderVault v, uint256 id) = _newVaultOn(key);
        vm.prank(curator);
        v.rebalance(-600, 600);
        assertFalse(hook.isOracleReady(key), "oracle must still be booting");
        assertEq(v.cumulativeAlpha(), 0, "no alpha before an oracle baseline exists");
        assertEq(v.baseNavPerShare(), 0, "no baseline before the oracle is ready");
        assertEq(registry.alphaAccumulator(id), 0, "nothing checkpointed");
    }
}
