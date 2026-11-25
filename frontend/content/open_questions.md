# Open Questions

Anything that cannot be established from this repository, or that remains a deliberate open item.
Kept short and current.

## Open

- **Live-network fork run.** `contracts/test/Fork.t.sol` compiles and is skipped (not failed) when
  `UNICHAIN_SEPOLIA_RPC_URL` is unset. It has not been executed against a real RPC here. Run with:
  `UNICHAIN_SEPOLIA_RPC_URL=<rpc> forge test --match-contract ForkLifecycleTest -vvv`.
- **Deploy broadcast.** `Deploy.s.sol` has only been dry-run (`forge script contracts/script/Deploy.s.sol:Deploy`,
  no `--broadcast`). A real broadcast needs an RPC and a funded key. The hook salt is mined at
  runtime against the CREATE2 deployer, so it cannot go stale.
- **Gas review of the oracle ring buffer.** `RudderHook` uses a fixed-capacity ring buffer;
  gas costs at capacity have not been benchmarked.
- **Static analysis.** `slither` was not installed in the development environment, so no automated
  static-analysis results are claimed.

## Reference

- **Unichain Sepolia v4 addresses** (chainId 1301), from
  https://docs.uniswap.org/contracts/v4/deployments and sepolia.uniscan.xyz:
  - PoolManager:              `0x00b036b58a818b1bc34d502d3fe730db729e62ac`
  - PositionManager:          `0xf969aee60879c54baaed9f3ed26147db216fd664` (unused by design; vaults call `PoolManager.unlock` directly)
  - StateView:                `0xc199f1072a74d4e905aba1a84d9a45e2546b6222`
  - V4Quoter:                 `0x56dcd40a3f2d466f48e7f48bdbe5cc9b92ae4472`
  - Universal Router:         `0xf70536b3bcc1bd1a972dc186a2cf84cc6da6be5d`
  - PoolSwapTest:             `0x9140a78c1a137c7ff1c151ec8231272af78a99a4`
  - PoolModifyLiquidityTest:  `0x5fa728c0a5cfd51bee4b060773f50554c0c8a7ab`
  - ReservesLens:             `0x0000001b173C3bbF3984D417d8614E3eed34865B`
- **Fresh-clone build.** `git clone --recurse-submodules` into a clean directory builds and passes
  the full suite (the clean clone's `v4-periphery` is not dirty; the local ` m` is benign nested
  pointer drift — see `FEEDBACK.md §8`).
- **Oracle bootstrap.** A pool cannot have a TWAP before it has liquidity to swap against, so the
  vault's first deposit and first range-set bypass the "oracle ready" gate; every subsequent
  deposit/rebalance requires a ready oracle. The exemption is a one-way flag (see `KNOWN_LIMITATIONS.md`).
- **NAV-loss bound reachability.** Positions are valued at the TWAP before and after a rebalance, so
  a same-price re-centre preserves NAV to first order; the bound realistically only catches
  rounding. Envelope authors should not rely on it for large drawdown protection.
- **First-depositor inflation.** `MINIMUM_LIQUIDITY` (1000) is locked to the vault on the first
  deposit; a donation-inflation attempt is economically unprofitable. Residual griefing (a
  rounded-to-zero victim deposit reverts) is possible but bounded and non-appropriating.

---

Rendered from commit cee9100a4c4fa976728806331a6177b82c568d6d · [View source](https://github.com/Sendi0011/Rudder/blob/cee9100a4c4fa976728806331a6177b82c568d6d/docs/OPEN_QUESTIONS.md)
