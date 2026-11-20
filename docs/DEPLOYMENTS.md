# Deployments

No live deployment has been broadcast from this repository. The table in
[`README.md`](../README.md#deployed-addresses) is empty and `contracts/deployments.json` records only
the network name.

The deploy script mines a CREATE2 salt at runtime against the canonical deterministic deployment
proxy and calls that proxy directly. The hook address therefore matches the mined address without
relying on Foundry's `new C{salt: ...}` sender. A local test runs the same path against an emulated
proxy; see `contracts/test/DeployScriptTest.t.sol`.

To record a deployment, run the script with `WRITE_DEPLOYMENTS=1`, copy the emitted addresses into
the README table and run:

```sh
bash scripts/verify-deployment.sh
```

The check compares the README with the artifact and, when addresses are present, checks contract code
and the hook/registry bindings through `UNICHAIN_SEPOLIA_RPC_URL`. It does not send a transaction.
