// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StrategyRegistry} from "../src/StrategyRegistry.sol";
import {Envelope, EnvelopeLib} from "../src/libraries/EnvelopeLib.sol";

contract EnvWrapper {
    function validateRangeWidth(int24 width, int24 maxWidth) external pure {
        EnvelopeLib.validateRangeWidth(width, maxWidth);
    }

    function validateInterval(uint48 lastTs, uint48 nowTs, uint48 minInterval) external pure {
        EnvelopeLib.validateInterval(lastTs, nowTs, minInterval);
    }

    function validatePriceImpact(uint32 impactBps, uint32 maxImpactBps) external pure {
        EnvelopeLib.validatePriceImpact(impactBps, maxImpactBps);
    }

    function validateNavLoss(int24 lossBps, int24 maxLossBps) external pure {
        EnvelopeLib.validateNavLoss(lossBps, maxLossBps);
    }
}

contract RebalanceBoundsTest is Test {
    StrategyRegistry registry;
    EnvWrapper w;

    function setUp() public {
        registry = new StrategyRegistry();
        w = new EnvWrapper();
    }

    function test_RebalanceBounds_TooWideRange() public {
        Envelope memory env = Envelope({
            maxRangeWidth: 100,
            maxCenterShift: 50,
            maxTwapDistanceTicks: 1000,
            minRebalanceInterval: 10,
            maxPriceImpactBps: 100,
            maxNavLossBps: -500,
            maxDailyNavLossBps: 1000
        });
        registry.registerStrategy(env);
        vm.expectRevert(abi.encodeWithSelector(EnvelopeLib.InvalidRangeWidth.selector, 200, 100));
        w.validateRangeWidth(200, 100);
    }

    function test_RebalanceBounds_IntervalTooShort() public {
        Envelope memory env = Envelope({
            maxRangeWidth: 1000,
            maxCenterShift: 500,
            maxTwapDistanceTicks: 1000,
            minRebalanceInterval: 60,
            maxPriceImpactBps: 50,
            maxNavLossBps: -500,
            maxDailyNavLossBps: 1000
        });
        registry.registerStrategy(env);
        vm.expectRevert(abi.encodeWithSelector(EnvelopeLib.IntervalTooShort.selector, 100, 150, 60));
        w.validateInterval(100, 150, 60);
    }

    function test_RebalanceBounds_PriceImpactTooHigh() public {
        Envelope memory env = Envelope({
            maxRangeWidth: 1000,
            maxCenterShift: 500,
            maxTwapDistanceTicks: 1000,
            minRebalanceInterval: 60,
            maxPriceImpactBps: 50,
            maxNavLossBps: -500,
            maxDailyNavLossBps: 1000
        });
        registry.registerStrategy(env);
        vm.expectRevert(abi.encodeWithSelector(EnvelopeLib.PriceImpactTooHigh.selector, 100, 50));
        w.validatePriceImpact(100, 50);
    }

    function test_RebalanceBounds_NavLossTooLarge() public {
        Envelope memory env = Envelope({
            maxRangeWidth: 1000,
            maxCenterShift: 500,
            maxTwapDistanceTicks: 1000,
            minRebalanceInterval: 60,
            maxPriceImpactBps: 50,
            maxNavLossBps: -500,
            maxDailyNavLossBps: 1000
        });
        registry.registerStrategy(env);
        vm.expectRevert(abi.encodeWithSelector(EnvelopeLib.NavLossTooLarge.selector, -1000, -500));
        w.validateNavLoss(-1000, -500);
    }
}
