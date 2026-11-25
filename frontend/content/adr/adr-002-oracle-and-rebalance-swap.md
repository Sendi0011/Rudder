# ADR-002: Oracle, Rebalance Swap, and Hook-Native Envelope Enforcement
Date: 2026-11-15

## Context
The vault values positions and gates deposits/rebalances on a manipulation-resistant price, and a
curator rebalance must move the position without leaving value behind or letting the curator choose
its own metrics. Two forces shape the design: (a) the pool's price must not be movable by a same-block
push, and (b) the envelope must hold even if a vault has a bug, since a vault is the only contract
allowed to add liquidity through the hook.

## Decisions
- **Cumulative tick oracle in the hook.** `beforeSwap` records the *pre-swap* tick into a fixed
  per-pool ring buffer (`CAPACITY = 2048`). A sample stores `lastCumulative + tick * elapsed`, where
  `elapsed` is the time since the previous sample; the first sample stores zero. One sample per
  timestamp, so a same-block push-and-reverse cannot move the oracle. `consult` extends the newest
  cumulative to `block.timestamp` with the current tick, binary-searches the ring for the first
  observation at or after the window start, and interpolates the cumulative there; a window starting
  before the oldest sample uses the oldest sample as the start. The average tick is the cumulative
  difference divided by the elapsed seconds, rounded toward negative infinity. `MIN_OBSERVATIONS = 2`;
  `MAX_OBSERVATION_AGE = 1 hour`.
- **One TWAP read per transaction.** The vault caches the TWAP in transient storage (`tstore`) for the
  life of a transaction, so repeated valuations within one action cost a single `consult`. This makes
  `totalAssetsValue`, `twapSqrtPrice`, `_twapSqrtPrice`, and `_performanceFee` non-`view` and makes the
  holdings invariant non-`view`.
- **Deposit deviation guard; withdrawals never gated.** Once the oracle is live, a deposit reverts if
  the spot deviates from the TWAP by more than `min(envelope.maxPriceImpactBps,
  PROTOCOL_MAX_PRICE_IMPACT_BPS)` (`PROTOCOL_MAX_PRICE_IMPACT_BPS = 50` in sqrt-price bps). Withdrawals
  are never gated by oracle state, pause, or the hook.
- **Rebalance swaps the excess side through the pool.** A rebalance removes liquidity, computes the
  mix the new range needs at the current price (all token0 above the range, all token1 below, else the
  liquidity-math ratio), and swaps the excess as exact input inside `unlock`. The `sqrtPriceLimitX96`
  is derived from the TWAP and the impact cap; the cap is the tighter of the envelope and the protocol
  ceiling so a rebalance can never push the pool past what deposits accept. Realized price impact and
  NAV loss are re-checked on-chain after the swap; a swap that hits its limit leaves the unswapped side
  idle rather than reverting. Curators never supply metrics.
- **Hook-native envelope enforcement (defense in depth).** `beforeAddLiquidity` independently enforces
  the live envelope for any registered vault: tick-spacing alignment, `maxRangeWidth`,
  `maxTwapDistanceTicks` from the TWAP tick, and `minRebalanceInterval` between range-setting adds.
  Top-up adds into the live range are exempt, and `beforeRemoveLiquidity` is never gated. The envelope
  is read live from the registry and the TWAP through the same oracle, so the vault's own checks and
  the hook's checks cannot drift.

## Consequences
- A vault bug that skips `rebalance`'s checks still cannot seat liquidity outside the envelope; the
  hook is the backstop. `HookEnvelope.t.sol` drives the vault's low-level add path directly to prove it.
- The per-transaction TWAP cache ties the vault's correctness to a single `consult` per action; it is
  sound because a transaction is the unit of user intent and the oracle is only read, never written,
  by the vault.
- Rebalancing in a pool where the vault is the dominant liquidity provider can move the spot toward the
  impact limit at low cost, because liquidity is briefly thin; the limit and the post-swap checks bound
  the damage, and dust is left idle rather than forced into the pool.
- The oracle gate adds a bounded amount of gas per add (a registry read plus an O(log n) consult),
  independent of how many observations the ring holds.
- The first interval after launch is unscored and the TWAP is undefined until two observations exist;
  deposits fall back to the spot price for the deviation guard only while the oracle is not yet live.

---

Rendered from commit a9f574526cbe24e489e60502caf06053d545de35 · [View source](https://github.com/Sendi0011/Rudder/blob/a9f574526cbe24e489e60502caf06053d545de35/docs/adr/ADR-002-oracle-and-rebalance-swap.md)
