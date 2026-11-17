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
  script/Deploy.s.sol
  test/           unit, integration, fuzz and stateful invariant tests
frontend/         (placeholder)
docs/             architecture, threat model, ADRs, changelog, limitations
```

## Build and test

Requires [Foundry](https://book.getfoundry.sh/) and initialized submodules.

```sh
git clone --recurse-submodules <repo> && cd uniswapid/contracts
forge fmt --check
forge build --via-ir
forge test --via-ir
```

`via-ir` is required (the default pipeline reports "Stack too deep" in `RudderVault.withdraw`). A
faster CI profile is available via `FOUNDRY_PROFILE=ci`.

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
`scripts/activity.sh` to send one small swap per loop iteration:

```sh
scripts/activity.sh
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

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — components and invariants
- [`docs/THREAT_MODEL.md`](docs/THREAT_MODEL.md) — threats, vectors, mitigations
- [`docs/KNOWN_LIMITATIONS.md`](docs/KNOWN_LIMITATIONS.md) — boundaries and open work
- [`docs/CHANGELOG.md`](docs/CHANGELOG.md) — notable changes
- [`docs/OPEN_QUESTIONS.md`](docs/OPEN_QUESTIONS.md) — open items
- [`docs/FEEDBACK.md`](docs/FEEDBACK.md) — Uniswap v4 developer friction encountered while building
- [`docs/adr/ADR-001-architecture.md`](docs/adr/ADR-001-architecture.md) — architecture decisions
