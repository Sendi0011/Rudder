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
| 1 | Curator acts outside mandate | Out-of-bounds rebalance | `rebalance()` validates every bound via `EnvelopeLib`; out-of-bounds reverts with a specific error | Implemented |
| 2 | Curator drains LP funds | Withdraw/transfer | Curator has no withdraw rights; vault custody only | Implemented |
| 3 | Curator loosens envelope to rug LPs | Loosen bounds then act | Tightening instant; loosening timelocked (24h) so LPs can exit first | Implemented |
| 4 | Oracle manipulation via thin liquidity | Manipulated spot read as NAV | Prices sampled in `beforeSwap` (pre-swap) into a ring buffer, one sample per timestamp; TWAP via `consult()` feeds all NAV/fee/impact values; deposit deviation bound vs TWAP | Implemented |
| 5 | Stale/absent oracle blocks withdrawals | Bad oracle state | Withdrawals never revert on oracle; fee is zero if oracle not ready. Deposits/rebalances revert (first deposit/range-set bootstrap exempt) | Implemented + tested |
| 6 | First-depositor share inflation / donation attack | Donate to inflate share price | `MINIMUM_LIQUIDITY` (1000) locked on first deposit, so donations are absorbed by locked shares; test shows the attack is unprofitable | Implemented + tested |
| 7 | Fee overcharge | Curator sets excessive fee | Fee only on `max(0, value - hold)`; capped by `PROTOCOL_MAX_FEE_BPS`; crystallized at withdrawal | Implemented + fuzz |
| 8 | Fake alpha / self-reported performance | Curator reports returns | Alpha computed on-chain vs hold benchmark; AUM/volume never feed ranking | Implemented |
| 9 | Reentrancy | Malicious token/hook callback | `ReentrancyGuard` on state-changing external fns; custom errors; `unlockCallback` is PoolManager-only | Implemented + tested |
| 10 | Rounding drains vault | Repeated tiny withdrawals | All rounding down favors vault/remaining LPs | Implemented + fuzz |
| 11 | Pause used to trap LPs | Admin pauses withdrawals | Pause blocks deposits/rebalances only, never withdrawals | Implemented |
| 12 | Integer overflow in interval math | `lastTs + minInterval` overflows uint48 | Rewritten as a subtraction; caught by fuzz | Fixed |
| 13 | Zero-operand division | `mulDiv` divides by zero when `a==0` | Explicit zero short-circuit; caught by fuzz | Fixed |
| 14 | Malicious/unknown hook on a vault | Curator points a vault at an arbitrary hook | `VaultFactory` pins a single hook (bound once) and rejects any other; vault rejects uninitialized pools | Implemented + tested |

## Known limitations (honest)
See `KNOWN_LIMITATIONS.md` for the full, maintained list. In short: the hold benchmark is a
deliberate lower bound, the NAV-loss bound is a rounding guard rather than drawdown protection, the
fork test and deploy broadcast have not been run against a live RPC, and there is no third-party
audit.

## Static analysis
`slither` was not available in the development environment, so no automated static-analysis results
are claimed. We do not report tooling findings we did not run.
