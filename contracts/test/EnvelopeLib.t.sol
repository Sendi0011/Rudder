// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {EnvelopeLib} from "../src/libraries/EnvelopeLib.sol";

contract EnvelopeLibWrapper {
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

    function test_ValidateRangeWidth_Ok() public view {
        w.validateRangeWidth(100, 200);
    }

    function test_ValidateRangeWidth_TooLarge() public {
        vm.expectRevert(abi.encodeWithSelector(EnvelopeLib.InvalidRangeWidth.selector, 300, 200));
        w.validateRangeWidth(300, 200);
    }

    function test_ValidateCenterShift_Ok() public view {
        w.validateCenterShift(50, 100);
        w.validateCenterShift(-50, 100);
    }

    function test_ValidateCenterShift_TooLarge() public {
        vm.expectRevert(abi.encodeWithSelector(EnvelopeLib.InvalidCenterShift.selector, 150, 100));
        w.validateCenterShift(150, 100);
    }

    function test_ValidateInterval() public {
        vm.expectRevert(abi.encodeWithSelector(EnvelopeLib.IntervalTooShort.selector, 100, 150, 60));
        w.validateInterval(100, 150, 60);
        w.validateInterval(100, 170, 60);
    }

    function test_ValidatePriceImpact() public {
        vm.expectRevert(abi.encodeWithSelector(EnvelopeLib.PriceImpactTooHigh.selector, 50, 40));
        w.validatePriceImpact(50, 40);
    }

    function test_ValidateNavLoss() public {
        vm.expectRevert(abi.encodeWithSelector(EnvelopeLib.NavLossTooLarge.selector, -50, -30));
        w.validateNavLoss(-50, -30);
        w.validateNavLoss(-20, -30);
    }
}
