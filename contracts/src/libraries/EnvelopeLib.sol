// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

struct Envelope {
    int24 maxRangeWidth;
    int24 maxCenterShift;
    uint48 minRebalanceInterval;
    uint32 maxPriceImpactBps;
    int24 maxNavLossBps;
}

/// @title EnvelopeLib
library EnvelopeLib {
    error InvalidRangeWidth(int24 width, int24 maxWidth);
    error InvalidCenterShift(int24 shift, int24 maxShift);
    error IntervalTooShort(uint48 last, uint48 nowTs, uint48 minInterval);
    error PriceImpactTooHigh(uint32 impactBps, uint32 maxImpactBps);
    error NavLossTooLarge(int24 lossBps, int24 maxLossBps);

    function validateRangeWidth(int24 width, int24 maxWidth) internal pure {
        if (width > maxWidth) revert InvalidRangeWidth(width, maxWidth);
    }

    function validateCenterShift(int24 shift, int24 maxShift) internal pure {
        if (shift < 0) shift = -shift;
        if (shift > maxShift) revert InvalidCenterShift(shift, maxShift);
    }

    function validateInterval(uint48 lastTs, uint48 nowTs, uint48 minInterval) internal pure {
        if (nowTs < lastTs + minInterval) {
            revert IntervalTooShort(lastTs, nowTs, minInterval);
        }
    }

    function validatePriceImpact(uint32 impactBps, uint32 maxImpactBps) internal pure {
        if (impactBps > maxImpactBps) revert PriceImpactTooHigh(impactBps, maxImpactBps);
    }

    function validateNavLoss(int24 lossBps, int24 maxLossBps) internal pure {
        if (lossBps < maxLossBps) {
            revert NavLossTooLarge(lossBps, maxLossBps);
        }
    }
}
