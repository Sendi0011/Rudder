# ADR-001: Rudder Architecture
Date: 2026-10-13

## Decisions
- Vaults call PoolManager.unlock directly (no PositionManager NFT). Hook sees vault as sender.
- Envelope enforcement in vault; hook handles gating, TWAP ring buffer (afterSwap), pool-level logic.
- Vault shares ERC-20 clones. Per-account hold basket stores (amount0,amount1) only; valuation at withdrawal against TWAP.
- Oracle safety: withdrawals MUST NEVER revert on oracle state. If TWAP stale or < min observations, withdraw succeeds with zero performance fee. Deposits and rebalances revert on bad oracle.
- Pause blocks deposits/rebalances only; never withdrawals. Tightening instant; loosening timelocked.
- Ranking alpha-vs-hold over lookback; AUM/volume display-only. One-tx migration; fee crystallizes on exit.
- First-depositor share inflation (donation attack) protection via virtual shares or minimum-liquidity lock.
- Rounding favors vault and remaining LPs. ReentrancyGuard, custom errors, NatSpec on all external. Solidity 0.8.26, Foundry, via_ir if needed, evm_version cancun.
- Unichain Sepolia; verify official v4 addresses from docs; record unknowns in OPEN_QUESTIONS.md.
- Known limitation: hold benchmark rewards any LP return above hold including passive LP return.

## Solvency Invariant
Holdings (idle + position amounts + uncollected fees) cover outstanding share redemptions. 
Balances sum to totalSupply: sum of all account balances == totalSupply for each share token. 
Rounding favors vault and remaining LPs.

---

Rendered from commit e2136aea016f055a33d630b075eedb1cc6db4667 · [View source](https://github.com/Sendi0011/Rudder/blob/e2136aea016f055a33d630b075eedb1cc6db4667/docs/adr/ADR-001-architecture.md)
