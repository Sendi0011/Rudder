# Rudder

A Uniswap v4 hook plus vault system for **curated liquidity**. Curators steer an LP position inside
an on-chain mandate (an *envelope*); LPs never relinquish custody. Exit always works, and oracle
badness never blocks withdrawals. <!-- claim:RUD-001 -->

- **Curator steers, never custodies.** A curator can only move the position inside bounds enforced
  by `EnvelopeLib` — range width, centre shift, rebalance interval, price impact, NAV loss, and
  distance from the TWAP tick. Every violation reverts. <!-- claim:RUD-002 -->
- **Manipulation-resistant oracle.** `RudderHook` samples prices in `beforeSwap` (the pre-swap
  price), one sample per timestamp, and serves a time-weighted average. A swapper cannot choose the
  price it is recorded at. <!-- claim:RUD-003 -->
- **Hold-benchmarked performance fees.** Fees apply only to `max(0, value − hold)` at the TWAP, are
  capped, and crystallize at withdrawal. A stale oracle yields zero fee. The benchmark is deliberately
  lenient: any return above a passive hold counts, so it overstates active skill. <!-- claim:RUD-004 -->
- **Transparent ranking.** Strategies are ranked by on-chain per-interval alpha versus a hold
  benchmark, expressed as a dimensionless return. AUM and volume never feed the ranking. <!-- claim:RUD-005 -->
- **Permissionless alpha checkpoints.** Anyone can call `pokeAlpha()` to accrue and rebase when the
  oracle is ready. Without a token flow it cannot change shares or payouts, and a stale or reverting
  oracle leaves state unchanged. <!-- claim:RUD-031 -->

## Layout

```
contracts/
  src/            Solidity sources (vault, hook, registry, factory, migrator, libraries)
  script/         deploy, seed and activity scripts
  scripts/        activity loop
  test/           unit, integration, fuzz and stateful invariant tests
frontend/         not started
docs/             architecture, threat model, ADRs, changelog, limitations
```

## Build and test

Requires [Foundry](https://book.getfoundry.sh/) and initialized submodules. `foundry.toml` is at the
repository root, so run every `forge` command from that directory.

```sh
git clone --recurse-submodules https://github.com/Sendi0011/Rudder.git && cd Rudder
forge fmt --check
forge build --via-ir
forge test --via-ir
```

`via-ir` is required (the default pipeline reports "Stack too deep" in `RudderVault.withdraw`). A
faster CI profile is available via `FOUNDRY_PROFILE=ci`. <!-- claim:RUD-006 -->

## Numbers

Local measurements from `FOUNDRY_PROFILE=ci forge test --match-contract EvidenceTest`.

- Oracle lookup gas: **9,583** early and **17,316** at capacity; the ring holds **2,048** observations,
  the TWAP window is **1,800** seconds, and the freshness bound is **3,600** seconds
  ([`evidence/oracle_gas.json`](evidence/oracle_gas.json)). <!-- claim:RUD-007 -->
- TWAP step response: spot moved from tick **-1** to **817** while the **1,800**-second TWAP read
  **135** after **30** observations, a **682**-tick gap from spot and **67** bps sqrt-price deviation
  ([`evidence/twap_accuracy.json`](evidence/twap_accuracy.json)). <!-- claim:RUD-008 -->
- Rebalance mandate: width **600** ticks, centre shift **0** ticks, elapsed **20** seconds since the
  prior rebalance, and NAV change **-5** bps ([`evidence/rebalance_bounds.json`](evidence/rebalance_bounds.json)). <!-- claim:RUD-009 -->
- Deposit guard: manipulated spot deviated **109** bps against a **50** bps envelope cap and **50** bps
  protocol cap before `SpotTwapDeviation` ([`evidence/deposit_guard.json`](evidence/deposit_guard.json)). <!-- claim:RUD-010 -->
- Ranking invariance: vaults at different sizes accrued the same alpha delta of **2,499,874,729,099,975**
  with **0** bps relative difference; mid-window deposit and withdrawal each changed alpha by **0**
  ([`evidence/flow_invariance.json`](evidence/flow_invariance.json)). <!-- claim:RUD-011 -->
- Rebalance cost: NAV fell **15** bps and alpha fell **15** bps; the hold basket stayed unchanged
  ([`evidence/rebalance_alpha_cost.json`](evidence/rebalance_alpha_cost.json)). <!-- claim:RUD-012 -->
- Churn ranking: across **3** rebalances the ranking gap was **200** bps against **249** bps summed cost
  ([`evidence/churner_alpha.json`](evidence/churner_alpha.json)). <!-- claim:RUD-013 -->
- Rebalance bound: a **500** bps per-rebalance floor over **30** seconds at a **10**-second interval allowed
  **1,856** bps across **4** rebalances; measured loss was **73** bps across **3** charged rebalances
  ([`evidence/worst_case_loss.json`](evidence/worst_case_loss.json)). <!-- claim:RUD-029 -->
- Curator sample: **4** random curators over **3** regimes and **2** envelopes saw a **-5** bps reactive
  mean against a **-7** bps placebo mean with **34** bps dispersion; worst loss was **77** bps against
  a **9,981** bps bound and **183** bps drawdown
  ([`evidence/placebo_curators.json`](evidence/placebo_curators.json)). <!-- claim:RUD-030 -->

Fork test against a live network (skipped when the RPC is unset): <!-- claim:RUD-014 -->

```
UNICHAIN_SEPOLIA_RPC_URL=<rpc> forge test --match-contract ForkLifecycleTest -vvv
```

## Deployment

Copy `.env.example` to `.env`, fill the variable names, then load it:

```sh
cp .env.example .env
source .env
```

The fork lifecycle test runs only when an RPC is configured:

```sh
forge test --match-contract ForkLifecycleTest -vvv
```

Dry-run each script against the configured RPC without broadcasting:

```sh
forge script contracts/script/Deploy.s.sol:Deploy --rpc-url "$UNICHAIN_SEPOLIA_RPC_URL" -vvv
forge script contracts/script/Seed.s.sol:Seed --rpc-url "$UNICHAIN_SEPOLIA_RPC_URL" -vvv
forge script contracts/script/Activity.s.sol:Activity --rpc-url "$UNICHAIN_SEPOLIA_RPC_URL" -vvv
```

Broadcast only after reviewing the dry-run output:

```sh
forge script contracts/script/Deploy.s.sol:Deploy --rpc-url "$UNICHAIN_SEPOLIA_RPC_URL" --broadcast -vvv
forge script contracts/script/Seed.s.sol:Seed --rpc-url "$UNICHAIN_SEPOLIA_RPC_URL" --broadcast -vvv
```

`Deploy.s.sol` writes `contracts/deployments.json`; `Seed.s.sol` writes `contracts/seed.json`. Run
the scripts in this order: Deploy, Seed, at least five Activity runs, then the oracle-ready call
below. `Seed` initializes the pool at `START_TICK`, seats the three vault ranges and funds them
before any swap. `Activity` reads the pool and vault state from `contracts/seed.json`, steers price
back toward the starting tick, and refuses a swap that would leave the narrowest vault range. Use
`scripts/activity.sh` to send one small swap per loop iteration:

```sh
scripts/activity.sh
```

After the Activity runs, confirm the oracle is ready:

```sh
HOOK=$(jq -r .rudderHook contracts/deployments.json)
TOKEN0=$(jq -r .token0 contracts/seed.json)
TOKEN1=$(jq -r .token1 contracts/seed.json)
FEE=$(jq -r .fee contracts/seed.json)
SPACING=$(jq -r .tickSpacing contracts/seed.json)

cast call "$HOOK" 'isOracleReady((address,address,uint24,int24,address)) returns (bool)' \
  "($TOKEN0,$TOKEN1,$FEE,$SPACING,$HOOK)"
```

Verify the deployed contracts with the deployed addresses and constructor arguments:

```sh
POOL_MANAGER=$(jq -r .poolManager contracts/deployments.json)
REGISTRY=$(jq -r .strategyRegistry contracts/deployments.json)
IMPLEMENTATION=$(jq -r .vaultImplementation contracts/deployments.json)
FACTORY=$(jq -r .vaultFactory contracts/deployments.json)
HOOK=$(jq -r .rudderHook contracts/deployments.json)

forge verify-contract "$REGISTRY" contracts/src/StrategyRegistry.sol:StrategyRegistry --chain 1301
forge verify-contract "$IMPLEMENTATION" contracts/src/RudderVault.sol:RudderVault --chain 1301
forge verify-contract "$FACTORY" contracts/src/VaultFactory.sol:VaultFactory --chain 1301 \
  --constructor-args "$(cast abi-encode 'constructor(address,address,address,address)' "$IMPLEMENTATION" "$POOL_MANAGER" "$REGISTRY" "$HOOK")"
forge verify-contract "$HOOK" contracts/src/RudderHook.sol:RudderHook --chain 1301 \
  --constructor-args "$(cast abi-encode 'constructor(address,address)' "$POOL_MANAGER" "$OWNER")"
```

| Contract | Address | Notes |
| --- | --- | --- |
| RudderHook |  |  |
| StrategyRegistry |  |  |
| RudderVault implementation |  |  |
| VaultFactory |  |  |
| PoolManager |  |  |
| Token0 |  |  |
| Token1 |  |  |

## Hookathon

Rudder uses a Uniswap v4 hook as the enforcement point for curated liquidity. The hook address is
mined for its exact permission bits, and `VaultFactory` pins that address so every vault shares the
same gating and price source.

### What to show

The reviewer walkthrough is in [`docs/DEMO.md`](docs/DEMO.md): register a bounded strategy, create a
vault, deposit, swap to prime the TWAP, rebalance inside and outside the envelope, reject a
manipulated deposit, withdraw through a stale oracle, rank strategies, and migrate in one transaction.

### v4 surface

- `beforeAddLiquidity` allows liquidity changes only from factory-created vaults. <!-- claim:RUD-016 -->
- `beforeSwap` records the pre-swap tick at most once per timestamp into a fixed ring, so a swapper
  cannot choose the price used by the vault's TWAP. <!-- claim:RUD-017 -->
- Vaults call `PoolManager.unlock` directly; no NFT position manager holds the position. <!-- claim:RUD-018 -->
- The hook is deployed with CREATE2 at an address whose low bits match its permissions, and the
  factory refuses any pool that does not use that hook. <!-- claim:RUD-015 -->

### Run it locally

```sh
forge fmt --check
FOUNDRY_PROFILE=ci forge test
```

See [Deployment](#deployment) for RPC setup and script commands. No broadcast or live deployment is
performed by these local commands. <!-- claim:RUD-019 --> Development friction and remaining open items are collected in
[`docs/FEEDBACK.md`](docs/FEEDBACK.md) and [`docs/OPEN_QUESTIONS.md`](docs/OPEN_QUESTIONS.md).

## Documentation

- [`docs/MANDATE.md`](docs/MANDATE.md) — scope and exclusions
- [`docs/CLAIMS.md`](docs/CLAIMS.md) — claims linked to artifacts and commands
- [`docs/EVIDENCE.md`](docs/EVIDENCE.md) — artifact reproduction
- [`docs/DEPLOYMENTS.md`](docs/DEPLOYMENTS.md) — deployment state and checks
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — components and invariants
- [`docs/DEMO.md`](docs/DEMO.md) — reviewer walkthrough
- [`docs/THREAT_MODEL.md`](docs/THREAT_MODEL.md) — threats, vectors, mitigations
- [`docs/KNOWN_LIMITATIONS.md`](docs/KNOWN_LIMITATIONS.md) — boundaries and open work
- [`docs/CHANGELOG.md`](docs/CHANGELOG.md) — notable changes
- [`docs/OPEN_QUESTIONS.md`](docs/OPEN_QUESTIONS.md) — open items
- [`docs/FEEDBACK.md`](docs/FEEDBACK.md) — Uniswap v4 developer friction encountered while building
- [`docs/adr/ADR-001-architecture.md`](docs/adr/ADR-001-architecture.md) — architecture decisions
- [`docs/adr/ADR-002-oracle-and-rebalance-swap.md`](docs/adr/ADR-002-oracle-and-rebalance-swap.md) — oracle and rebalance decisions
- [`docs/adr/ADR-003-protocol-nav-loss-floor.md`](docs/adr/ADR-003-protocol-nav-loss-floor.md) — protocol NAV-loss floor

## Partner integrations

No partner integrations. There is no partner SDK, adapter, route or partner-specific callback in
`contracts/src`, `contracts/script` or `frontend/`. <!-- claim:RUD-020 -->

## Built during the hookathon

Listed from `git log` dates since 2026-11-16:

- 2026-11-17: cumulative-tick oracle correction; zero-impact rebalance handling; bounded alpha
  history and leaderboard; deposit, withdrawal and rebalance invariants; ranking and flow tests;
  oracle tests under optimization; seed and activity scripts; deployment commands; hookathon
  orientation; pull request merge `134d7b0`.
- 2026-11-18: withdrawal independence fix and tests; evidence write permission; bounded invariant
  handler with action and revert counters; measured operating numbers; review findings; mutation
  harness and its result table.
- 2026-11-19: reproducible prior-art search, generated evidence artifacts and prior-art comparison;
  mutation result publication.

## Credits

- Uniswap v4 core (`v4-core`) and periphery (`v4-periphery`)
- OpenZeppelin contracts
- The Uniswap v3 cumulative-price oracle design
- Atrium Academy UHI Hook Directory (`AtriumAcademy/UHI-Hook-Data`)
- Uniswap hooklist (`Uniswap/hooklist`)

The reproducible search and neighbor comparison are in [`docs/prior-art.md`](docs/prior-art.md).

| Neighbor | Evidence level | Bounded mechanism | Rudder contrast |
| --- | --- | --- | --- |
| Invariant | code read, commit `476778e` | tick bounds and minimum range width | per-vault mandate adds centre shift, interval, TWAP distance and price impact with delayed loosening | <!-- claim:RUD-021 -->
| CoPool Hook | code read, commit `9bdd059` | token selection, balances and pooled liquidity | per-depositor hold-basis fees and share-based exits are in the Rudder code and tests | <!-- claim:RUD-022 -->
| TickRangeHook | code read, explorer source | tick lower and upper bounds | Rudder checks width, shift, interval, TWAP distance and price impact | <!-- claim:RUD-023 -->
| M0 Tick Range Hook | code read, explorer source | tick lower and upper bounds | Rudder checks width, shift, interval, TWAP distance and price impact | <!-- claim:RUD-024 -->
| CuratedLP | code read, commit `0bcce80` | tick ordering, spacing, interval, fee cap and delegation bounds | Rudder adds hold-basis fees and a flow-invariant alpha ranking | <!-- claim:RUD-025 -->
| Sentinel v4 | code read, commit `5aa883e` | oracle deviation, yield thresholds and automation width fallback | Rudder ties bounds to a per-vault mandate and timelocked loosening | <!-- claim:RUD-026 -->
| Ghostbot | code read, commit `0ca2b56` | ticks, cooldown, fee change and signal freshness | Rudder evaluates performance per depositor against a hold basket | <!-- claim:RUD-027 -->

## Known limitations

### Not audited

Rudder has not been audited. The tests and evidence artifacts are local checks, not a security
review. <!-- claim:RUD-028 -->

## Demo

Demo video: `<placeholder>`

## Deployed addresses

Deployed addresses table: (empty)

| Contract | Address |
| --- | --- |
| RudderHook |  |
| StrategyRegistry |  |
| RudderVault implementation |  |
| VaultFactory |  |
| PoolManager |  |
| Token0 |  |
| Token1 |  |
