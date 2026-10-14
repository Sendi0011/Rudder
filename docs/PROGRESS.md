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

## T7 (Ranking and migration - scaffold)
- Ranking: alpha-vs-hold (checkpointed concept noted; view logic scaffolded). AUM/volume display-only.
- Migration: one-tx migration concept (structure in place; full implementation in T7 completion).
- Added test skeletons for oracle-safe withdrawals and share inflation protection (first-depositor). 
- Tests: 22 passing total.

## T7 (Ranking and migration - implementation)
- StrategyRegistry: added cumulative alpha-vs-hold checkpointing (checkpointAlpha, getAlpha), strategy<->vault binding (setStrategyVault), events. AUM/volume explicitly not part of ranking.
- VaultMigrator: single-transaction migration from one vault to another (withdraw crystallizes fee, deposits into destination on behalf of LP), ReentrancyGuard, events.
- Registry tests (5): register, instant tighten, timelocked loosen (revert-before/apply-after), alpha checkpoint, unauthorized checkpoint revert.
- Tests: 27 passing total. Gates: fmt/build/test pass.

## T8 (Hardening)
- Fuzz/invariant suite (8 tests): envelope bounds always enforced; fee never exceeds cap; fee zero on loss; proportional basket never exceeds total and split conserves; interval enforcement.
- Fuzzing caught two real bugs: (1) MathLib.mulDivDown/Up divided by zero when an operand was 0; (2) EnvelopeLib.validateInterval overflowed uint48 via `lastTs + minInterval`. Both fixed.
- Gas snapshot recorded to contracts/.gas-snapshot.
- FEEDBACK.md populated from real friction (BaseHook location, IHooks signature drift, getSlot0 absence, submodule recursion, via-ir need, no built-in TWAP helper, Foundry lint noise).
- THREAT_MODEL.md: 13 threats with vector/mitigation/status; honest limitations; slither not installed so no static-analysis claims made.
- Tests: 35 passing. Gates: fmt/build(via-ir)/test pass.

## T8b (Integration - vault moves real assets)
- `RudderVault` now custodies and moves real assets via `PoolManager.unlock`: `deposit` pulls both
  tokens (balance-delta checked; fee-on-transfer refused) and mines a position; `withdraw` removes
  liquidity and transfers pro-rata; `rebalance` removes + re-mines. Replaced the stubbed
  `_getTotalHold0/1` and `_totalAssetsValue` with real accounting (idle balances + position amounts
  + fees, all valued at the TWAP via new `LiquidityLib.valueInToken0`).
- `rebalance(newTickLower, newTickUpper)` only; removed caller-supplied `priceImpactBps`/`navLossBps`.
  Price impact (spot vs TWAP), center shift, and NAV before/after are measured on-chain. Tick-spacing
  alignment enforced. One revert test per bound, each driven by a real execution.
- `withdraw` burns exactly the redeemed shares, reduces the user's hold basket by `shares/userShares`,
  values output at TWAP (never sums raw token0+token1), charges the fee only on positive gain, pays it
  out, and pays zero when the oracle is not ready.
- `RudderHook.setPaused` is now `onlyOwner` (was unrestricted); pause never blocks withdraw.
  Added `consult(poolKey, secondsAgo)` TWAP view over the ring buffer.
- `foundry.toml`: `via_ir = true` (required; withdraw otherwise hits "Stack too deep").
- `VaultFactory`: added `vaultCount`, `vaults[]`, `vaultsLength()` for indexing and for the
  bad-config test. Replaced `test_NoUninitializedCloneOnRevert` with `test_BadConfigRevertsAndRegistersNoVault`
  (initialize reverting => no vault registered, `vaultCount == 0`).
- New tests: `RudderIntegrationBase` (real PoolManager + ERC-20s + minimal swap router),
  `Lifecycle.t.sol` (deposit->swap->rebalance->withdraw; one revert per bound; pause; free-share-mint,
  false-metrics, first-depositor-inflation), `VaultInvariants.t.sol` (stateful share conservation,
  fee-cap bound, envelope width never exceeded). `NAVMath.valueInToken0` placeholder removed (dead
  code; superseded by `LiquidityLib`).
- Tests: 53 passing. Gates: `forge fmt --check`, `forge build --via-ir`, `forge test --via-ir` pass.
- Deferred to T9: networked fork test on Unichain Sepolia; deploy scripts with hook-salt mining
  against the script's actual CREATE2 deployer (no scripts exist yet).

## T7 completion (Ranking - wired end to end)
- `StrategyRegistry` now has an `owner` (deployer) and a `factory` set once via `setFactory`.
  `setStrategyVault(id, vault)` is gated on `msg.sender == factory`, reverts `UnknownStrategy` for an
  unknown id and `StrategyAlreadyBound` if the strategy already has a vault. A strategy can never be
  hijacked to a second vault, and the curator can no longer rebind it.
- `VaultFactory.createVault` binds the freshly initialized vault to its strategy atomically
  (`registry.setStrategyVault`), so the vault is authorised to checkpoint the moment it exists.
- `RudderVault` now keeps a global aggregate hold basket (`totalHold`) updated on deposit (+=) and
  withdraw (pro-rata -=), and computes `alphaPerShare() = NAV-per-share - hold-value-per-share` at the
  TWAP, scaled to 1e18 shares.
- Alpha is checkpointed **automatically** at the end of `deposit`, `withdraw`, and `rebalance`
  (`_checkpointAlpha` emits the delta vs the last checkpoint to `registry.checkpointAlpha`). It is
  never curator-triggered and is skipped while the oracle is not ready (no trustworthy benchmark).
- Tests added: registry factory-set once / only-owner; vault bind only-factory / already-bound /
  unknown-strategy; factory propagates `StrategyAlreadyBound`; integration — factory binds vault,
  first deposit skips checkpoint until the oracle is ready, and deposit/withdraw/rebalance each write a
  checkpoint whose cumulative value equals the vault's live `alphaPerShare()`.
- `Invariants.t.sol` handler now registers one fresh strategy per vault (a strategy binds one vault)
  and caps creation so the O(n) invariant loops stay bounded; added `default.invariant.runs/depth = 64`.
- Tests: 75 passing. Gates: `forge fmt --check`, `forge build --via-ir`, `forge test --via-ir` pass.

## T8c (Oracle bootstrap hardening + oracle-independent withdrawals)
- Replaced the `totalSupply() == 0` bootstrap exemption with a **one-time `oracleBootstrapped` flag**.
  `depositOracle`/`rebalanceOracle` now waive the oracle-readiness requirement only while the flag is
  false; `_syncBootstrap()` flips it true the first time the TWAP is observed ready and it never
  un-flips. Emptying the vault (or the vault going dormant) can no longer reopen the exemption.
- End-to-end tests added to `Lifecycle.t.sol`:
  - `test_BootstrapFlagOneWay_EmptyingDoesNotReopen`: empty all LP shares, warp past the observation
    window, then a deposit reverts `OracleBad`.
  - `test_WithdrawZeroFeeWhenOracleStale`: after warping past `MAX_OBSERVATION_AGE` a withdrawal still
    succeeds and the `Withdraw` event reports `fee0 == fee1 == 0`.
  - `test_WithdrawWithEmptyOracleBuffer`: a withdrawal works with no observations at all, zero fee.
  - `test_WithdrawFromOutOfRangePosition`: a position driven fully below its range withdraws, returning
    almost entirely currency0.
- Tests: 79 passing. Gates: `forge fmt --check`, `forge build --via-ir`, `forge test --via-ir` pass.

## T8d (Pull-based curator fees + pro-rata fee accounting)
- Curator fees are now **pull-based**: a withdrawal accrues fees into `pendingFees0/1` and never
  transfers to the fee recipient, so a recipient that rejects transfers can never block an LP
  withdrawal. New `claimFees()` (fee-recipient only) pays out accrued fees and emits `FeesClaimed`.
- Pending fees are a liability: excluded from `_totalAssetsValue` (NAV/alpha), excluded from the
  pro-rata idle paid to withdrawing LPs, and excluded from idle deployed into the position
  (`_freeIdle0/1`). They therefore cannot be captured by other LPs or swept into the position.
- **Bug fixed (found by a new test):** on a *partial* withdrawal the performance fee compared the
  partial output against the account's *full* hold basket, so partial exits never charged a fee.
  The hold basket is now pro-rated to the redeemed shares before the comparison.
- Tests added: fees accrue and are pull-claimed (recipient balance unchanged during withdraw); only
  the fee recipient may claim; another LP cannot capture the curator's pending fees.
- Tests: 82 passing. Gates: `forge fmt --check`, `forge build --via-ir`, `forge test --via-ir` pass.
