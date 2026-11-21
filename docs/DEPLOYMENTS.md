# Deployments

No live deployment has been broadcast from this repository. The table in
[`README.md`](../README.md#deployed-addresses) is empty and `contracts/deployments.json` records only
the network name.

The deploy script mines a CREATE2 salt at runtime against the canonical deterministic deployment
proxy and calls that proxy directly. The hook address therefore matches the mined address without
relying on Foundry's `new C{salt: ...}` sender. A local test etches the canonical proxy runtime and
rejects a selector-encoded call; see `contracts/test/DeployScriptTest.t.sol`.

To record a deployment, run the script with `WRITE_DEPLOYMENTS=1`, copy the emitted addresses into
the README table and run:

```sh
bash scripts/verify-deployment.sh
```

The check prints a pass/fail table and exits non-zero on any failure. It compares the README with the
artifact and, when addresses are present, checks runtime code hashes, hook/registry bindings,
`hook.owner()` against `OWNER`, and `hook.isOracleReady(poolKey)` after activity through
`UNICHAIN_SEPOLIA_RPC_URL`. Immutable slots are zeroed in both the compiled artifact and the on-chain
runtime before hashing, so constructor-bound addresses are ignored. It does not send a transaction.
