// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

/// @title MathLib
/// @notice Math utilities with rounding that favors vault and remaining LPs
library MathLib {
    error Overflow();
    error DivisionByZero();

    /// @dev Multiply then divide, rounding down (favors vault)
    function mulDivDown(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256) {
        if (denominator == 0) revert DivisionByZero();
        unchecked {
            uint256 prod = a * b;
            if (prod / a != b) revert Overflow();
            return prod / denominator;
        }
    }

    /// @dev Multiply then divide, rounding up (favors LPs when claiming against vault, so we prefer down)
    function mulDivUp(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256) {
        if (denominator == 0) revert DivisionByZero();
        unchecked {
            uint256 prod = a * b;
            if (prod / a != b) revert Overflow();
            if (prod == 0) return 0;
            return (prod - 1) / denominator + 1;
        }
    }

    /// @dev Subtract with guard, rounding favors remaining (always floor operations)
    function subFloor(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b > a) return 0;
        return a - b;
    }

    /// @dev Convert basis points to factor (e.g. 10000 bps = 100%)
    function bpsToFactor(uint256 bps) internal pure returns (uint256) {
        return mulDivDown(1e18, bps, 10000);
    }
}
