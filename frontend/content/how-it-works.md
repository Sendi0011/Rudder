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
  tighten instantly and loosen behind a 24h timelock, and queued loosening is validated when queued.
  Ranking is per-interval alpha versus a hold benchmark, anchored at the lookback cutoff and read
  through bounded leaderboard pages.
- **`VaultFactory`** clones vaults as minimal proxies, pins the single trusted hook, and requires the
  pool to already be initialized and to use that hook.
- **`RudderVault`** holds LP assets and one v4 position plus idle balances. It opens/closes the
  position through `PoolManager.unlock` directly (no PositionManager NFT). Its `rebalance` validates
  the envelope on-chain and charges a leaky-bucket daily loss budget; withdrawals are always pro-rata
  and never revert on a bad oracle or a depleted bucket.
- **`RudderHook`** gates which addresses may add liquidity (only factory vaults), independently
  enforces each vault's live envelope on every add (alignment, width, TWAP distance, interval), and
  maintains a manipulation-resistant TWAP from pre-swap prices. Removals are never gated.
- **`VaultMigrator`** moves an LP between two vaults of the same pool in one transaction.

## Envelope fields

| Field | Bound |
| --- | --- |
| `maxRangeWidth` | Maximum tick width of the live position |
| `maxCenterShift` | Maximum move of the range centre against the TWAP tick |
| `minRebalanceInterval` | Minimum seconds between rebalances |
| `maxTwapDistanceTicks` | Maximum distance between the range centre and the TWAP tick |
| `maxPriceImpactBps` | Maximum swap price impact |
| `maxNavLossBps` | Maximum TWAP NAV loss charged to one rebalance |
| `maxDailyNavLossBps` | Maximum cumulative TWAP NAV loss charged in a rolling day |

`StrategyRegistry` validates every field on registration, tightening and queued loosening. The vault
reads the live envelope on each rebalance and charges `maxDailyNavLossBps` to a leaky bucket.

## Invariants

- A vault's holdings (idle + position valued at the TWAP) always cover LP NAV plus curator pending
  fees; the sum of holders' pro-rata claims never exceeds NAV.
- The performance fee never exceeds `PROTOCOL_MAX_FEE_BPS` and is zero on a loss or a stale oracle.
- The envelope width is never exceeded by the live position.
- `rebalance` reverts if any envelope bound (width, centre shift, interval, price impact, NAV loss,
  daily NAV-loss budget, distance from the TWAP tick) is violated.
- The loss bucket never exceeds its capacity and the sum of charged micro-bps in any rolling day stays
  inside the daily budget; deposit, withdrawal and alpha-poke paths do not read the bucket.
- The hook's add gate never seats a vault's liquidity outside its envelope, even if the vault skips
  its own checks; top-up adds into the live range are exempt and removals are never gated.
- Pause suppresses deposits and rebalances and never affects withdrawals.

See `THREAT_MODEL.md` for the threat/ mitigation table, `KNOWN_LIMITATIONS.md` for the known
boundaries, and `adr/ADR-001-architecture.md`, `adr/ADR-002-oracle-and-rebalance-swap.md`,
`adr/ADR-003-protocol-nav-loss-floor.md` and
`adr/ADR-004-daily-loss-budget.md` for the decisions behind this layout.

---

Rendered from commit 3212ad666f4f528fc441666739df78ba7be5182b · [View source](https://github.com/Sendi0011/Rudder/blob/3212ad666f4f528fc441666739df78ba7be5182b/docs/ARCHITECTURE.md)
