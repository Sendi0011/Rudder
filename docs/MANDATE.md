# Mandate

Rudder is a Uniswap v4 hook and share-based vault system for curated concentrated liquidity. Its
scope is narrow and local to this repository.

## In scope

- A per-vault envelope stored in `StrategyRegistry`: range width, centre shift, rebalance interval,
  TWAP distance, price impact and NAV loss.
- Instant envelope tightening and delayed loosening through the strategy curator.
- Deposits and rebalances gated by a cumulative-tick TWAP with one sample per block timestamp.
- Exits that do not consult oracle state, a registry or an unbounded loop.
- A performance fee charged per depositor against that depositor's hold basket.
- An on-chain alpha accumulator used for ranking; AUM and volume do not enter the score.

## Rebalance loss bound

Let `L` be the positive magnitude of the NAV-loss floor stored as `maxNavLossBps` (a `-500` floor
means `L = 500`). `EnvelopeLib.validate` rejects floors deeper than `-PROTOCOL_MAX_NAV_LOSS_BPS`
with `PROTOCOL_MAX_NAV_LOSS_BPS = 500`, so `L <= 500`. A single accepted rebalance can compound
NAV-per-share by at most `L/10000`, so the
surviving fraction after `n` rebalances is at least `(1 - L/10000)^n`. With minimum interval `I`,
at most `floor(T/I)` interval-spaced rebalances fit in a horizon `T` after the first range-set.
The first range-set skips the interval check, so a horizon that starts at bootstrap admits one extra
rebalance:

`n = floor(T/I) + 1`
`bound(T) = 1 - (1 - L/10000)^n`
`boundBps(T) = 10000 * (1 - (1 - L/10000)^n)`

A horizon that starts after bootstrap with a known last rebalance timestamp replaces the `+ 1` with
zero when no immediate rebalance is allowed. The bound compounds the accounting loss measured by
`RudderVault._navLossBps`; it is not a market-price drawdown bound.

## Envelope authority

Only the registered curator for a strategy may change that strategy's envelope. `tightenEnvelope`
applies a strictly tighter envelope immediately and cancels any pending loosening. A looser change
must be queued with `queueLoosenEnvelope` and can only be applied by the same curator after
`LOOSEN_DELAY`; the checks live in
[`StrategyRegistry.sol:114-140`](../contracts/src/StrategyRegistry.sol). The curator has no withdrawal
or transfer right over LP funds; the registry stores the envelope, curator identity, bound vault and
alpha samples only.

## Rebalance cost and ranking

The registry ranking gap and the summed pre/post NAV loss from rebalances are distinct figures. The
first is a change in dimensionless alpha; the second is an accounting loss in basis points. They are
reported together as tracking measurements, with the local tolerance stated in
[`EVIDENCE.md:28-31`](EVIDENCE.md), and neither figure is a profit guarantee.

## Out of scope

- No audit, security review or deployment-readiness assertion.
- No live-network deployment has been broadcast from this repository.
- No partner SDK, adapter, route or partner-specific callback.
- No dynamic-fee surcharge, ZK circuit or off-chain score feed.
- No guarantee of profit, no capital protection and no claim of global priority.
- No assertion that the prior-art datasets cover the whole ecosystem.

## Boundaries

The first deposit and first range-set bootstrap the oracle; after that, deposits and rebalances
require a ready oracle while withdrawals remain independent of it. Pause blocks deposits and
rebalances, never withdrawals. Envelope authors choose bounds within the protocol NAV-loss floor;
a looser floor than `-500` bps is rejected at registration.

Claims and their local artifacts are listed in [`CLAIMS.md`](CLAIMS.md). Reproduction commands are in
[`EVIDENCE.md`](EVIDENCE.md).
