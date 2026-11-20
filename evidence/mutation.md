# Mutation results

| Mutation | Result | Regression test | Seconds |
| --- | --- | --- | --- |
| range_width | killed | `test_ValidateRangeWidth_TooLarge` | 146 |
| tick_spacing | killed | `test_HookRejectsMisalignedRangeFromBuggyVault` | 358 |
| center_shift | killed | `test_ValidateCenterShift_TooLarge` | 148 |
| rebalance_interval | killed | `test_ValidateInterval` | 154 |
| price_impact | killed | `test_ValidatePriceImpact` | 162 |
| nav_loss | killed | `test_ValidateNavLoss` | 156 |
| twap_distance | killed | `test_ValidateTwapDistance` | 174 |
| hook_range_width | killed | `test_HookRejectsWideRangeFromBuggyVault` | 298 |
| is_vault_gate | killed | `test_NonFactoryAddressRejectedByHookGate` | 162 |
| tighten_envelope | killed | `test_TightenRevertsWhenAnyFieldLooser` | 69 |
| withdraw_oracle_gate | killed | `test_WithdrawWithFewerThanTwoSamplesPaysProRata` | 178 |
| fee_when_oracle_not_ready | killed | `test_WithdrawZeroFeeWhenOracleStale` | 180 |
| hold_basket_on_transfer | killed | `test_TransferMovesCostBasis` | 173 |
| deposit_deviation_guard | killed | `test_DepositRejectedWhenSpotDeviatesFromTwap` | 170 |
| oracle_tick_time_factor | killed | `test_ConstantTickHeldThirtyMinutesPositive` | 212 |
| vault_range_width_call | killed | `test_RevertOnRangeWidth` | 193 |
| vault_twap_distance_call | killed | `test_RebalanceRejectedWhenCenterTooFarFromTwap` | 178 |
| vault_interval_call | killed | `test_RevertOnInterval` | 197 |
| vault_center_shift_call | killed | `test_RevertOnCenterShift` | 198 |
| vault_price_impact_pre_call | killed | `test_RevertOnPriceImpact` | 216 |
| vault_price_impact_post_call | killed | `test_RebalanceStopsAtPriceLimitAndLeavesResidual` | 178 |
| vault_nav_loss_call | killed | `test_RevertOnNavLoss` | 237 |
| vault_alpha_cost_call | killed | `test_CostlyRebalanceChargesAlphaForNavLoss` | 294 |
