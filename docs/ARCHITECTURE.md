# Architecture

Rudder is a bounded-delegation system for curated liquidity on Uniswap v4: a hook plus
curator-operated vaults that steer a single LP range inside an on-chain mandate.

## Components

```
                 ┌────────────────────┐
   curator ────▶ │  StrategyRegistry  │  envelopes, curator identity, alpha ranking
                 └─────────┬──────────┘
                           │ envelope + curator
                 ┌─────────▼──────────┐
   LP ─────────▶ │    VaultFactory    │  clones vaults; pins the hook; requires a live pool
                 └─────────┬──────────┘
                    clone  │  initialize
                 ┌─────────▼──────────┐        unlock / modifyLiquidity
                 │    RudderVault     │ ───────────────────────────────▶ ┌──────────────┐
                 │  custody + range   │ ◀─────────────────────────────── │  PoolManager │
                 └─────────┬──────────┘        NAV / TWAP                └──────┬───────┘
                           │ consult                                           │ beforeSwap / beforeAddLiquidity
                 ┌─────────▼──────────┐                                        │
                 │    RudderHook      │ ◀──────────────────────────────────────┘
                 │  gating + oracle   │
                 └────────────────────┘

   LP ───────▶ VaultMigrator ── (withdraw from A, deposit into B, one tx)
```

- **`StrategyRegistry`** is the source of truth for each strategy's `Envelope` and curator. Envelopes
  tighten instantly and loosen behind a 24h timelock. Ranking is per-interval alpha versus a hold
  benchmark.
- **`VaultFactory`** clones vaults as minimal proxies, pins the single trusted hook, and requires the
  pool to already be initialized and to use that hook.
- **`RudderVault`** holds LP assets and one v4 position plus idle balances. It opens/closes the
  position through `PoolManager.unlock` directly (no PositionManager NFT). Its `rebalance` validates
  the envelope on-chain; withdrawals are always pro-rata and never revert on a bad oracle.
- **`RudderHook`** gates which addresses may add liquidity (only factory vaults) and maintains a
  manipulation-resistant TWAP from pre-swap prices.
- **`VaultMigrator`** moves an LP between two vaults of the same pool in one transaction.

## Invariants

- A vault's holdings (idle + position valued at the TWAP) always cover LP NAV plus curator pending
  fees; the sum of holders' pro-rata claims never exceeds NAV.
- The performance fee never exceeds `PROTOCOL_MAX_FEE_BPS` and is zero on a loss or a stale oracle.
- The envelope width is never exceeded by the live position.
- `rebalance` reverts if any envelope bound (width, centre shift, interval, price impact, NAV loss,
  distance from the TWAP tick) is violated.
- Pause suppresses deposits and rebalances and never affects withdrawals.

See `THREAT_MODEL.md` for the threat/ mitigation table, `KNOWN_LIMITATIONS.md` for honest
boundaries, and `adr/ADR-001-architecture.md` for the decisions behind this layout.
