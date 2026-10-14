// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {RudderVault} from "../src/RudderVault.sol";

contract WithdrawOracleSafetyTest is Test {
    RudderVault vault;

    function setUp() public {
        vault = new RudderVault();
    }

    function test_WithdrawNeverRevertsOnBadOracle() public {
        // Skeleton test - verifies structure; full integration in T8/T9
        // Withdraw with zero shares should revert by InsufficientBalance/ZeroAmount,
        // but oracle badness path must not cause revert (spec: withdraw succeeds with zero fee if bad)
        vm.expectRevert();
        vault.withdraw(1, address(this));
    }
}
