// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

/// @notice On-chain bounds a curator may steer within. Every field is a hard cap; the vault enforces
///         them on every rebalance so an LP's delegation is bounded by construction.
/// @dev    `maxTwapDistanceTicks` bounds how far the range centre may sit from the TWAP tick, so a
///         curator can never park liquidity in a regime disconnected from the oracle price.
struct Envelope {
    int24 maxRangeWidth;
    int24 maxCenterShift;
    int24 maxTwapDistanceTicks;
    uint32 minRebalanceInterval;
    uint32 maxPriceImpactBps;
    int24 maxNavLossBps;
}

/// @title EnvelopeLib
/// @notice Validation and strictness comparison for envelopes. "Stricter" means each field is at
///         least as restrictive: caps shrink, floors rise, minimums grow.
library EnvelopeLib {
    int24 internal constant PROTOCOL_MAX_NAV_LOSS_BPS = 500;

    error InvalidParams();
    error NotTighter();
    error InvalidRangeWidth(int24 width, int24 maxWidth);
    error InvalidCenterShift(int24 shift, int24 maxShift);
    error IntervalTooShort(uint256 lastTs, uint256 nowTs, uint256 minInterval);
    error PriceImpactTooHigh(uint32 impactBps, uint32 maxPriceImpactBps);
    error NavLossTooLarge(int24 lossBps, int24 maxNavLossBps);
    error NavLossFloorTooLow(int24 floor, int24 minFloor);

    /// @notice Reject degenerate envelopes: caps must be positive, intervals nonzero, and the
    ///         impact/loss bounds within their natural ranges.
    function validate(Envelope memory e) internal pure {
        if (e.maxRangeWidth <= 0) revert InvalidParams();
        if (e.maxCenterShift < 0) revert InvalidParams();
        if (e.maxTwapDistanceTicks < 0) revert InvalidParams();
        if (e.minRebalanceInterval == 0) revert InvalidParams();
        if (e.maxPriceImpactBps > 10_000) revert InvalidParams();
        if (e.maxNavLossBps > 0) revert InvalidParams();
        if (e.maxNavLossBps < -PROTOCOL_MAX_NAV_LOSS_BPS) {
            revert NavLossFloorTooLow(e.maxNavLossBps, -PROTOCOL_MAX_NAV_LOSS_BPS);
        }
    }

    /// @notice True if every field of `next` is at least as strict as `current`. Instant tightening
    ///         is allowed only when this holds; any looser field must go through the timelock.
    function isTighter(Envelope memory current, Envelope memory next) internal pure returns (bool) {
        return next.maxRangeWidth <= current.maxRangeWidth && next.maxCenterShift <= current.maxCenterShift
            && next.maxTwapDistanceTicks <= current.maxTwapDistanceTicks
            && next.minRebalanceInterval >= current.minRebalanceInterval
            && next.maxPriceImpactBps <= current.maxPriceImpactBps && next.maxNavLossBps >= current.maxNavLossBps;
    }

    function validateRangeWidth(int24 width, int24 maxWidth) internal pure {
        if (width > maxWidth) revert InvalidRangeWidth(width, maxWidth);
    }

    function validateCenterShift(int24 shift, int24 maxShift) internal pure {
        int24 dist = shift < 0 ? -shift : shift;
        if (dist > maxShift) revert InvalidCenterShift(dist, maxShift);
    }

    /// @notice Bound the distance between the range centre and the TWAP tick.
    function validateTwapDistance(int24 centerTick, int24 twapTick, int24 maxDistance) internal pure {
        int24 diff = centerTick - twapTick;
        int24 dist = diff < 0 ? -diff : diff;
        if (dist > maxDistance) revert InvalidParams();
    }

    function validateInterval(uint256 lastTs, uint256 nowTs, uint256 minInterval) internal pure {
        if (nowTs < lastTs || nowTs - lastTs < minInterval) {
            revert IntervalTooShort(lastTs, nowTs, minInterval);
        }
    }

    function validatePriceImpact(uint32 impactBps, uint32 maxImpactBps) internal pure {
        if (impactBps > maxImpactBps) revert PriceImpactTooHigh(impactBps, maxImpactBps);
    }

    function validateNavLoss(int24 lossBps, int24 maxLossBps) internal pure {
        if (lossBps < maxLossBps) revert NavLossTooLarge(lossBps, maxLossBps);
    }
}
