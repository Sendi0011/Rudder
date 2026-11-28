# Changelog

All notable changes to Rudder are recorded here. Rudder has not cut a tagged release yet;
entries are grouped by the date they landed on `main`.

## Unreleased

### Added
- **Bounded delegation.** `EnvelopeLib` defines per-strategy bounds (range width, centre shift,
  interval, price impact, NAV loss, distance from the TWAP tick). `RudderVault.rebalance` validates
  every bound on-chain and reverts on violation, so a curator can steer but never act outside its
  mandate.
- **Curated liquidity vaults.** `RudderVault` custodies LP assets and holds a single Uniswap v4
  position opened through `PoolManager.unlock` (no PositionManager NFT) plus idle balances.
  Withdrawals are always pro-rata and never revert on a bad oracle.
- **Manipulation-resistant oracle.** `RudderHook` records prices in `beforeSwap` (the pre-swap
  price) into a fixed-capacity ring buffer, collapsing intra-block pushes to one sample per
  timestamp, and serves a time-weighted average via `consult`.
- **Strategy registry.** `StrategyRegistry` stores envelopes and curator identity, supports instant
  tightening and 24h-timelocked loosening, and ranks strategies by per-interval alpha versus a
  hold benchmark. AUM and volume never feed the ranking.
- **Vault factory.** `VaultFactory` clones vaults as minimal proxies and requires the pool to be
  already initialized and to use the single pinned hook at creation time.
- **Migration.** `VaultMigrator` moves an LP's position between vaults of the same pool in one
  transaction, crystallizing any performance fee before redeposit.
- **Deployment.** `Deploy.s.sol` mines a CREATE2 salt at runtime so the hook lands at an address
  whose low bits encode its permissions, and writes `contracts/deployments.json`. A networked fork
  test (`Fork.t.sol`) runs the full lifecycle against Unichain Sepolia when an RPC is configured.

### Security
- Deposits priced off a manipulated spot are rejected once the oracle is live (spot-vs-TWAP
  deviation bound); withdrawals are never gated by it.
- Performance fees apply only to `max(0, value - hold)` at the TWAP, are capped, and are
  crystallized at withdrawal; a stale oracle yields zero fee.
- Pause suppresses deposits and rebalances but never withdrawals.
- `MINIMUM_LIQUIDITY` is locked on the first deposit to blunt share-inflation griefing.
- Stateful invariants assert that holdings always cover redemptions, that the fee cap holds, and
  that the envelope width is respected.

### Fixed
- Interval math no longer overflows (`lastTs + minInterval` rewritten as a subtraction).
- `mulDiv` no longer divides by zero on a zero operand.
- Hold-basket basis moves on share transfer, keeping per-holder P&L accounting correct.
- The hook takes its owner as a constructor argument and binds its vault factory exactly once.

---

Rendered from commit 1d00a33f16fb0d270836a1fd8e8984523363f352 · [View source](https://github.com/Sendi0011/Rudder/blob/1d00a33f16fb0d270836a1fd8e8984523363f352/docs/CHANGELOG.md)
