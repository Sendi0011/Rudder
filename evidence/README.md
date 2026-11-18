# Evidence

Regenerate the measurement artifacts with:

```sh
forge test --match-contract EvidenceTest
```

- `oracle_gas.json` — `consult` gas at the start and at ring capacity.
- `twap_accuracy.json` — spot and TWAP ticks around a step change.
- `rebalance_bounds.json` — live envelope fields and a measured rebalance.
- `deposit_guard.json` — spot/TWAP deviation and the deposit cap that rejects it.
- `flow_invariance.json` — alpha under size changes and mid-window flows.
- `invariant_runs.json` — invariant run settings and handler revert rate.
