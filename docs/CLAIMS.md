# Claims

Each claim below names a local artifact and a command that produces or exercises it. A claim is
scoped to the stated limit. Nothing here asserts an audit, a live-network run or a partner
integration.

## Claims

| Claim | Evidence | Reproduce | Limit |
| --- | --- | --- | --- |
| Withdrawals succeed with a stale oracle and pay no performance fee | [WithdrawIndependenceTest](../contracts/test/WithdrawIndependence.t.sol) | `FOUNDRY_PROFILE=ci forge test --match-contract WithdrawIndependenceTest` | Local test state only |
| Rebalance swap cost lowers alpha by the NAV-per-share loss | [rebalance_alpha_cost.json](../evidence/rebalance_alpha_cost.json) | `WRITE_EVIDENCE=1 FOUNDRY_PROFILE=ci forge test --match-contract EvidenceTest --match-test test_RebalanceCostEvidence` | One deep-pool scenario |
| A churning vault ranks below a static vault by its summed rebalance cost | [churner_alpha.json](../evidence/churner_alpha.json) | `WRITE_EVIDENCE=1 FOUNDRY_PROFILE=ci forge test --match-contract EvidenceTest --match-test test_RebalanceCostEvidence` | Three local rebalances |
| Alpha does not change with vault size or mid-window deposits and withdrawals | [flow_invariance.json](../evidence/flow_invariance.json) | `WRITE_EVIDENCE=1 FOUNDRY_PROFILE=ci forge test --match-contract EvidenceTest --match-test test_FlowInvarianceEvidence` | Local scenario only |
| Oracle lookup stays bounded at ring capacity | [oracle_gas.json](../evidence/oracle_gas.json) | `WRITE_EVIDENCE=1 FOUNDRY_PROFILE=ci forge test --match-contract EvidenceTest --match-test test_OracleGasEvidence` | Local gas measurement |
| A tick step propagates into the TWAP with a measured gap | [twap_accuracy.json](../evidence/twap_accuracy.json) | `WRITE_EVIDENCE=1 FOUNDRY_PROFILE=ci forge test --match-contract EvidenceTest --match-test test_TwapAccuracyEvidence` | Local scenario only |
| Envelope checks are called at the vault rebalance call sites | [mutation.md](../evidence/mutation.md) | `bash scripts/mutation.sh --only vault_range_width_call` | Call-site mutants only |
| The deployed hook address encodes its permission bits | [DeployScriptTest](../contracts/test/DeployScriptTest.t.sol) | `FOUNDRY_PROFILE=ci forge test --match-contract DeployScriptTest` | Local CREATE2 proxy emulation |
| Recursive actions cannot exceed the bounded handler path | [VaultInvariantsTest](../contracts/test/VaultInvariants.t.sol) | `FOUNDRY_PROFILE=ci forge test --match-contract VaultInvariantsTest` | CI run settings only |

## Scope

The prior-art comparison is in [prior-art.md](prior-art.md). It reports a searched set, not global
priority. Deployment state is in [DEPLOYMENTS.md](DEPLOYMENTS.md).
