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

## T3 (Registry and factory)
- StrategyRegistry: register strategy with Envelope, tighten (instant), queueLoosen/applyLoosen (24h timelock), curator checks, events. Envelope changes: tightening instant, loosening timelocked.
- VaultFactory: minimal-proxy clones, tracks vault->strategyId, isVault helper. Vaults call PoolManager.unlock (no PM NFT).
- RudderVault skeleton: ERC20, per-account holdBasket (amount0,amount1) only, initialized once.
- Gates: fmt ok; build has lint warnings only (not errors). Tests still 12 passing.

## T4 (Vault core - scaffold)
- RudderVault: ERC20 clone, per-account holdBasket stores (amount0,amount1) only (valuation at withdrawal). initialize once. MINIMUM_LIQUIDITY for first-depositor inflation protection. 
- Access: whenNotPaused checks hook.paused(); oracleOk for deposits (revert if bad oracle). Withdraw succeeds even if oracle bad (zero fee path). 
- Deposit/withdraw logic scaffolded with proportionals (rounding down via MathLib/NAVMath). Holds withdrawal-never-reverts-on-oracle as stated.
- Gates: fmt/build/test pass (12 tests).

## T5 (Rebalance)
- Vault.rebalance validates envelope via EnvelopeLib: range width, interval, price impact, NAV loss; updates lastRebalanceTimestamp. Center shift check scaffolded. Only curator; requires oracle ready; blocked when paused.
- Bounds tests added (4) covering each envelope constraint.
- Tests: 16 passing total.
- Gates: fmt/build/test pass.

## T6 (Performance fee)
- Vault.withdraw computes performance fee only if oracle ready (oracle-safe: zero fee if not ready). Fee applied at withdrawal, capped by PROTOCOL_MAX_FEE_BPS (2000), rounds down favoring vault. Fee reduction reflected proportionally.
- Fee math tests: zero on loss, zero if equal, capped, normal. Total 20 tests passing.
- Gates: fmt ok, build via-ir ok, tests pass.
