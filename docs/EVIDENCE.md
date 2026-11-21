# Evidence

Measurement artifacts live under [`evidence/`](../evidence/README.md). They are produced by local
tests with an explicit write switch. A normal `forge test` run does not write them.

## Measurements

```sh
WRITE_EVIDENCE=1 FOUNDRY_PROFILE=ci forge test --match-contract EvidenceTest
WRITE_EVIDENCE=1 FOUNDRY_PROFILE=ci forge test --match-contract VaultInvariantsTest
```

| Artifact | Source | Claim |
| --- | --- | --- |
| `oracle_gas.json` | `test_OracleGasEvidence` | Oracle lookup at the start and at ring capacity |
| `twap_accuracy.json` | `test_TwapAccuracyEvidence` | Step response of the cumulative-tick TWAP |
| `rebalance_bounds.json` | `test_RebalanceBoundsEvidence` | Live envelope fields around a rebalance |
| `deposit_guard.json` | `test_DepositGuardEvidence` | Spot deviation against the deposit cap |
| `flow_invariance.json` | `test_FlowInvarianceEvidence` | Alpha under size and flow changes |
| `rebalance_alpha_cost.json` | `test_RebalanceCostEvidence` | NAV and alpha loss from a rebalance |
| `churner_alpha.json` | `test_RebalanceCostEvidence` | Ranking gap against summed rebalance cost |
| `invariant_runs.json` | `invariant_ActionsExecuted` | Invariant run settings and action counters |

## Other artifacts

```sh
bash scripts/mutation.sh
python3 scripts/prior_art/search.py
```

`mutation.md` records which regression test kills each source mutant. `prior_art_search.json` and
`prior_art_summary.md` record counts and dataset commits without copying entry prose into the
repository.

## Checks

```sh
bash scripts/check-docs.sh
bash scripts/check-claims.sh
```

The first compares README figures with the JSON artifacts. The second checks that each row in
[`CLAIMS.md`](CLAIMS.md) links one existing artifact, names one command and states one limit.
