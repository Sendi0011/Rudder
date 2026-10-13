// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {NAVMath} from "../src/libraries/NAVMath.sol";

contract FeeMathTest is Test {
    function test_Fee_ZeroOnLoss() public pure {
        uint256 fee = NAVMath.computePerformanceFee(90, 100, 2000, 1000);
        assertEq(fee, 0);
    }

    function test_Fee_Capped() public pure {
        uint256 fee = NAVMath.computePerformanceFee(150, 100, 1000, 2000);
        assertEq(fee, 5); // gain 50, capped to 1000bps = 5
    }

    function test_Fee_Normal() public pure {
        uint256 fee = NAVMath.computePerformanceFee(200, 100, 2000, 1000);
        assertEq(fee, 10); // 10% of 100 gain = 10
    }

    function test_Fee_ZeroIfEqual() public pure {
        uint256 fee = NAVMath.computePerformanceFee(100, 100, 2000, 1000);
        assertEq(fee, 0);
    }
}
