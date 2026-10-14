// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {FullMath} from "v4-core/libraries/FullMath.sol";
import {FixedPoint96} from "v4-core/libraries/FixedPoint96.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";

/// @title LiquidityLib
/// @notice Position sizing and valuation helpers built only on v4-core math. Amounts are always
///         derived from a sqrt price so that token0 and token1 are never naively summed.
library LiquidityLib {
    error LiquidityOverflow();

    /// @notice Token amounts backing `liquidity` over [sqrtA, sqrtB] at current price sqrtP.
    /// @dev Rounds up (favors the vault). Mirrors Uniswap's getAmountsForLiquidity.
    function getAmountsForLiquidity(uint160 sqrtP, uint160 sqrtA, uint160 sqrtB, uint128 liquidity)
        internal
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        if (sqrtP <= sqrtA) {
            amount0 = SqrtPriceMath.getAmount0Delta(sqrtA, sqrtB, liquidity, true);
        } else if (sqrtP < sqrtB) {
            amount0 = SqrtPriceMath.getAmount0Delta(sqrtP, sqrtB, liquidity, true);
            amount1 = SqrtPriceMath.getAmount1Delta(sqrtA, sqrtP, liquidity, true);
        } else {
            amount1 = SqrtPriceMath.getAmount1Delta(sqrtA, sqrtB, liquidity, true);
        }
    }

    /// @notice Maximum liquidity mintable from `amount0`/`amount1` over [sqrtA, sqrtB] at price sqrtP.
    function getLiquidityForAmounts(uint160 sqrtP, uint160 sqrtA, uint160 sqrtB, uint256 amount0, uint256 amount1)
        internal
        pure
        returns (uint128 liquidity)
    {
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        if (sqrtP <= sqrtA) {
            liquidity = _liquidityForAmount0(sqrtA, sqrtB, amount0);
        } else if (sqrtP < sqrtB) {
            uint128 l0 = _liquidityForAmount0(sqrtP, sqrtB, amount0);
            uint128 l1 = _liquidityForAmount1(sqrtA, sqrtP, amount1);
            liquidity = l0 < l1 ? l0 : l1;
        } else {
            liquidity = _liquidityForAmount1(sqrtA, sqrtB, amount1);
        }
    }

    /// @notice Value of (amount0, amount1) denominated in token0 at sqrt price sqrtP.
    /// @dev token1 is converted through price = (sqrtP / 2^96)^2, i.e. amount1 * 2^192 / sqrtP^2.
    function valueInToken0(uint256 amount0, uint256 amount1, uint160 sqrtP) internal pure returns (uint256) {
        if (sqrtP == 0 || amount1 == 0) return amount0;
        uint256 step1 = FullMath.mulDiv(amount1, FixedPoint96.Q96, sqrtP);
        uint256 step2 = FullMath.mulDiv(step1, FixedPoint96.Q96, sqrtP);
        return amount0 + step2;
    }

    /// @notice Value of (amount0, amount1) denominated in token1 at sqrt price sqrtP.
    /// @dev amount0 * (sqrtP / 2^96)^2 = amount0 * sqrtP^2 / 2^192.
    function valueInToken1(uint256 amount0, uint256 amount1, uint160 sqrtP) internal pure returns (uint256) {
        if (sqrtP == 0 || amount0 == 0) return amount1;
        uint256 step1 = FullMath.mulDiv(amount0, sqrtP, FixedPoint96.Q96);
        uint256 step2 = FullMath.mulDiv(step1, sqrtP, FixedPoint96.Q96);
        return amount1 + step2;
    }

    function _liquidityForAmount0(uint160 sqrtA, uint160 sqrtB, uint256 amount0) private pure returns (uint128) {
        if (amount0 == 0) return 0;
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        uint256 intermediate = FullMath.mulDiv(sqrtA, sqrtB, FixedPoint96.Q96);
        return _toUint128(FullMath.mulDiv(amount0, intermediate, sqrtB - sqrtA));
    }

    function _liquidityForAmount1(uint160 sqrtA, uint160 sqrtB, uint256 amount1) private pure returns (uint128) {
        if (amount1 == 0) return 0;
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        return _toUint128(FullMath.mulDiv(amount1, FixedPoint96.Q96, sqrtB - sqrtA));
    }

    function _toUint128(uint256 x) private pure returns (uint128) {
        if (x > type(uint128).max) revert LiquidityOverflow();
        return uint128(x);
    }
}
