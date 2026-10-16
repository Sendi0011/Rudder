# Known Limitations

Honest boundaries of the current Rudder implementation. Nothing here is a hidden caveat:
each item is either an accepted design trade-off or work that is not yet done.

## Design trade-offs

- **The hold benchmark is intentionally lenient.** Alpha is measured against simply holding the
  deposited assets, so a curator is credited for any return above hold, including what a passive
  LP would earn. It is an honest lower bound on value added, not a claim of skill-sourcing.
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

## Not yet done

- **Fork test against the live network.** `contracts/test/Fork.t.sol` compiles and is skipped (not
  failed) when `UNICHAIN_SEPOLIA_RPC_URL` is unset. It has not been executed against a real RPC in
  this environment. The official Unichain Sepolia addresses are verified and recorded in
  `OPEN_QUESTIONS.md`; the local integration suite runs against the canonical v4 `PoolManager`
  deployed in-process.
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
