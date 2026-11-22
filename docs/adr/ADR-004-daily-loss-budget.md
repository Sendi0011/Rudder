# ADR-004: Daily NAV-loss budget

- Status: Accepted

## Context

The per-rebalance NAV-loss floor bounds a single action but not a sequence of legal actions. A
curator could spend the full floor repeatedly and stay inside every existing envelope check. The
compounding bounds described in `ADR-003` are ceilings, not an allocation that can be spent and
refilled.

## Decision

`Envelope` carries `maxDailyNavLossBps`. `EnvelopeLib.validate` rejects a zero budget, a budget above
the protocol ceiling and a floor magnitude greater than half the budget. Instant tightening requires
the new envelope to be no looser on this field; loosening must be queued and validated at queue time
and then wait the existing timelock.

`RudderVault` keeps a per-vault leaky bucket in micro-bps. Capacity is half the budget, refill is
capacity spread evenly over the horizon recorded in
[`evidence/worst_case_loss.json`](../evidence/worst_case_loss.json), and a successful rebalance is
charged the rounded-up TWAP NAV-loss fraction. The capacity, refill and rounding constants are
exercised by the mutants in [`evidence/mutation.md`](../evidence/mutation.md). A charge above
capacity reverts the whole rebalance and emits no bucket update. Deposits, withdrawals and alpha
poking never read or write the bucket.

The additive charge gives a direct rolling bound: cumulative rebalance loss in any horizon is at most
the starting capacity plus the refill accrued in that horizon. Over the recorded horizon the refill
cannot restore more than the daily budget, so the sum of charged losses stays inside that budget.
The multiplicative loss from a chain of rebalances is no larger than the sum of its parts, so the
additive budget also bounds compounded accounting loss. The seeded budgets, observed charges and
rebalance counts are in [`evidence/worst_case_loss.json`](../evidence/worst_case_loss.json).

## Scope

The bucket prices rebalance-induced NAV loss measured at the TWAP. It does not bound market-price
moves, fee opportunity cost or rounding in favor of LPs. Tightening lowers capacity without clamping
an already-filled bucket, so a curator cannot regain spent allowance by tightening and waiting for
the queued loosen path.

## Rejected alternative

A fixed calendar-day reset was rejected. A reset at a wall-clock boundary lets a curator spend the
whole allowance immediately before and immediately after the boundary, giving a short-window loss
far above the intended daily allowance. Continuous refill spreads the allowance across time, and a
rolling-window invariant in
[`VaultInvariants.t.sol`](../contracts/test/VaultInvariants.t.sol) enforces that behavior across
charge histories.
