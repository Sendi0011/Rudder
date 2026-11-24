# Deployments

No live deployment has been broadcast from this repository. The table in
[`README.md`](../README.md#deployed-addresses) is empty and `contracts/deployments.json` records only
the network name.

The deploy script mines a CREATE2 salt at runtime against the canonical deterministic deployment
proxy and calls that proxy directly. The hook address therefore matches the mined address without
relying on Foundry's `new C{salt: ...}` sender. A local test etches the canonical proxy runtime and
rejects a selector-encoded call; see `contracts/test/DeployScriptTest.t.sol`.

Every `forge script` call passes `--private-key "$PRIVATE_KEY" --sender "$DEPLOYER_ADDRESS"`. If
`DEPLOYER_ACCOUNT` is set, use `--account "$DEPLOYER_ACCOUNT" --sender "$DEPLOYER_ADDRESS"` instead.
Broadcasts also pass `--slow` so transactions stay ordered.

A dry run executes the script body, so `Deploy.s.sol` would overwrite `contracts/deployments.json`
with `WRITE_DEPLOYMENTS=1`. Run dry runs with `WRITE_DEPLOYMENTS=0`.

Use `--phase deploy` right after broadcasting `Deploy.s.sol`: it checks the artifact, runtime code
and code hashes, hook owner and contract bindings, without needing README addresses or `seed.json`.
After Seed and Activity, fill the README table from the artifact and run the full check:

```sh
bash scripts/verify-deployment.sh --phase deploy
bash scripts/verify-deployment.sh --phase full
```

The check prints a pass/fail table and exits non-zero on any failure. It compares the README with the
artifact and, when addresses are present, checks runtime code hashes, hook/registry bindings,
`hook.owner()` against `OWNER`, and `hook.isOracleReady(poolKey)` after activity through
`UNICHAIN_SEPOLIA_RPC_URL`. Immutable slots are zeroed in both the compiled artifact and the on-chain
runtime before hashing, so constructor-bound addresses are ignored. It does not send a transaction.
