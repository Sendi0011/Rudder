// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {RudderIntegrationBase} from "./RudderIntegrationBase.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {EnvelopeLib} from "../src/libraries/EnvelopeLib.sol";

contract PlaceboTest is RudderIntegrationBase {
    uint256 internal constant DEP = 1000e18;

    function test_NoRebalanceKeepsAlphaFlat() public {
        _fund(alice, DEP, DEP);
        _fund(bob, 1e18, 1e18);
        _deposit(alice, DEP, DEP);
        _deposit(bob, 1e18, 1e18);
        _readyOracle();
        vm.prank(bob);
        vault.withdraw(1e15, bob);

        int256 start = vault.cumulativeAlpha();
        _swap(true, -int256(5e17));
        vm.warp(block.timestamp + 10);
        vm.prank(bob);
        vault.withdraw(1e15, bob);

        assertApproxEqAbs(vault.cumulativeAlpha() - start, 0, 1e12);
    }

    function test_AlphaStaysZeroWhileOracleIsUnready() public {
        _fund(alice, DEP, DEP);
        _deposit(alice, DEP, DEP);

        vm.prank(curator);
        vault.rebalance(-600, 600);

        assertEq(vault.cumulativeAlpha(), 0);
        assertEq(registry.getAlpha(strategyId), 0);
    }

    function test_WithdrawRejectsSharesAboveBalance() public {
        _fund(alice, DEP, DEP);
        uint256 shares = _deposit(alice, DEP, DEP);

        vm.expectRevert(RudderVault.InsufficientBalance.selector);
        vm.prank(alice);
        vault.withdraw(shares + 1, alice);
    }

    function test_EnvelopeRejectsRangeAboveMaximum() public {
        vm.expectRevert(abi.encodeWithSelector(EnvelopeLib.InvalidRangeWidth.selector, int24(12_000), int24(6000)));
        vm.prank(curator);
        vault.rebalance(-6000, 6000);
    }

    function _readyOracle() internal {
        _swap(true, -int256(1e6));
        vm.warp(block.timestamp + 10);
        _swap(false, -int256(1e6));
        vm.warp(block.timestamp + 10);
        assertTrue(hook.isOracleReady(key));
    }
}
