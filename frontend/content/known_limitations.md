# Known Limitations

Boundaries of the current Rudder implementation. Nothing here is a hidden caveat:
each item is either an accepted design trade-off or work that is not yet done.

## Design trade-offs

- **The hold benchmark is intentionally lenient.** Alpha is measured against simply holding the
  deposited assets, so a curator is credited for any return above hold, including what a passive
  LP would earn. This overstates active skill: the benchmark does not isolate skill from beta, from
  passive LP yield, or from the pool's own price path.
- **The NAV-loss bound is realistically a rounding guard.** Positions are valued at the TWAP before
  and after a rebalance, so a same-price re-centre preserves NAV to first order. Envelope authors
  should not rely on `maxNavLossBps` for large drawdown protection.
- **The rebalance centre is bounded to the TWAP tick.** This prevents liquidity from being parked
  away from the oracle price, at the cost of not allowing a curator to pre-position far from the
  current price.
- **Curator fees are pull-based.** Fees accrue into `pendingFees0/1` and are withdrawn by the fee
  recipient; the vault never pushes tokens to the recipient, so a reverting recipient cannot block
  LP withdrawals.
- **First deposit bootstraps the oracle.** A pool has no TWAP before it has liquidity to swap
  against, so the vault's first deposit and first range-set bypass the oracle-readiness gate. Every
  subsequent deposit and rebalance requires a ready oracle; the exemption is a one-way flag that
  never re-opens.

## What the envelope costs

- **Reaction is paced by the envelope.** After the first range-set, a curator cannot re-centre faster
  than `minRebalanceInterval`, cannot move the centre farther than `maxCenterShift` in one step and
  cannot continue once the daily budget is spent. A fast price path can outrun the range between
  allowed rebalances.
- **The tiers trade speed for protection.** Tighter envelopes lengthen the interval and shorten the
  allowed range, which reduces the room to act and the frequency of action at the same time. Looser
  envelopes buy responsiveness by allowing wider ranges and larger per-step loss.
- **The daily budget prices rebalance loss only.** The bucket charges TWAP-measured NAV loss from a
  rebalance; it does not cap market-price moves, fee opportunity cost or rounding in favor of LPs.
  The seeded budgets and observed charged loss are in
  [`evidence/worst_case_loss.json`](https://github.com/Sendi0011/Rudder/raw/3212ad666f4f528fc441666739df78ba7be5182b/evidence/worst_case_loss.json).
- **Tightening can leave the bucket above capacity.** A smaller budget lowers capacity immediately and
  does not clamp the stored charge, so rebalances stay blocked until time refills enough room. The
  choice is recorded in [`ADR-004`](/docs/adr/adr-004-daily-loss-budget/).

## Resolved

- **Alpha history and leaderboard reads are bounded.** A vault reports its cumulative alpha on every
  action, but samples are persisted into a fixed-capacity ring (720 slots) at most once per
  `CHECKPOINT_INTERVAL`, so a strategy that acts every block can no longer grow storage without bound.
  `getAlpha` binary-searches the ring, and the leaderboard scores at most `MAX_LEADERBOARD_PAGE` (100)
  bound strategies per call with `leaderboardPage` reaching later slices.
- **Ranking is return-based, not level-based.** The score is a cumulative per-interval
  `vaultReturn − holdReturn` fraction rather than a raw price difference, so vaults of different size
  and token decimals are comparable on the same scale.
- **Mid-window flows no longer distort the score.** The interval is accrued from the pre-action
  baseline and the baseline is rebased afterwards, so a large deposit or withdrawal inside the window
  is never mistaken for performance. The registry anchors the score at the lookback cutoff,
  interpolated between bracketing samples, so an extra checkpoint caused by that flow does not move
  the anchor. The first interval after launch is unscored: with one sample, the cutoff anchor is that
  sample itself.
- **Deposits are capped by a protocol ceiling.** The spot-vs-TWAP deviation bound on deposits is the
  tighter of the strategy envelope and `PROTOCOL_MAX_PRICE_IMPACT_BPS`, so a curator cannot disable the
  guard by widening its own envelope.
- **A registry failure cannot block exits.** The vault reports alpha best-effort, so a revert in the
  registry never turns a withdrawal into a revert.
- **Rebalance loss has a spendable daily allowance.** A leaky bucket in `RudderVault` caps the
  cumulative charge and refills continuously; the source mutants in
  [`evidence/mutation.md`](https://github.com/Sendi0011/Rudder/blob/3212ad666f4f528fc441666739df78ba7be5182b/evidence/mutation.md) cover the capacity, refill, rounding and
  validation checks.

## Not yet done

- **Fork test against the live network.** `contracts/test/Fork.t.sol` compiles and is skipped (not
  failed) when `UNICHAIN_SEPOLIA_RPC_URL` is unset. It has not been executed against a real RPC in
  this environment. The official Unichain Sepolia addresses are recorded in `OPEN_QUESTIONS.md`;
  the local integration suite runs against the canonical v4 `PoolManager` deployed in-process.
- **Deployment has only been dry-run.** `Deploy.s.sol` was exercised offline (no `--broadcast`);
  a real broadcast to Unichain Sepolia still requires an RPC and a funded key. The hook salt is
  mined at runtime against the CREATE2 deployer, so it cannot go stale.
- **No third-party audit.** The code has been exercised by unit, integration, fuzz and stateful
  invariant tests (see the test suite), but it has not been reviewed by an external auditor.
- **Static analysis not claimed.** `slither` was not available in the development environment, so
  no automated static-analysis results are asserted. We do not report tooling findings we did not
  run.

## Environment

- **`via-ir` is required.** The default compilation pipeline produces a "Stack too deep" error in
  `RudderVault.withdraw`; the project builds and tests with `--via-ir`.
- **Nested-submodule pointer drift.** `git status` can show `contracts/lib/v4-periphery` as dirty
  because its vendored submodules sit ahead of its pins. This is benign, does not affect the build,
  and does not reproduce on a fresh `git clone --recurse-submodules`. See `FEEDBACK.md §8`.

---

Rendered from commit 3212ad666f4f528fc441666739df78ba7be5182b · [View source](https://github.com/Sendi0011/Rudder/blob/3212ad666f4f528fc441666739df78ba7be5182b/docs/KNOWN_LIMITATIONS.md)
