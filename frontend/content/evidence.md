# Evidence

Measurement artifacts live under [`evidence/`](https://github.com/Sendi0011/Rudder/blob/e2136aea016f055a33d630b075eedb1cc6db4667/evidence/README.md). They are produced by local
tests with an explicit write switch. A normal `forge test` run does not write them.

## Measurements

```sh
WRITE_EVIDENCE=1 FOUNDRY_PROFILE=ci forge test --match-contract EvidenceTest
WRITE_EVIDENCE=1 FOUNDRY_PROFILE=ci forge test --match-contract WorstCaseBoundTest
env K=30 FOUNDRY_OPTIMIZER=false FOUNDRY_VIA_IR=true WRITE_EVIDENCE=1 forge test --match-contract PlaceboCuratorsTest --block-gas-limit 20000000000 -vv
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
| `worst_case_loss.json` | `test_WorstCaseBoundCoversObservedRebalanceLosses` | Daily budget bounds against observed charged rebalance loss |
| `placebo_curators.json` | `test_PlaceboCuratorDistribution` | Curator alpha distribution in hundredths of a bps |
| `invariant_runs.json` | `invariant_ActionsExecuted` | Invariant run settings and action counters |

The `rankingGapBps` and `summedCostBps` fields in
[`churner_alpha.json`](https://github.com/Sendi0011/Rudder/raw/e2136aea016f055a33d630b075eedb1cc6db4667/evidence/churner_alpha.json) come from different measurements. The first is
the delta between registry alpha scores; the second sums direct pre/post NAV loss. In this run they
are 200 and 249 bps. The source assertion at
[`Evidence.t.sol:413-424`](https://github.com/Sendi0011/Rudder/raw/e2136aea016f055a33d630b075eedb1cc6db4667/contracts/test/Evidence.t.sol) allows a 40% relative gap, so the figures
are reported as tracking within that tolerance, not as equal.

The daily-budget artifact reports each tier's interval, NAV-loss floor, budget, bound, observed
charged loss and rebalance count over the horizon in
[`worst_case_loss.json`](https://github.com/Sendi0011/Rudder/raw/e2136aea016f055a33d630b075eedb1cc6db4667/evidence/worst_case_loss.json). `ObservedBps` sums charged
`LossBucketUpdated` costs rounded up to whole bps, and `BoundBps` is the daily budget. A rebalance
that is rejected by the bucket is not counted. These are accounting figures, not market drawdown.

| Tier | Interval | NAV-loss floor | Daily budget | Bound | Observed | Max charged step | Rebalances |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Conservative | 3,600 s | 50 bps | 200 bps | 200 bps | 198 bps | 31 bps | 16 |
| Balanced | 1,800 s | 100 bps | 500 bps | 500 bps | 495 bps | 31 bps | 33 |
| Aggressive | 600 s | 200 bps | 1,000 bps | 1,000 bps | 983 bps | 32 bps | 89 |

The largest charged step is 31, 31 and 32 bps against floors of 50, 100 and 200 bps in
[`worst_case_loss.json`](https://github.com/Sendi0011/Rudder/raw/e2136aea016f055a33d630b075eedb1cc6db4667/evidence/worst_case_loss.json). The local maximum-cost swaps do not reach
the per-action floor, so the floor is a ceiling in this sample rather than an observed step size.

The [`placebo_curators.json`](https://github.com/Sendi0011/Rudder/raw/e2136aea016f055a33d630b075eedb1cc6db4667/evidence/placebo_curators.json) sample uses fixed seeds, exact-input
swaps and shared local pools. `K` defaults to 30 and can be lowered with `K=n`; the published sample
uses 30 placebos per cell, giving 180 runs across six scenarios. Every vault is checkpointed with
`pokeAlpha()` after each price step, so a static or non-rebalancing curator still accrues alpha over
the same intervals. Alpha statistics, dispersion, drawdown and loss figures are stored in hundredths
of a bps.

| Statistic | Value |
| --- | --- |
| Reactive mean | -1961 |
| Static mean | -2 |
| Placebo mean | -939 |
| Placebo standard deviation | 2329 |
| Placebo minimum | -12013 |
| Placebo p25 | -1851 |
| Placebo p50 | -193 |
| Placebo p75 | 377 |
| Placebo maximum | 3486 |
| Reactive z-score × 100 | -43 |
| Worst rebalance loss | 9599 |
| Loss bound | 441108 |
| Drawdown versus hold | 11707 |

`reactiveVsPlaceboZScoreTimes100` is `(reactive mean − placebo mean) × 100 / placebo std`, stored as
an integer. The reactive mean sits below the placebo mean, so no curator edge is claimed. This is a
local stress comparison, not an estimate of live execution or fee income.

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
[`CLAIMS.md`](/docs/claims/) carries a README or prior-art marker, names a real source or test reference,
links one existing artifact, names one command and states one limit.

---

Rendered from commit e2136aea016f055a33d630b075eedb1cc6db4667 · [View source](https://github.com/Sendi0011/Rudder/blob/e2136aea016f055a33d630b075eedb1cc6db4667/docs/EVIDENCE.md)
