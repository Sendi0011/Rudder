# Evidence

Measurement artifacts live under [`evidence/`](../evidence/README.md). They are produced by local
tests with an explicit write switch. A normal `forge test` run does not write them.

## Measurements

```sh
WRITE_EVIDENCE=1 FOUNDRY_PROFILE=ci forge test --match-contract EvidenceTest
WRITE_EVIDENCE=1 FOUNDRY_PROFILE=ci forge test --match-contract WorstCaseBoundTest
env FOUNDRY_OPTIMIZER=false FOUNDRY_VIA_IR=true WRITE_EVIDENCE=1 forge test --match-contract PlaceboCuratorsTest -vv
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
| `worst_case_loss.json` | `test_WorstCaseBoundCoversObservedRebalanceLosses` | Compounded envelope bound against observed rebalance loss |
| `placebo_curators.json` | `test_PlaceboCuratorDistribution` | Reactive, static and random curator alpha distribution |
| `invariant_runs.json` | `invariant_ActionsExecuted` | Invariant run settings and action counters |

The `rankingGapBps` and `summedCostBps` fields in
[`churner_alpha.json`](../evidence/churner_alpha.json) come from different measurements. The first is
the delta between registry alpha scores; the second sums direct pre/post NAV loss. In this run they
are 200 and 249 bps. The source assertion at
[`Evidence.t.sol:413-424`](../contracts/test/Evidence.t.sol) allows a 40% relative gap, so the figures
are reported as tracking within that tolerance, not as equal.

The bound in [`worst_case_loss.json`](../evidence/worst_case_loss.json) compounds the per-rebalance
NAV-loss floor over the interval-spaced horizon described in
[`MANDATE.md:16-31`](MANDATE.md). It measures accounting loss from rebalancing, not market-price
drawdown. The same artifact reports the seeded tiers over an 86,400-second day; each tier uses
`floor(T/I) + 1` rebalances because the horizon starts at bootstrap and the first range-set skips the
interval check.

| Tier | Interval | NAV-loss floor | Rebalances | 24-hour bound |
| --- | --- | --- | --- | --- |
| Conservative | 3,600 s | -200 bps | 25 | 3,975 bps |
| Balanced | 1,800 s | -500 bps | 49 | 9,197 bps |
| Aggressive | 600 s | -500 bps | 145 | 10,000 bps |

The bounds are compounding accounting ceilings, not a spendable daily allowance. The conservative
tier keeps a residual floor above zero; the two faster tiers can reach the full 10,000 bps ceiling
under repeated maximum-loss rebalances.

The [`placebo_curators.json`](../evidence/placebo_curators.json) sample uses fixed seeds, exact-input
swaps and shared local pools. It compares reactive, static and random curators on the same price
paths. The reactive mean sits just above the placebo mean, so the result is reported as a narrow
margin. This is a local stress comparison, not an estimate of live execution or fee income.

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
[`CLAIMS.md`](CLAIMS.md) carries a README or prior-art marker, names a real source or test reference,
links one existing artifact, names one command and states one limit.
