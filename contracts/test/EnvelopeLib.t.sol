// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Envelope, EnvelopeLib} from "../src/libraries/EnvelopeLib.sol";

contract EnvelopeLibWrapper {
    function validate(Envelope memory e) external pure {
        EnvelopeLib.validate(e);
    }

    function isTighter(Envelope memory current, Envelope memory next) external pure returns (bool) {
        return EnvelopeLib.isTighter(current, next);
    }

    function validateTwapDistance(int24 centerTick, int24 twapTick, int24 maxDistance) external pure {
        EnvelopeLib.validateTwapDistance(centerTick, twapTick, maxDistance);
    }

    function validateRangeWidth(int24 width, int24 maxWidth) external pure {
        EnvelopeLib.validateRangeWidth(width, maxWidth);
    }

    function validateCenterShift(int24 shift, int24 maxShift) external pure {
        EnvelopeLib.validateCenterShift(shift, maxShift);
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

contract EnvelopeLibTest is Test {
    EnvelopeLibWrapper internal w;

    function setUp() public {
        w = new EnvelopeLibWrapper();
    }

    function _base() internal pure returns (Envelope memory) {
        return Envelope({
            maxRangeWidth: 1000,
            maxCenterShift: 500,
            maxTwapDistanceTicks: 2000,
            minRebalanceInterval: 60,
            maxPriceImpactBps: 50,
            maxNavLossBps: -500,
            maxDailyNavLossBps: 1000
        });
    }

    function test_Validate_AcceptsWellFormed() public view {
        w.validate(_base());
    }

    function test_Validate_RejectsDegenerate() public {
        Envelope memory e = _base();
        e.maxRangeWidth = 0;
        vm.expectRevert(EnvelopeLib.InvalidParams.selector);
        w.validate(e);

        e = _base();
        e.maxCenterShift = -1;
        vm.expectRevert(EnvelopeLib.InvalidParams.selector);
        w.validate(e);

        e = _base();
        e.maxTwapDistanceTicks = -1;
        vm.expectRevert(EnvelopeLib.InvalidParams.selector);
        w.validate(e);

        e = _base();
        e.minRebalanceInterval = 0;
        vm.expectRevert(EnvelopeLib.InvalidParams.selector);
        w.validate(e);

        e = _base();
        e.maxPriceImpactBps = 10_001;
        vm.expectRevert(EnvelopeLib.InvalidParams.selector);
        w.validate(e);

        e = _base();
        e.maxNavLossBps = 1;
        vm.expectRevert(EnvelopeLib.InvalidParams.selector);
        w.validate(e);
    }

    function test_Validate_RejectsNavLossFloorBelowProtocolCap() public {
        Envelope memory e = _base();
        e.maxNavLossBps = -501;
        vm.expectRevert(abi.encodeWithSelector(EnvelopeLib.NavLossFloorTooLow.selector, -501, -500));
        w.validate(e);
    }

    function test_ValidateRejectsInvalidDailyBudget() public {
        Envelope memory e = _base();
        e.maxDailyNavLossBps = 0;
        vm.expectRevert(EnvelopeLib.ZeroDailyNavLossBudget.selector);
        w.validate(e);

        e = _base();
        e.maxDailyNavLossBps = 1001;
        vm.expectRevert(abi.encodeWithSelector(EnvelopeLib.DailyNavLossBudgetTooHigh.selector, 1001, 1000));
        w.validate(e);

        e = _base();
        e.maxNavLossBps = -100;
        e.maxDailyNavLossBps = 199;
        vm.expectRevert(abi.encodeWithSelector(EnvelopeLib.NavLossFloorExceedsBudget.selector, -100, 199));
        w.validate(e);

        e.maxDailyNavLossBps = 200;
        w.validate(e);
    }

    function test_IsTighter_TreatsSmallerDailyBudgetAsTighter() public view {
        Envelope memory cur = _base();
        Envelope memory next = _base();
        next.maxNavLossBps = -100;
        next.maxDailyNavLossBps = 200;
        assertTrue(w.isTighter(cur, next));
    }

    function test_IsTighter_RejectsLooserDailyBudget() public view {
        Envelope memory cur = _base();
        cur.maxNavLossBps = -100;
        cur.maxDailyNavLossBps = 200;
        Envelope memory next = _base();
        next.maxNavLossBps = -100;
        next.maxDailyNavLossBps = 500;
        assertFalse(w.isTighter(cur, next));
    }

    function test_IsTighter_StrictlyTighter() public view {
        Envelope memory cur = _base();
        Envelope memory next = _base();
        next.maxRangeWidth = 500;
        next.minRebalanceInterval = 120;
        next.maxNavLossBps = -100; // a shallower (stricter) loss floor
        assertTrue(w.isTighter(cur, next));
    }

    function test_IsTighter_IdenticalIsTighter() public view {
        assertTrue(w.isTighter(_base(), _base()));
    }

    function test_IsTighter_RejectsAnyLooserField() public {
        Envelope memory cur = _base();

        Envelope memory next = _base();
        next.maxRangeWidth = 1001;
        assertFalse(w.isTighter(cur, next), "wider range is looser");

        next = _base();
        next.maxCenterShift = 501;
        assertFalse(w.isTighter(cur, next), "larger shift is looser");

        next = _base();
        next.maxTwapDistanceTicks = 2001;
        assertFalse(w.isTighter(cur, next), "further TWAP distance is looser");

        next = _base();
        next.minRebalanceInterval = 59;
        assertFalse(w.isTighter(cur, next), "shorter interval is looser");

        next = _base();
        next.maxPriceImpactBps = 51;
        assertFalse(w.isTighter(cur, next), "higher impact bound is looser");

        next = _base();
        next.maxNavLossBps = -501;
        assertFalse(w.isTighter(cur, next), "deeper loss floor is looser");
    }

    function test_ValidateTwapDistance() public {
        w.validateTwapDistance(100, 90, 50);
        w.validateTwapDistance(-100, -90, 50);
        vm.expectRevert(EnvelopeLib.InvalidParams.selector);
        w.validateTwapDistance(200, 90, 50);
    }

    function test_ValidateRangeWidth_Ok() public view {
        w.validateRangeWidth(100, 200);
    }

    function test_ValidateRangeWidth_TooLarge() public {
        vm.expectRevert(abi.encodeWithSelector(EnvelopeLib.InvalidRangeWidth.selector, 200, 100));
        w.validateRangeWidth(200, 100);
    }

    function test_ValidateCenterShift_Ok() public view {
        w.validateCenterShift(100, 200);
        w.validateCenterShift(-100, 200);
    }

    function test_ValidateCenterShift_TooLarge() public {
        vm.expectRevert(abi.encodeWithSelector(EnvelopeLib.InvalidCenterShift.selector, 300, 200));
        w.validateCenterShift(300, 200);
    }

    function test_ValidateInterval() public {
        w.validateInterval(1000, 1060, 60);
        vm.expectRevert(abi.encodeWithSelector(EnvelopeLib.IntervalTooShort.selector, 1000, 1030, 60));
        w.validateInterval(1000, 1030, 60);
    }

    function test_ValidatePriceImpact() public {
        w.validatePriceImpact(50, 100);
        vm.expectRevert(abi.encodeWithSelector(EnvelopeLib.PriceImpactTooHigh.selector, 150, 100));
        w.validatePriceImpact(150, 100);
    }

    function test_ValidateNavLoss() public {
        w.validateNavLoss(-100, -500);
        vm.expectRevert(abi.encodeWithSelector(EnvelopeLib.NavLossTooLarge.selector, -600, -500));
        w.validateNavLoss(-600, -500);
    }
}
