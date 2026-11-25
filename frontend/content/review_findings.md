# Review findings

## Envelope loosening through `tightenEnvelope`

`StrategyRegistry.tightenEnvelope` allowed a curator to replace an envelope with looser fields without
the timelock. Resolved in `114849d`. Guards: `RegistryTest.test_TightenInstant`,
`RegistryTest.test_TightenRevertsWhenAnyFieldLooser`, and
`EnvelopeLibTest.test_IsTighter_RejectsAnyLooserField`.

## Migrator and transfer basis

The migrator could leave value behind, and share transfers did not move the hold-basket cost basis,
so a recipient could be charged on the seller's principal. Resolved in `26385cc`. Guards:
`MigratorTest.test_MigrateMovesFullBalanceAndCrystallizesFee` and
`MigratorTest.test_TransferMovesCostBasis`.

## Same-block oracle manipulation

Swaps inside one block could overwrite the oracle sample with a price chosen by the swapper. Resolved
in `c9f2103`. Guard: `OracleTest.test_OneSamplePerBlock`.

## Cumulative-tick oracle math

The oracle did not weight cumulative ticks by elapsed time and mishandled windows that started before
the stored history. Resolved in `43355d9`. Guards: `OracleTest.test_ConstantTickHeldThirtyMinutesPositive`,
`OracleTest.test_ConstantTickHeldThirtyMinutesNegative`,
`OracleTest.test_StepFromZeroTo816AveragesAbout136`, and
`OracleTest.test_WindowStartBetweenSamplesAndLongerThanHistory`.

## Unbounded alpha history

Alpha checkpoints grew without limit, making reads and withdrawals more expensive as history grew.
Resolved in `6197da0`. Guards: `RegistryTest.test_AlphaHistoryBoundedByRingBuffer`,
`RegistryTest.test_GetAlphaGasIsSublinearInHistoryLength`,
`RegistryTest.test_LeaderboardPageIsBounded`, and
`LifecycleTest.test_WithdrawSucceedsWithLongAlphaHistory`.

## Seed swapped before liquidity

`Seed.s.sol` swapped on an empty pool, leaving the oracle unusable and the vault ranges unfunded.
Resolved in `306c1d3`. Guard: `SeedFlowTest.test_SeedOrderKeepsPoolUsable`.

## Withdrawal depended on price reads

A reverting `consult` or registry checkpoint could turn an exit into a revert or a fee. Resolved in
`7fbc182`. Guards: `WithdrawIndependenceTest.test_WithdrawWithConsultRevertPaysProRata`,
`WithdrawIndependenceTest.test_WithdrawWithRegistryRevertPaysProRata`, and
`WithdrawIndependenceTest.test_WithdrawWithStaleOraclePaysProRata`.

---

Rendered from commit b599bb68a1020923f1b4d0375a05eac030f1d616 · [View source](https://github.com/Sendi0011/Rudder/blob/b599bb68a1020923f1b4d0375a05eac030f1d616/docs/REVIEW_FINDINGS.md)
