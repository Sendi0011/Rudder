// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {EnvelopeLib} from "../src/libraries/EnvelopeLib.sol";
import {NAVMath} from "../src/libraries/NAVMath.sol";
import {MathLib} from "../src/libraries/MathLib.sol";

/// @title Invariants
/// @notice Property/fuzz tests for core safety invariants:
/// - envelope never violated (out-of-bounds always reverts)
/// - fee never exceeds cap * gain
/// - proportional basket never exceeds total (rounding favors vault)
contract InvariantsTest is Test {
    function checkRange(int24 width, int24 maxWidth) external pure {
        EnvelopeLib.validateRangeWidth(width, maxWidth);
    }

    function checkInterval(uint48 lastTs, uint48 nowTs, uint48 minInterval) external pure {
        EnvelopeLib.validateInterval(lastTs, nowTs, minInterval);
    }

    function checkPriceImpact(uint32 impactBps, uint32 maxImpactBps) external pure {
        EnvelopeLib.validatePriceImpact(impactBps, maxImpactBps);
    }

    function checkNavLoss(int24 lossBps, int24 maxLossBps) external pure {
        EnvelopeLib.validateNavLoss(lossBps, maxLossBps);
    }

    function checkCenterShift(int24 shift, int24 maxShift) external pure {
        EnvelopeLib.validateCenterShift(shift, maxShift);
    }

    // Fuzz: any width > maxWidth must revert
    function testFuzz_rangeWidth_enforced(int24 width, int24 maxWidth) public {
        if (width > maxWidth) {
            vm.expectRevert();
            this.checkRange(width, maxWidth);
        } else {
            this.checkRange(width, maxWidth);
        }
    }

    // Fuzz: any impact > max must revert
    function testFuzz_priceImpact_enforced(uint32 impact, uint32 maxImpact) public {
        if (impact > maxImpact) {
            vm.expectRevert();
            this.checkPriceImpact(impact, maxImpact);
        } else {
            this.checkPriceImpact(impact, maxImpact);
        }
    }

    // Fuzz: nav loss below max must revert
    function testFuzz_navLoss_enforced(int24 loss, int24 maxLoss) public {
        if (loss < maxLoss) {
            vm.expectRevert();
            this.checkNavLoss(loss, maxLoss);
        } else {
            this.checkNavLoss(loss, maxLoss);
        }
    }

    // Fuzz: interval below min must revert
    function testFuzz_interval_enforced(uint48 lastTs, uint48 nowTs, uint48 minInterval) public {
        bool tooShort = nowTs < lastTs || (uint256(nowTs) - uint256(lastTs)) < uint256(minInterval);
        if (tooShort) {
            vm.expectRevert();
            this.checkInterval(lastTs, nowTs, minInterval);
        } else {
            this.checkInterval(lastTs, nowTs, minInterval);
        }
    }

    // Fuzz: fee never exceeds cap * gain
    function testFuzz_fee_neverExceedsCap(uint256 gain, uint256 maxFeeBps, uint256 feeBps) public {
        gain = bound(gain, 0, 1e30);
        maxFeeBps = bound(maxFeeBps, 0, 10000);
        feeBps = bound(feeBps, 0, 10000);
        uint256 holdValue = 1000;
        uint256 depositorValue = holdValue + gain;
        uint256 fee = NAVMath.computePerformanceFee(depositorValue, holdValue, maxFeeBps, feeBps);
        uint256 capAmount = MathLib.mulDivDown(gain, maxFeeBps, 10000);
        assertLe(fee, capAmount);
    }

    // Fuzz: fee is zero on loss or equality
    function testFuzz_fee_zeroOnLoss(uint256 a, uint256 b) public {
        a = bound(a, 0, 1e30);
        b = bound(b, 0, 1e30);
        if (a <= b) {
            uint256 fee = NAVMath.computePerformanceFee(a, b, 2000, 1000);
            assertEq(fee, 0);
        }
    }

    // Fuzz: proportional basket never exceeds total (rounding favors vault/remaining)
    function testFuzz_proportional_neverExceeds(uint256 amount, uint256 shares, uint256 totalShares) public {
        amount = bound(amount, 0, 1e30);
        totalShares = bound(totalShares, 1, 1e30);
        shares = bound(shares, 0, totalShares);
        NAVMath.Basket memory total = NAVMath.Basket({amount0: amount, amount1: amount});
        NAVMath.Basket memory outB = NAVMath.proportionalBasket(total, shares, totalShares);
        assertLe(outB.amount0, amount);
        assertLe(outB.amount1, amount);
    }

    // Fuzz: proportional basket sums never exceed when split (conservation)
    function testFuzz_proportional_splitConservation(uint256 amount, uint256 s1, uint256 s2) public {
        amount = bound(amount, 0, 1e30);
        s1 = bound(s1, 0, 1e18);
        s2 = bound(s2, 0, 1e18);
        uint256 totalShares = s1 + s2;
        if (totalShares == 0) return;
        NAVMath.Basket memory total = NAVMath.Basket({amount0: amount, amount1: amount});
        NAVMath.Basket memory a = NAVMath.proportionalBasket(total, s1, totalShares);
        NAVMath.Basket memory b = NAVMath.proportionalBasket(total, s2, totalShares);
        // Sum of parts must not exceed total (rounding down)
        assertLe(a.amount0 + b.amount0, amount);
    }
}
