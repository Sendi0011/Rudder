# Evidence

Regenerate the measurement artifacts with:

```sh
WRITE_EVIDENCE=1 FOUNDRY_PROFILE=ci forge test --match-contract EvidenceTest
WRITE_EVIDENCE=1 FOUNDRY_PROFILE=ci forge test --match-contract WorstCaseBoundTest
env FOUNDRY_OPTIMIZER=false FOUNDRY_VIA_IR=true WRITE_EVIDENCE=1 forge test --match-contract PlaceboCuratorsTest -vv
WRITE_EVIDENCE=1 FOUNDRY_PROFILE=ci forge test --match-contract VaultInvariantsTest
```

Normal test runs leave these files unchanged.

- `oracle_gas.json` — `consult` gas at the start and at ring capacity.
- `twap_accuracy.json` — spot and TWAP ticks around a step change.
- `rebalance_bounds.json` — live envelope fields and a measured rebalance.
- `deposit_guard.json` — spot/TWAP deviation and the deposit cap that rejects it.
- `flow_invariance.json` — alpha under size changes and mid-window flows.
- `rebalance_alpha_cost.json` — NAV and alpha loss from a measured rebalance.
- `churner_alpha.json` — ranking gap against summed rebalance cost.
- `worst_case_loss.json` — seeded daily budgets, bounds, observed charged loss and rebalance counts.
- `placebo_curators.json` — curator alpha distribution in hundredths of a bps with K and z-score.
- `invariant_runs.json` — invariant run settings and handler revert rate.
