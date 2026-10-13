# Progress
Append a section after each tranche (T0..T14) with: what was built, what tests prove, open risks, commands run.

## T0 (Foundation)
- Scaffolded monorepo (contracts/, frontend/, docs/, .github/). Added foundry.toml (solc 0.8.26, cancun, src/test/script paths), .gitmodules (v4-core, v4-periphery), CI (forge fmt/build/test), README, ADR-001 with oracle-safe withdrawals, hold-basket-only storage, donation-attack protection, precise solvency invariant, deployments.json skeleton, FEEDBACK skeleton.
- Gates: forge fmt --check/build/test pending (no contracts yet). Layout and docs committed.
- Open risks: need to verify official Unichain Sepolia v4 addresses; confirm via_ir necessity later; oracle thresholds TBD (T1/T2).
