# Mandate

Rudder is a Uniswap v4 hook and share-based vault system for curated concentrated liquidity. Its
scope is narrow and local to this repository.

## In scope

- A per-vault envelope stored in `StrategyRegistry`: range width, centre shift, rebalance interval,
  TWAP distance, price impact and NAV loss.
- Instant envelope tightening and delayed loosening through the registry owner.
- Deposits and rebalances gated by a cumulative-tick TWAP with one sample per block timestamp.
- Exits that do not consult oracle state, a registry or an unbounded loop.
- A performance fee charged per depositor against that depositor's hold basket.
- An on-chain alpha accumulator used for ranking; AUM and volume do not enter the score.

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
rebalances, never withdrawals. Envelope authors choose the bounds; a loose bound is a policy choice,
not a protocol guarantee.

Claims and their local artifacts are listed in [`CLAIMS.md`](CLAIMS.md). Reproduction commands are in
[`EVIDENCE.md`](EVIDENCE.md).
