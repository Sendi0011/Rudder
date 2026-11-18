# Rudder

A Uniswap v4 hook plus vault system for **curated liquidity**. Curators steer an LP position inside
an on-chain mandate (an *envelope*); LPs never relinquish custody. Exit always works, and oracle
badness never blocks withdrawals.

- **Curator steers, never custodies.** A curator can only move the position inside bounds enforced
  by `EnvelopeLib` — range width, centre shift, rebalance interval, price impact, NAV loss, and
  distance from the TWAP tick. Every violation reverts.
- **Manipulation-resistant oracle.** `RudderHook` samples prices in `beforeSwap` (the pre-swap
  price), one sample per timestamp, and serves a time-weighted average. A swapper cannot choose the
  price it is recorded at.
- **Hold-benchmarked performance fees.** Fees apply only to `max(0, value − hold)` at the TWAP, are
  capped, and crystallize at withdrawal. A stale oracle yields zero fee. The benchmark is deliberately
  lenient: any return above a passive hold counts, so it overstates active skill.
- **Transparent ranking.** Strategies are ranked by on-chain per-interval alpha versus a hold
  benchmark, expressed as a dimensionless return. AUM and volume never feed the ranking.

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
faster CI profile is available via `FOUNDRY_PROFILE=ci`.

## Numbers

Local measurements from `FOUNDRY_PROFILE=ci forge test --match-contract EvidenceTest`.

- Oracle lookup gas: **9,583** early and **17,316** at capacity; the ring holds **2,048** observations,
  the TWAP window is **1,800** seconds, and the freshness bound is **3,600** seconds
  ([`evidence/oracle_gas.json`](evidence/oracle_gas.json)).
- TWAP step response: spot moved from tick **-1** to **817** while the **1,800**-second TWAP read
  **135** after **30** observations, a **682**-tick gap from spot and **67** bps sqrt-price deviation
  ([`evidence/twap_accuracy.json`](evidence/twap_accuracy.json)).
- Rebalance mandate: width **600** ticks, centre shift **0** ticks, elapsed **20** seconds since the
  prior rebalance, and NAV change **-5** bps ([`evidence/rebalance_bounds.json`](evidence/rebalance_bounds.json)).
- Deposit guard: manipulated spot deviated **109** bps against a **50** bps envelope cap and **50** bps
  protocol cap before `SpotTwapDeviation` ([`evidence/deposit_guard.json`](evidence/deposit_guard.json)).
- Ranking invariance: vaults at different sizes accrued the same alpha delta of **2,499,874,729,099,975**
  with **0** bps relative difference; mid-window deposit and withdrawal each changed alpha by **0**
  ([`evidence/flow_invariance.json`](evidence/flow_invariance.json)).

Fork test against a live network (skipped when the RPC is unset):

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

- `beforeAddLiquidity` allows liquidity changes only from factory-created vaults.
- `beforeSwap` records the pre-swap tick at most once per timestamp into a fixed ring, so a swapper
  cannot choose the price used by the vault's TWAP.
- Vaults call `PoolManager.unlock` directly; no NFT position manager holds the position.
- The hook is deployed with CREATE2 at an address whose low bits match its permissions, and the
  factory refuses any pool that does not use that hook.

### Run it locally

```sh
forge fmt --check
FOUNDRY_PROFILE=ci forge test
```

See [Deployment](#deployment) for RPC setup and script commands. No broadcast or live deployment is
performed by these local commands. Development friction and remaining open items are collected in
[`docs/FEEDBACK.md`](docs/FEEDBACK.md) and [`docs/OPEN_QUESTIONS.md`](docs/OPEN_QUESTIONS.md).

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — components and invariants
- [`docs/DEMO.md`](docs/DEMO.md) — reviewer walkthrough
- [`docs/THREAT_MODEL.md`](docs/THREAT_MODEL.md) — threats, vectors, mitigations
- [`docs/KNOWN_LIMITATIONS.md`](docs/KNOWN_LIMITATIONS.md) — boundaries and open work
- [`docs/CHANGELOG.md`](docs/CHANGELOG.md) — notable changes
- [`docs/OPEN_QUESTIONS.md`](docs/OPEN_QUESTIONS.md) — open items
- [`docs/FEEDBACK.md`](docs/FEEDBACK.md) — Uniswap v4 developer friction encountered while building
- [`docs/adr/ADR-001-architecture.md`](docs/adr/ADR-001-architecture.md) — architecture decisions
- [`docs/adr/ADR-002-oracle-and-rebalance-swap.md`](docs/adr/ADR-002-oracle-and-rebalance-swap.md) — oracle and rebalance decisions
