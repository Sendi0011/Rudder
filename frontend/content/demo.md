# Demo

A ~3-minute walkthrough for reviewers.

## Setup

- Deploy the stack (or use the recorded Unichain Sepolia deployment): `StrategyRegistry`,
  `RudderVault` implementation, `VaultFactory`, and the mined `RudderHook`.
- Show `contracts/deployments.json` and the hook address whose low bits encode
  `beforeAddLiquidity | beforeSwap`.

## Script

1. **Register a strategy** as a curator with a visible `Envelope` (bounds on range width, centre
   shift, interval, price impact, NAV loss, distance from the TWAP).
2. **Create a vault** for an initialized pool; show that the factory pins the hook and refuses an
   uninitialized pool or a foreign hook.
3. **Deposit** — mine a position and show the first-depositor bootstrap behaviour (the oracle gate
   is waived exactly once).
4. **Swap** the pool twice to make the TWAP live; show `hook.isOracleReady(key) == true`.
5. **Rebalance** inside the envelope, then attempt an out-of-bounds rebalance and show the specific
   `EnvelopeLib` revert — the curator is bounded on-chain.
6. **Manipulate** the spot in a single block and show the pre-swap oracle and deposit deviation
   guard rejecting the manipulated deposit.
7. **Withdraw** — show pro-rata payout, the crystallized performance fee on gain only, and that a
   stale oracle yields zero fee without blocking the withdrawal.
8. **Rank** strategies by per-interval alpha and show that AUM/volume never feed the ranking.
9. **Migrate** an LP between two vaults of the same pool in a single transaction.

## Talking points

- The curator steers but never custodies: it has no withdrawal rights.
- Every promise is enforced by a revert, not by convention — bounds, pause, fees, gating.
- The oracle is built from pre-swap samples, so a swapper cannot choose the price it is recorded at.

---

Rendered from commit a9f574526cbe24e489e60502caf06053d545de35 · [View source](https://github.com/Sendi0011/Rudder/blob/a9f574526cbe24e489e60502caf06053d545de35/docs/DEMO.md)
