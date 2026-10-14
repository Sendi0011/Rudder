# Threat Model: Rudder

Bounded-delegation hook plus vaults for curated liquidity on Uniswap v4.

## Assets
- LP principal and accrued fees held by each curator vault.
- Curator's ability to steer ranges (not custody).
- Integrity of the TWAP used for NAV, fee accrual and envelope checks.
- Integrity of the alpha-vs-hold ranking (must not be gameable).

## Trust boundaries
- `RudderHook` (gating + TWAP oracle) is trusted by vaults.
- `StrategyRegistry` is the source of truth for envelopes and curator identity.
- `PoolManager` is external and trusted for swap/liquidity execution.
- Curator is untrusted-by-default: bounded by `Envelope`, never holds withdrawal rights.

## Threats and mitigations
| # | Threat | Vector | Mitigation | Status |
|---|--------|--------|------------|--------|
| 1 | Curator acts outside mandate | Out-of-bounds rebalance | `rebalance()` validates every bound via `EnvelopeLib`; out-of-bounds reverts with specific error | Implemented (T5) |
| 2 | Curator drains LP funds | Withdraw/transfer | Curator has no withdraw rights; vault custody only | Implemented (design) |
| 3 | Curator loosens envelope to rug LPs | Loosen bounds then act | Tightening instant; loosening timelocked (24h) so LPs can exit first | Implemented (T3) |
| 4 | Oracle manipulation via thin liquidity | Spot price used as NAV | TWAP `consult()` over the `afterSwap` ring buffer; all NAV/fee/impact values use it; price-impact bound is vs TWAP | Implemented (T8b); min-obs + age enforcement in hook |
| 5 | Stale/absent oracle blocks withdrawals | Bad oracle state | Withdrawals NEVER revert on oracle; fee is zero if oracle not ready. Only deposits/rebalances revert (first deposit/range-set bootstrap exempt) | Implemented + tested (T8b) |
| 6 | First-depositor share inflation / donation attack | Donate to inflate share price | `MINIMUM_LIQUIDITY` (1000) locked on first deposit, so donations are absorbed by locked shares; test shows the attack is unprofitable | Implemented + tested (T8b) |
| 7 | Fee overcharge | Curator sets excessive fee | Fee only on `max(0, value - hold)`; capped by `PROTOCOL_MAX_FEE_BPS`; crystallized at withdrawal | Implemented (T6) + fuzz (T8) |
| 8 | Fake alpha / self-reported performance | Curator reports returns | Alpha computed on-chain vs hold benchmark; AUM/volume never feed ranking | Partial (T7) |
| 9 | Reentrancy | Malicious token/hook callback | `ReentrancyGuard` on state-changing external fns; custom errors; `unlockCallback` is PoolManager-only | Implemented + tested (T8b) |
| 10 | Rounding drains vault | Repeated tiny withdrawals | All rounding down favors vault/remaining LPs | Implemented + fuzz (T8) |
| 11 | Pause used to trap LPs | Admin pauses withdrawals | Pause blocks deposits/rebalances only, never withdrawals | Implemented (T4) |
| 12 | Integer overflow in interval math | `lastTs + minInterval` overflows uint48 | Rewritten as subtraction; caught by fuzz | Fixed (T8) |
| 13 | Zero-operand division | `mulDiv` divides by zero when `a==0` | Explicit zero short-circuit; caught by fuzz | Fixed (T8) |

## Known limitations (honest)
- The hold benchmark rewards any LP return above hold, including what a passive LP would
  earn. It is an honest lower bound, not a claim of skill-sourcing.
- Envelope center-shift check now uses actual pre/post centers (T8b). NAV-loss bound realistically
  only catches rounding at a same-price re-centre (see OPEN_QUESTIONS.md).
- TWAP ring buffer truncation uses an in-place shift; gas review pending (T8/T9).
- Fork tests against the real PoolManager on Unichain Sepolia are not yet run; official
  addresses are verified and recorded in OPEN_QUESTIONS.md. T8b ships a local integration test
  against the canonical (in-process) v4 `PoolManager`; a networked fork is a T9 item.
- No deploy scripts exist yet; T8b item 8 (mine hook salts against the script's actual CREATE2
  deployer) is carried into T9 (see OPEN_QUESTIONS.md).

## Slither triage
`slither` is not installed in this environment (`slither: command not found`), so no
automated static-analysis results are claimed. This will be run and triaged here in T8
if the tool is available; otherwise it stays an open item. We do not report findings we
did not run.
