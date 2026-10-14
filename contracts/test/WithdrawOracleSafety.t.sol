// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {RudderTestBase} from "./RudderTestBase.sol";
import {RudderVault} from "../src/RudderVault.sol";

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
