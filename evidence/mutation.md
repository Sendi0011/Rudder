# Mutation results

| Mutation | Result | Regression test | Seconds |
| --- | --- | --- | --- |
| range_width | killed | `test_ValidateRangeWidth_TooLarge` | 91 |
| tick_spacing | killed | `test_HookRejectsMisalignedRangeFromBuggyVault` | 170 |
| center_shift | killed | `test_ValidateCenterShift_TooLarge` | 74 |
| rebalance_interval | killed | `test_ValidateInterval` | 81 |
| price_impact | killed | `test_ValidatePriceImpact` | 83 |
| nav_loss | killed | `test_ValidateNavLoss` | 77 |
| twap_distance | killed | `test_ValidateTwapDistance` | 77 |
| hook_range_width | killed | `test_HookRejectsWideRangeFromBuggyVault` | 164 |
| is_vault_gate | killed | `test_NonFactoryAddressRejectedByHookGate` | 187 |
| tighten_envelope | killed | `test_TightenRevertsWhenAnyFieldLooser` | 88 |
| withdraw_oracle_gate | killed | `test_WithdrawWithFewerThanTwoSamplesPaysProRata` | 184 |
| fee_when_oracle_not_ready | killed | `test_WithdrawZeroFeeWhenOracleStale` | 433 |
| hold_basket_on_transfer | killed | `test_TransferMovesCostBasis` | 160 |
| deposit_deviation_guard | killed | `test_DepositRejectedWhenSpotDeviatesFromTwap` | 173 |
| oracle_tick_time_factor | killed | `test_ConstantTickHeldThirtyMinutesPositive` | 203 |
