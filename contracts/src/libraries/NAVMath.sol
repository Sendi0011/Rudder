// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {MathLib} from "./MathLib.sol";

/// @title NAVMath
/// @notice Hold-basket and performance-fee math. Token valuation lives in `LiquidityLib`
///         (`valueInToken0`/`valueInToken1`), which does the correct sqrt-price conversion.
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
