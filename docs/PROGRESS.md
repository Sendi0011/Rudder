# Progress
Append a section after each tranche (T0..T14) with: what was built, what tests prove, open risks, commands run.

## T0 (Foundation)
- Scaffolded monorepo (contracts/, frontend/, docs/, .github/). Added foundry.toml (solc 0.8.26, cancun, src/test/script paths), .gitmodules (v4-core, v4-periphery), CI (forge fmt/build/test), README, ADR-001 with oracle-safe withdrawals, hold-basket-only storage, donation-attack protection, precise solvency invariant, deployments.json skeleton, FEEDBACK skeleton.
- Gates: forge fmt --check/build/test pending (no contracts yet). Layout and docs committed.
- Open risks: need to verify official Unichain Sepolia v4 addresses; confirm via_ir necessity later; oracle thresholds TBD (T1/T2).

## T1 (Libraries - partial)
- Added EnvelopeLib with pure validation and custom errors (range width, center shift, interval, price impact, NAV loss). Added wrapper unit tests (7/7 passing). NAVMath/MathLib placeholders for T1 continuation (hold-basket math, fee math, rounding favoring vault/LPs).
- Tests prove: bounds reject invalid inputs, accept valid ones; NavLoss logic matches spec (lossBps < maxNavLossBps reverts).
- Gates: forge fmt --check ok, forge build ok, forge test ok (EnvelopeLib).
- Open risks: need NAV/fund math with precise rounding, hold-basket only (valuation at withdrawal), oracle safety logic to be integrated in vault/hook (T2-T4).

## T1 (Libraries - complete)
- MathLib: mulDivDown/up with guards, subFloor, rounding favoring vault where specified.
- NAVMath: Basket (amount0,amount1 only), proportionalBasket (round down), computePerformanceFee (zero on loss, capped, rounds down). Scaffold valueInToken0 noted.
- Tests: 12 tests total across EnvelopeLib and NAVMath passing. Prove zero fee on loss, fee cap, proportional split, zero total shares.
- Gates: fmt/build/test pass.

## T2 (Hook - partial)
- RudderHook skeleton implementing IHooks: vault gating in beforeAddLiquidity (only factory-created vault), paused guard, afterSwap writes TWAP observations to ring buffer, oracle helpers (isOracleReady, getLastObservation) with MIN_OBSERVATIONS=2 and MAX_OBSERVATION_AGE=1h. Hook permissions minimal.
- Notes: TWAP staleness/min observations defined; withdrawals must never revert on bad oracle (enforced by vault logic later). Builder errors cleaned up for v4-core interface.
- Gates: fmt ok, build in progress - minor interface signature nuance noted.

## T2 (Hook - complete skeleton)
- RudderHook implements IHooks (v4-core): beforeAddLiquidity gates to vaultFactory and enforces paused; afterSwap records TWAP observations (ring buffer, truncates to ~720 recent). Helpers isOracleReady/getLastObservation. Minimal permissions. 
- Oracle safety note: withdrawals must never revert on bad oracle (to be enforced in vault; deposits/rebalances may revert).
- Gates: fmt/build/test pass (12 tests).
