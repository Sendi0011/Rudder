// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {RudderTestBase} from "./RudderTestBase.sol";
import {RudderIntegrationBase} from "./RudderIntegrationBase.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @notice Oracle-safety checks on factory-created vaults.
/// @dev Full end-to-end oracle-safety (withdrawing a live position while the oracle is stale) requires
///      the v4 unlock/collect integration and is tracked as the integration tranche. Here we prove the
///      withdraw path does not consult the oracle before the caller's balance, i.e. a bad/absent oracle
///      cannot cause a revert ahead of a legitimate balance check.
contract WithdrawOracleSafetyTest is RudderTestBase {
    function test_WithdrawWithNoSharesRevertsOnBalanceNotOracle() public {
        uint256 id = _registerStrategy(curator);
        address vault = _createVault(id, curator);

        // Oracle has no observations (not ready). Withdraw must still reach the balance check and revert
        // with InsufficientBalance - never an oracle error.
        vm.expectRevert(RudderVault.InsufficientBalance.selector);
        RudderVault(vault).withdraw(1, address(this));
    }

    function test_WithdrawZeroSharesRevertsZeroAmount() public {
        uint256 id = _registerStrategy(curator);
        address vault = _createVault(id, curator);

        vm.expectRevert(RudderVault.ZeroAmount.selector);
        RudderVault(vault).withdraw(0, address(this));
    }
}

/// @notice End-to-end exit safety with a live position, a stale oracle, a paused hook and a registry
///         that reverts on alpha reporting.
contract WithdrawLivePositionSafetyTest is RudderIntegrationBase {
    function test_WithdrawIgnoresStaleOraclePauseAndRegistryRevert() public {
        uint256 dep = 1000e18;
        _fund(alice, dep, dep);
        vm.prank(curator);
        vault.rebalance(-3000, 3000);
        vm.prank(alice);
        uint256 shares = vault.deposit(dep, dep, alice);

        _swap(true, -int256(1e6));
        vm.warp(block.timestamp + 10);
        _swap(true, -int256(1e6));
        vm.warp(block.timestamp + 10);
        assertTrue(hook.isOracleReady(key), "oracle was ready before the stall");

        hook.setPaused(true);
        vm.warp(block.timestamp + 2 hours);
        assertFalse(hook.isOracleReady(key), "oracle is stale");
        vm.mockCallRevert(
            address(registry), abi.encodeWithSignature("checkpointAlpha(uint256,int256)"), "registry down"
        );

        uint256 before0 = IERC20(address(token0)).balanceOf(alice);
        uint256 before1 = IERC20(address(token1)).balanceOf(alice);
        vm.prank(alice);
        vault.withdraw(shares, alice);

        assertEq(vault.balanceOf(alice), 0, "shares redeemed with a stale oracle");
        assertGt(
            IERC20(address(token0)).balanceOf(alice) + IERC20(address(token1)).balanceOf(alice),
            before0 + before1,
            "assets returned with a stale oracle and reverting registry"
        );
    }
}
