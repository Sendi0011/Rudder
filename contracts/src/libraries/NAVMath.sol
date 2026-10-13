// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "./MathLib.sol";

/// @title NAVMath
/// @notice NAV and hold-basket math
library NAVMath {
    /// @notice Hold basket - stores amounts only; valuation happens at withdrawal
    struct Basket {
        uint256 amount0;
        uint256 amount1;
    }

    /// @notice Compute proportional share of basket (round down - favors vault)
    function proportionalBasket(Basket memory total, uint256 shares, uint256 totalShares)
        internal
        pure
        returns (Basket memory outBasket)
    {
        if (totalShares == 0) {
            return Basket({amount0: 0, amount1: 0});
        }
        outBasket.amount0 = MathLib.mulDivDown(total.amount0, shares, totalShares);
        outBasket.amount1 = MathLib.mulDivDown(total.amount1, shares, totalShares);
        return outBasket;
    }

    /// @notice Compute value of basket in token0 terms using TWAP price
    /// @dev price is sqrtPriceX96 scaled as needed by caller; for now we take as 1:1 placeholder structure
    function valueInToken0(Basket memory b, uint160 sqrtPriceX96) internal pure returns (uint256 value0) {
        // Placeholder: caller interprets sqrtPriceX96 appropriately. Keep structure.
        // value0 = amount0 + amount1 * (price01 in terms of token0/token1)
        uint256 priceFactor = uint256(sqrtPriceX96) / 2; // dummy placeholder, not used in final form
        value0 = b.amount0 + MathLib.mulDivDown(b.amount1, priceFactor, 1e18);
        // Note: final implementation will use correct sqrt conversion; this is scaffold
        return b.amount0 + MathLib.mulDivDown(b.amount1, 1e18, 1e18); // simplified for now
    }

    /// @notice Compute performance fee amount; fee only on positive gain
    /// @dev Rounds down to favor vault. Fee capped by maxFeeBps on gain.
    function computePerformanceFee(uint256 depositorValue, uint256 holdValue, uint256 maxFeeBps, uint256 feeBps)
        internal
        pure
        returns (uint256 feeAmount)
    {
        if (depositorValue <= holdValue) {
            return 0;
        }
        uint256 gain = depositorValue - holdValue;
        uint256 effectiveFeeBps = feeBps > maxFeeBps ? maxFeeBps : feeBps;
        feeAmount = MathLib.mulDivDown(gain, effectiveFeeBps, 10000);
        return feeAmount;
    }
}
