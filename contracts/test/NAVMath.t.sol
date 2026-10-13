// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {NAVMath} from "../src/libraries/NAVMath.sol";
import {MathLib} from "../src/libraries/MathLib.sol";

contract NAVMathTest is Test {
    function test_ProportionalBasket() public pure {
        NAVMath.Basket memory total = NAVMath.Basket({amount0: 1000, amount1: 2000});
        NAVMath.Basket memory outB = NAVMath.proportionalBasket(total, 250, 1000); // 25%
        assertEq(outB.amount0, 250);
        assertEq(outB.amount1, 500);
    }

    function test_ProportionalBasket_ZeroTotalShares() public pure {
        NAVMath.Basket memory total = NAVMath.Basket({amount0: 1000, amount1: 2000});
        NAVMath.Basket memory outB = NAVMath.proportionalBasket(total, 250, 0);
        assertEq(outB.amount0, 0);
        assertEq(outB.amount1, 0);
    }

    function test_ComputePerformanceFee_ZeroOnLoss() public pure {
        uint256 fee = NAVMath.computePerformanceFee(100, 150, 2000, 1000); // depositor 100 < hold 150
        assertEq(fee, 0);
    }

    function test_ComputePerformanceFee_Capped() public pure {
        uint256 fee = NAVMath.computePerformanceFee(200, 100, 1000, 2000); // gain 100, feeBps 2000 > max 1000
        assertEq(fee, 10); // 100*1000/10000=10
    }

    function test_ComputePerformanceFee_Normal() public pure {
        uint256 fee = NAVMath.computePerformanceFee(150, 100, 2000, 1000); // gain 50, 10%
        assertEq(fee, 5);
    }
}
