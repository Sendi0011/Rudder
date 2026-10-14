# Open Questions
Record anything that cannot be verified (official Unichain Sepolia v4 addresses, RPCs, dependencies, etc.). Keep this append-only with timestamps/context.

- [x] Unichain Sepolia v4 addresses verified (2026-10-14) from official Uniswap docs
      https://docs.uniswap.org/contracts/v4/deployments (chainId 1301), sepolia.uniscan.xyz:
      - PoolManager:              0x00b036b58a818b1bc34d502d3fe730db729e62ac
      - PositionManager:          0xf969aee60879c54baaed9f3ed26147db216fd664 (unused by design; vaults call PoolManager.unlock directly)
      - StateView:                0xc199f1072a74d4e905aba1a84d9a45e2546b6222
      - V4Quoter:                 0x56dcd40a3f2d466f48e7f48bdbe5cc9b92ae4472
      - Universal Router:         0xf70536b3bcc1bd1a972dc186a2cf84cc6da6be5d
      - PoolSwapTest:             0x9140a78c1a137c7ff1c151ec8231272af78a99a4
      - PoolModifyLiquidityTest:  0x5fa728c0a5cfd51bee4b060773f50554c0c8a7ab
      - ReservesLens:             0x0000001b173C3bbF3984D417d8614E3eed34865B
- [ ] TWAP thresholds (min observations, max age) - TBD in T2 (with tests)
- [ ] minRebalanceInterval, envelope bounds defaults - TBD in T3/T5

## Resolved by T8b (2026-10-14)
- [x] Deposit/rebalance oracle bootstrap. A pool cannot have a TWAP before it has liquidity to
      swap against, so the vault's FIRST deposit and FIRST range-set bypass the "oracle ready" gate.
      Every subsequent deposit/rebalance requires a ready oracle. This is a deliberate, documented
      deviation from an unconditional gate; see RudderVault `depositOracle`/`rebalanceOracle`.
- [x] NAV-loss bound reachability. Because positions are valued at TWAP before and after a
      rebalance, a re-centre at the same price preserves NAV to first order; the bound realistically
      only catches rounding. The T8b test isolates it (all other bounds loose, tiny position) so the
      bound is exercised through a real execution. Envelope authors should not rely on it for large
      drawdown protection.
- [x] First-depositor inflation. `MINIMUM_LIQUIDITY` (1000) is locked to the vault on the first
      deposit. A donation-inflation attempt by the first depositor is economically unprofitable
      (locked shares absorb the donation); residual griefing (rounded-to-zero victim deposit reverts)
      is possible but bounded and non-appropriating. See Lifecycle test.

## Deferred to T9 (deploy)
- [ ] Real-network fork test (Unichain Sepolia) of deposit->swap->rebalance->withdraw. T8b ships a
      local integration test that runs against the canonical v4 `PoolManager` bytecode deployed
      in-process (real code, real unlock/sync/settle/take), not a mock. A networked fork needs an RPC
      and the verified PoolManager address above, which is a T9 concern.
- [ ] Deploy scripts (none exist yet) must mine hook salts against the exact CREATE2 deployer the
      script uses (per T8b item 8). No scripts to audit yet; captured here so it is not lost.
