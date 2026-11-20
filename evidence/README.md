# Evidence

Regenerate the measurement artifacts with:

```sh
WRITE_EVIDENCE=1 FOUNDRY_PROFILE=ci forge test --match-contract EvidenceTest
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
- `invariant_runs.json` — invariant run settings and handler revert rate.
