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
- **Honest performance fees.** Fees apply only to `max(0, value − hold)` at the TWAP, are capped, and
  crystallize at withdrawal. A stale oracle yields zero fee.
- **Transparent ranking.** Strategies are ranked by on-chain per-interval alpha versus a hold
  benchmark. AUM and volume never feed the ranking.

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

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — components and invariants
- [`docs/THREAT_MODEL.md`](docs/THREAT_MODEL.md) — threats, vectors, mitigations
- [`docs/KNOWN_LIMITATIONS.md`](docs/KNOWN_LIMITATIONS.md) — honest boundaries and open work
- [`docs/CHANGELOG.md`](docs/CHANGELOG.md) — notable changes
- [`docs/OPEN_QUESTIONS.md`](docs/OPEN_QUESTIONS.md) — unverified items
- [`docs/FEEDBACK.md`](docs/FEEDBACK.md) — Uniswap v4 developer friction encountered while building
- [`docs/adr/ADR-001-architecture.md`](docs/adr/ADR-001-architecture.md) — architecture decisions
