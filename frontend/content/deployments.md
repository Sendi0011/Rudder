# Deployments

Live deployment on Unichain Sepolia (chain `1301`) was broadcast on `2026-11-24` from commit
`aabf306`. Toolchain: `forge Version: 1.4.4-stable`, commit
`05794498bf47257b144e2e2789a1d5bf8566be0e`, built `2025-11-03T23:47:15.213010000Z`, profile
`maxperf`. The README table is filled from `contracts/deployments.json` and `contracts/seed.json`.
`broadcast/` holds the transaction receipts and is not committed.

The deploy script mines a CREATE2 salt at runtime against the canonical deterministic deployment
proxy and calls that proxy directly. The hook address therefore matches the mined address without
relying on Foundry's `new C{salt: ...}` sender. A local test etches the canonical proxy runtime and
rejects a selector-encoded call; see `contracts/test/DeployScriptTest.t.sol`.

The dry run predicted hook `0x19e5C142eF99698474E51E0CBcDFF768816c8880` (low 14 bits `0x880`) and
the script's `HookOwnerMismatch` guard confirmed `hook.owner() == OWNER`. The broadcast produced the
same addresses.

Every `forge script` call passes `--private-key "$PRIVATE_KEY" --sender "$DEPLOYER_ADDRESS"`. If
`DEPLOYER_ACCOUNT` is set, use `--account "$DEPLOYER_ACCOUNT" --sender "$DEPLOYER_ADDRESS"` instead.
Broadcasts also pass `--slow` so transactions stay ordered.

A dry run executes the script body, so `Deploy.s.sol` would overwrite `contracts/deployments.json`
with `WRITE_DEPLOYMENTS=1`. Run dry runs with `WRITE_DEPLOYMENTS=0`.

## Deployed contracts

| Contract | Address | Explorer |
| --- | --- | --- |
| RudderHook | `0x19e5C142eF99698474E51E0CBcDFF768816c8880` | [sepolia.uniscan.xyz](https://sepolia.uniscan.xyz/address/0x19e5c142ef99698474e51e0cbcdff768816c8880) |
| StrategyRegistry | `0x5C0638eaff9F0288a5FCe0589739f90f8E81D2f3` | [sepolia.uniscan.xyz](https://sepolia.uniscan.xyz/address/0x5c0638eaff9f0288a5fce0589739f90f8e81d2f3) |
| RudderVault implementation | `0x8A4e537889725c4A90F652657a9911B07D85FCb1` | [sepolia.uniscan.xyz](https://sepolia.uniscan.xyz/address/0x8a4e537889725c4a90f652657a9911b07d85fcb1) |
| VaultFactory | `0xef7e8C81a7B5c23D70390B481f30524b9C98cC0b` | [sepolia.uniscan.xyz](https://sepolia.uniscan.xyz/address/0xef7e8c81a7b5c23d70390b481f30524b9c98cc0b) |
| VaultMigrator | `0xD8bd8901d773F877b99d9e062435fA86C9eb2b91` | [sepolia.uniscan.xyz](https://sepolia.uniscan.xyz/address/0xd8bd8901d773f877b99d9e062435fa86c9eb2b91) |
| PoolManager | `0x00B036B58a818B1BC34d502D3fE730Db729e62AC` | [sepolia.uniscan.xyz](https://sepolia.uniscan.xyz/address/0x00b036b58a818b1bc34d502d3fe730db729e62ac) |
| Token0 | `0x1474d31bf469dEd9cae717CEDCF7F04e0F7aFc3b` | [sepolia.uniscan.xyz](https://sepolia.uniscan.xyz/address/0x1474d31bf469ded9cae717cedcf7f04e0f7afc3b) |
| Token1 | `0x38cC31de13281F81e4b88aEC290FE28616c5c4e6` | [sepolia.uniscan.xyz](https://sepolia.uniscan.xyz/address/0x38cc31de13281f81e4b88aec290fe28616c5c4e6) |
| Vault0 | `0x86fB893C2Dcb9EB5f16d8Fb641E827C610CA1f89` | [sepolia.uniscan.xyz](https://sepolia.uniscan.xyz/address/0x86fb893c2dcb9eb5f16d8fb641e827c610ca1f89) |
| Vault1 | `0xBFe8aD7DBF787bac8b49B85A922A641B85c33576` | [sepolia.uniscan.xyz](https://sepolia.uniscan.xyz/address/0xbfe8ad7dbf787bac8b49b85a922a641b85c33576) |
| Vault2 | `0xd9Ff3a77F9BD96D8De9E96ba977400cC2df63345` | [sepolia.uniscan.xyz](https://sepolia.uniscan.xyz/address/0xd9ff3a77f9bd96d8de9e96ba977400cc2df63345) |
| Swap router | `0xD4E00ea959628888e2DD7a53D75f41F8708fbE52` | [sepolia.uniscan.xyz](https://sepolia.uniscan.xyz/address/0xd4e00ea959628888e2dd7a53d75f41f8708fbe52) |

## Transaction hashes

From `broadcast/Deploy.s.sol/1301/run-latest.json` (not committed):

- `0x2dfb7181481d32e04d2ad2483e586c461308b725fe4fe8c4145ec21aac296a8c` — StrategyRegistry
- `0xb08e92b16f93a4667598bd348f95430a737a352a589dc3f0b87272ed0050a668` — RudderVault implementation
- `0x74fcb22b2db7855657773836904c4d1792eac59698ffe70ec9e7f3133ef2db59` — hook via CREATE2 proxy
- `0x2c9760e1427c3e7099a08cbfba6245961a318b6a5b730d00216825daf519d006` — VaultFactory
- `0x66648e2b8021f89c0b3c77a1e780ff09e7d4f10f27e38f0297b730e2c0dac58e` — `hook.setVaultFactory`
- `0xc8e822588bfd37eb0624365fb4d1d395f2359d8dabc040571280d4d4cb4adb2d` — `registry.setFactory`

VaultMigrator was broadcast separately with `forge create` on `2026-11-25` from commit `5b32e45`:

- `0xff07230c4624527237a193aaa7f8496f3a3fddbab734014e198f72e0c86933fb` — VaultMigrator deployment

From `broadcast/Seed.s.sol/1301/run-latest.json` (not committed):

- `0x6dbc494b47d2a22be1b0fe484bebd90bf66c8f4076051b28bb23d926994fccde` — token1 deployment
- `0x73baa021aa5eac4b836dc60c4cad8824cf0b72550e5e58c8b63ccf0dbdc1a6ba` — token0 deployment
- `0x2ff47d440fd67faedbe33d6bb7efe7597eb9240985e67900a9edc61cd0e90502` — token1 mint
- `0x882c2ca7e3c5ea3bc67f44c14602c38ee151011d91462cf03d0b5c6b78b2510c` — token0 mint
- `0x3564be142f4031ff13a898d7d0e79fde68f12a1261a582ba1e9b57753d9763f3` — swap router deployment
- `0x77783b388003cb4ef074e6bda679c380b4611b3f8d6929fe910a641b39100c78` — token0 approval
- `0xa3d1a5a253c7732f8e96982b11a23a597b8de88ebc78f7ee2ea20ce9222dc981` — token1 approval
- `0x2ffe97d7b3641bd44165bbcc67cf484b0ba52236a94dc509b2a85db368de258d` — pool initialize
- `0x3dd7ed6f5ac4370c732482a849ea030b135d604ff166592191e36cbaad4fdb89` — strategy 0 registration
- `0x0e07e59750884f0cba55e25b91227ee0b0a6f9764d70cca1d534bdf53d679917` — vault0 creation
- `0x20ac1e4ecf2dbfee3d74e934b06f7edf204091a2d3bf0f20c0a4211c1a583c79` — token0 approval for vault0
- `0xb216526969fc551d39a1b29124c21603211be3b7e74f41467c834b9be6249a39` — token1 approval for vault0
- `0x63e84d2d5572beb4bb09d928b4998ff7cebd1d30b704322d4d0ba30b4f6a772c` — vault0 rebalance
- `0xa9feccafc21d02afa103b24188c16be82126697ec3cdc9266ceac6d3d5d216e8` — vault0 deposit
- `0xe43b4ac499f7daf5ba087d40d9d8995b691730d9cf2c5eac0f7bdeb2396cea22` — strategy 1 registration
- `0xfae96dfd848b9643bdc62f0c02c19e78189d6c5a6c19e127eba78c95c90591b2` — vault1 creation
- `0x7ddb7b4ef4bf4e4c1ce930f109f9a203e3c36b999eeaa7bb2cdbef89bb742099` — token0 approval for vault1
- `0xd3772524c4c5e28cf16f95c04c416d006ad721507adc587e523002c6204ce6a5` — token1 approval for vault1
- `0x0f77bbcc172e8aaac59d16a2586c6bdb93132c34425ade3f486ed7ebc593f5ef` — vault1 rebalance
- `0xd47bba26fec419c9239129ae0a4e00f570ee89a41d11a84d90c813909922bf60` — vault1 deposit
- `0x3dabc247d20ec9250d36bbe01399c02a5048ab1f9cc0ff6c326c602940a38c8a` — strategy 2 registration
- `0x5399ee82747f204668920d6524f8d330f55ccd6f3080aad5a868f503794977d5` — vault2 creation
- `0x9b122e421805908709f5a9413b81cd951f30e2593783bf8ecba05fa73d3977ce` — token0 approval for vault2
- `0x565324979b92f531db7ed1b9d74617d583df31a136d65d2fb1cf66547a3795b6` — token1 approval for vault2
- `0xbf16a444653b043c35a15e895fa6618d553a2e7611ac8f8eec2af56709b4109d` — vault2 rebalance
- `0x7c96f0632d5d7d108f6173217755752dc2d5c30dcd2a600f154f339b5421606b` — vault2 deposit

## Checks before broadcast

- Deploy dry run: hook `0x19e5C142eF99698474E51E0CBcDFF768816c8880`, low 14 bits `0x880`, owner
  matched `OWNER`, `contracts/deployments.json` left empty by `WRITE_DEPLOYMENTS=0`.
- Seed dry run: three vaults and router predicted; broadcast produced the same addresses.
- Seed state: `contracts/seed.json` exists, pool tick `0` equals `START_TICK`, and all three vaults
  hold liquidity: vault0 `3383749980973837142785`, vault1 `1717249943619917122385`, vault2
  `884374709427154703939`.
- Fork lifecycle test at commit `aabf306`: `[PASS] test_Fork_DepositSwapRebalanceWithdraw()`,
  `1 passed; 0 failed; 0 skipped`.

## Activity

Six `Activity.s.sol` broadcasts with `ACTIVITY_RUN=0..5`, `--slow`, and 60 seconds between runs:

| Run | Pool tick | Narrowest vault range |
| --- | --- | --- |
| 0 | -1 | [-600, 600] |
| 1 | 0 | [-600, 600] |
| 2 | -1 | [-600, 600] |
| 3 | 0 | [-600, 600] |
| 4 | -1 | [-600, 600] |
| 5 | 0 | [-600, 600] |

Run 5 was killed by a tool timeout before any transaction was sent (broadcast hash was `null` and
the on-chain nonce was unchanged); a single rerun completed and produced the row above.

`hook.isOracleReady(poolKey)` returned `true`. Background loop started with:

```sh
nohup scripts/activity.sh > activity.log 2>&1 &
```

PID `38522` (also in the run directory). Stop it with `kill 38522`. `activity.log` is not committed.

## Explorer verification

`forge verify-contract` responses were `OK` on Unichain Sepolia:

| Contract | GUID | Explorer |
| --- | --- | --- |
| StrategyRegistry | `yds6jqluz4hbyqjnulvadxkp2ugg4ban9i772i3pdmgbsw6gjs` | [link](https://sepolia.uniscan.xyz/address/0x5c0638eaff9f0288a5fce0589739f90f8e81d2f3) |
| RudderVault implementation | `fsvc6bt35fjvqpwjtfjdkcj8mggjx5pqxbmhsxcxezemfiwi7y` | [link](https://sepolia.uniscan.xyz/address/0x8a4e537889725c4a90f652657a9911b07d85fcb1) |
| VaultFactory | `uqy7x49pqpj9xzrjye3mtv3dqmywuekydybysrehzu7pc5tfvk` | [link](https://sepolia.uniscan.xyz/address/0xef7e8c81a7b5c23d70390b481f30524b9c98cc0b) |
| RudderHook | `jifk6ymjibvdubwmxzpitzaldypf2jut19ucjhtdlyiummawtr` | [link](https://sepolia.uniscan.xyz/address/0x19e5c142ef99698474e51e0cbcdff768816c8880) |
| VaultMigrator | `hiphgxqcutlkb7wzhzu5y2tt34k5mvtw83jtjvptrd3dccbbtv` | [link](https://sepolia.uniscan.xyz/address/0xd8bd8901d773f877b99d9e062435fa86c9eb2b91) |

## Verification log

Use `--phase deploy` right after broadcasting `Deploy.s.sol`, then `--phase full` after Seed and
Activity and the README table fill:

```sh
bash scripts/verify-deployment.sh --phase deploy
bash scripts/verify-deployment.sh --phase full
```

Recorded output:

```text
$ bash scripts/verify-deployment.sh --phase deploy
| Check | Result | Detail |
| --- | --- | --- |
| runtime code: RudderHook | PASS | 7987 bytes |
| runtime code: StrategyRegistry | PASS | 7004 bytes |
| runtime code: RudderVault implementation | PASS | 18077 bytes |
| runtime code: VaultFactory | PASS | 2568 bytes |
| runtime code: VaultMigrator | PASS | 1549 bytes |
| runtime code: PoolManager | PASS | 24009 bytes |
| code hash: RudderHook | PASS | 5 immutable spans zeroed |
| code hash: StrategyRegistry | PASS | 0 immutable spans zeroed |
| code hash: RudderVault implementation | PASS | 0 immutable spans zeroed |
| code hash: VaultFactory | PASS | 8 immutable spans zeroed |
| code hash: VaultMigrator | PASS | 0 immutable spans zeroed |
| hook owner | PASS | 0xf55ad1AcDd9fE5b307F330ccD4D685A3040fb526 |
| factory hook | PASS | 0x19e5C142eF99698474E51E0CBcDFF768816c8880 |
| hook factory | PASS | 0xef7e8C81a7B5c23D70390B481f30524b9C98cC0b |
| hook pool manager | PASS | 0x00B036B58a818B1BC34d502D3fE730Db729e62AC |
| registry factory | PASS | 0xef7e8C81a7B5c23D70390B481f30524b9C98cC0b |
DEPLOY_OK: artifact, code and bindings

$ bash scripts/verify-deployment.sh --phase full
| Check | Result | Detail |
| --- | --- | --- |
| README address: RudderHook | PASS | 0x19e5C142eF99698474E51E0CBcDFF768816c8880 |
| README address: StrategyRegistry | PASS | 0x5C0638eaff9F0288a5FCe0589739f90f8E81D2f3 |
| README address: RudderVault implementation | PASS | 0x8A4e537889725c4A90F652657a9911B07D85FCb1 |
| README address: VaultFactory | PASS | 0xef7e8C81a7B5c23D70390B481f30524b9C98cC0b |
| README address: VaultMigrator | PASS | 0xD8bd8901d773F877b99d9e062435fA86C9eb2b91 |
| README address: PoolManager | PASS | 0x00B036B58a818B1BC34d502D3fE730Db729e62AC |
| runtime code: RudderHook | PASS | 7987 bytes |
| runtime code: StrategyRegistry | PASS | 7004 bytes |
| runtime code: RudderVault implementation | PASS | 18077 bytes |
| runtime code: VaultFactory | PASS | 2568 bytes |
| runtime code: VaultMigrator | PASS | 1549 bytes |
| runtime code: PoolManager | PASS | 24009 bytes |
| code hash: RudderHook | PASS | 5 immutable spans zeroed |
| code hash: StrategyRegistry | PASS | 0 immutable spans zeroed |
| code hash: RudderVault implementation | PASS | 0 immutable spans zeroed |
| code hash: VaultFactory | PASS | 8 immutable spans zeroed |
| code hash: VaultMigrator | PASS | 0 immutable spans zeroed |
| hook owner | PASS | 0xf55ad1AcDd9fE5b307F330ccD4D685A3040fb526 |
| factory hook | PASS | 0x19e5C142eF99698474E51E0CBcDFF768816c8880 |
| hook factory | PASS | 0xef7e8C81a7B5c23D70390B481f30524b9C98cC0b |
| hook pool manager | PASS | 0x00B036B58a818B1BC34d502D3fE730Db729e62AC |
| registry factory | PASS | 0xef7e8C81a7B5c23D70390B481f30524b9C98cC0b |
| oracle ready after activity | PASS | true |
DEPLOYMENTS_OK: 6 addresses
```

The check prints a pass/fail table and exits non-zero on any failure. It compares the README with the
artifact and, when addresses are present, checks runtime code hashes, hook/registry bindings,
`hook.owner()` against `OWNER`, and `hook.isOracleReady(poolKey)` after activity through
`UNICHAIN_SEPOLIA_RPC_URL`. Immutable slots are zeroed in both the compiled artifact and the on-chain
runtime before hashing, so constructor-bound addresses are ignored. It does not send a transaction.

---

Rendered from commit 5b32e45ae598940f532367a3840275bf257be677 · [View source](https://github.com/Sendi0011/Rudder/blob/5b32e45ae598940f532367a3840275bf257be677/docs/DEPLOYMENTS.md)
