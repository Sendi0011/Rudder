// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {RudderIntegrationBase} from "./RudderIntegrationBase.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {VaultMigrator} from "../src/VaultMigrator.sol";

/// @notice Migration between curator vaults and the cost-basis transfer that makes the exit fee fair.
contract MigratorTest is RudderIntegrationBase {
    uint256 internal constant BIG = 1e18;

    VaultMigrator internal migrator;

    function setUp() public override {
        super.setUp();
        migrator = new VaultMigrator();
    }

    function _newVault() internal returns (RudderVault v) {
        vm.prank(curator);
        uint256 id = registry.registerStrategy(_envelope());
        vm.prank(curator);
        v = RudderVault(factory.createVault(id, key, 1000));
    }

    function _readyPool() internal {
        _swap(true, -int256(1e18));
        vm.warp(block.timestamp + 10);
        _swap(true, -int256(1e18));
        vm.warp(block.timestamp + 10);
    }

    /// @notice A full single-transaction migration moves the LP's whole balance and crystallizes the
    ///         exit fee against the LP's own cost basis at the source vault.
    function test_MigrateMovesFullBalanceAndCrystallizesFee() public {
        vm.prank(curator);
        vault.rebalance(-600, 600);
        _fund(alice, BIG, BIG);
        uint256 shares = _deposit(alice, BIG, BIG);
        _readyPool();

        // Lift NAV above the hold basket so an exit fee is due.
        token0.mint(address(vault), 100e18);

        RudderVault dest = _newVault();
        vm.prank(curator);
        dest.rebalance(-600, 600);

        uint256 feesBefore = vault.pendingFees0() + vault.pendingFees1();
        vm.prank(alice);
        vault.approve(address(migrator), shares);

        vm.prank(alice);
        uint256 newShares = migrator.migrate(address(vault), address(dest));

        assertEq(vault.balanceOf(alice), 0, "source shares fully migrated");
        assertGt(newShares, 0, "destination shares minted");
        assertEq(dest.balanceOf(alice), newShares, "destination shares owned by the LP");
        assertGt(vault.pendingFees0() + vault.pendingFees1(), feesBefore, "exit fee crystallized at source");
    }

    /// @notice Transferring shares moves their cost basis, so the recipient's exit fee is charged
    ///         against that basis rather than being treated as free profit.
    function test_TransferMovesCostBasis() public {
        vm.prank(curator);
        vault.rebalance(-600, 600);
        _fund(alice, BIG, BIG);
        uint256 shares = _deposit(alice, BIG, BIG);
        _readyPool();
        token0.mint(address(vault), 100e18);

        (uint256 before0, uint256 before1) = vault.holdBasket(bob);
        assertEq(before0 + before1, 0, "bob starts with no basis");

        vm.prank(alice);
        vault.transfer(bob, shares);

        (uint256 moved0, uint256 moved1) = vault.holdBasket(bob);
        assertGt(moved0 + moved1, 0, "transfer must move cost basis to the recipient");

        vm.prank(bob);
        (uint256 out0, uint256 out1) = vault.withdraw(shares, bob);
        assertGt(out0 + out1, 0, "recipient can withdraw migrated shares");
    }
}
