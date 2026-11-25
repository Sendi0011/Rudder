# Mandate

Rudder is a Uniswap v4 hook and share-based vault system for curated concentrated liquidity. Its
scope is narrow and local to this repository.

## In scope

- A per-vault envelope stored in `StrategyRegistry`: range width, centre shift, rebalance interval,
  TWAP distance, price impact, NAV-loss floor and daily NAV-loss budget.
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

## Daily loss budget

The daily budget is the spendable allowance behind those per-action floors. `EnvelopeLib.validate`
rejects a zero budget, a budget above the protocol ceiling and a floor magnitude above half the
budget. The seeded floors, budgets, intervals and bounds are recorded in
[`evidence/worst_case_loss.json`](https://github.com/Sendi0011/Rudder/raw/cee9100a4c4fa976728806331a6177b82c568d6d/evidence/worst_case_loss.json).

`RudderVault` charges each rebalance to a per-vault leaky bucket after the NAV-loss floor passes. The
bucket starts at zero; its capacity is half the budget and it refills that capacity over the horizon
recorded in [`evidence/worst_case_loss.json`](https://github.com/Sendi0011/Rudder/raw/cee9100a4c4fa976728806331a6177b82c568d6d/evidence/worst_case_loss.json). It rejects a rebalance
whose rounded-up charge would exceed capacity. A tighter budget lowers capacity immediately without
clamping the stored bucket; a looser budget must clear the existing timelock. Deposits, withdrawals
and alpha poking never consult the bucket. The parameter choice and the rejected fixed-window reset
are recorded in [`ADR-004`](/docs/adr/adr-004-daily-loss-budget/).

## Envelope authority

Only the registered curator for a strategy may change that strategy's envelope. `tightenEnvelope`
applies a strictly tighter envelope immediately and cancels any pending loosening. A looser change
must be queued with `queueLoosenEnvelope` and can only be applied by the same curator after
`LOOSEN_DELAY`; the checks live in
[`StrategyRegistry.sol:114-140`](https://github.com/Sendi0011/Rudder/raw/cee9100a4c4fa976728806331a6177b82c568d6d/contracts/src/StrategyRegistry.sol). The curator has no withdrawal
or transfer right over LP funds; the registry stores the envelope, curator identity, bound vault and
alpha samples only.

## Rebalance cost and ranking

The registry ranking gap and the summed pre/post NAV loss from rebalances are distinct figures. The
first is a change in dimensionless alpha; the second is an accounting loss in basis points. They are
reported together as tracking measurements, with the local tolerance stated in
[`EVIDENCE.md:28-31`](/docs/evidence/), and neither figure is a profit guarantee.

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

Claims and their local artifacts are listed in [`CLAIMS.md`](/docs/claims/). Reproduction commands are in
[`EVIDENCE.md`](/docs/evidence/).

---

Rendered from commit cee9100a4c4fa976728806331a6177b82c568d6d · [View source](https://github.com/Sendi0011/Rudder/blob/cee9100a4c4fa976728806331a6177b82c568d6d/docs/MANDATE.md)
