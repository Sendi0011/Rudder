// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

interface IRudderVault {
    function withdraw(uint256 shares, address recipient) external returns (uint256, uint256);
    function deposit(uint256 amount0, uint256 amount1, address recipient) external returns (uint256);
    function holdBasket(address) external view returns (uint256, uint256);
    function balanceOf(address) external view returns (uint256);
}

/// @title VaultMigrator
/// @notice Single-transaction migration of LP position from one curator vault to another.
/// @dev Fee crystallizes on exit (vault.withdraw handles it). ReentrancyGuard protects.
contract VaultMigrator is ReentrancyGuard {
    error NothingToMigrate();
    error SameVault();

    event Migrated(
        address indexed lp,
        address indexed fromVault,
        address indexed toVault,
        uint256 shares,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Migrate LP's entire balance from one vault to another in one transaction
    /// @param fromVault Source curator vault
    /// @param toVault Destination curator vault
    /// @return newShares shares minted in destination vault
    function migrate(address fromVault, address toVault) external nonReentrant returns (uint256 newShares) {
        if (fromVault == toVault) revert SameVault();
        uint256 shares = IRudderVault(fromVault).balanceOf(msg.sender);
        if (shares == 0) revert NothingToMigrate();

        // Withdraw from source (crystallizes fee on exit per vault logic)
        (uint256 amount0, uint256 amount1) = IRudderVault(fromVault).withdraw(shares, address(this));

        // Deposit into destination on behalf of the LP
        newShares = IRudderVault(toVault).deposit(amount0, amount1, msg.sender);

        emit Migrated(msg.sender, fromVault, toVault, shares, amount0, amount1);
    }
}
