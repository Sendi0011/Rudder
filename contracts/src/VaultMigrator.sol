// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

interface IRudderVault {
    function withdraw(uint256 shares, address recipient) external returns (uint256, uint256);
    function deposit(uint256 amount0, uint256 amount1, address recipient) external returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function currency0() external view returns (address);
    function currency1() external view returns (address);
}

/// @title VaultMigrator
/// @notice Single-transaction migration of an LP position from one curator vault to another.
/// @dev The migrator pulls the LP's shares, withdraws them itself (so the exit fee is crystallized
///      against the shares' own cost basis, which the vault moved to the migrator on transfer),
///      approves the destination vault, and deposits on the LP's behalf. The LP must approve this
///      contract for the source vault's shares.
contract VaultMigrator is ReentrancyGuard {
    using SafeERC20 for IERC20;

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

    /// @notice Migrate the caller's entire balance from one curator vault to another.
    /// @param fromVault Source curator vault.
    /// @param toVault Destination curator vault.
    /// @return newShares Shares minted in the destination vault.
    function migrate(address fromVault, address toVault) external nonReentrant returns (uint256 newShares) {
        if (fromVault == toVault) revert SameVault();
        uint256 shares = IRudderVault(fromVault).balanceOf(msg.sender);
        if (shares == 0) revert NothingToMigrate();

        // Pull the shares so the migrator can withdraw them; the vault moves the matching hold
        // basket pro-rata on transfer, so the exit fee is charged against the LP's own basis.
        IERC20(fromVault).safeTransferFrom(msg.sender, address(this), shares);

        (uint256 amount0, uint256 amount1) = IRudderVault(fromVault).withdraw(shares, address(this));

        address token0 = IRudderVault(toVault).currency0();
        address token1 = IRudderVault(toVault).currency1();
        IERC20(token0).forceApprove(toVault, amount0);
        IERC20(token1).forceApprove(toVault, amount1);

        newShares = IRudderVault(toVault).deposit(amount0, amount1, msg.sender);

        // Do not leave residual allowances hanging around the destination vault.
        IERC20(token0).forceApprove(toVault, 0);
        IERC20(token1).forceApprove(toVault, 0);

        emit Migrated(msg.sender, fromVault, toVault, shares, amount0, amount1);
    }
}
