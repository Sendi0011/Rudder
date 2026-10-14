// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {RudderVault} from "../src/RudderVault.sol";

contract ShareInflationTest is Test {
    RudderVault vault;

    function setUp() public {
        vault = new RudderVault();
    }

    function test_MinimumLiquidityProtection() public view {
        // Structure test for first-depositor share inflation protection
        assertEq(vault.MINIMUM_LIQUIDITY(), 1000);
    }
}
