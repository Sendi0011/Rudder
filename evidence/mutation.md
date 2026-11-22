# Mutation results

| Mutation | Result | Regression test | Seconds |
| --- | --- | --- | --- |
| range_width | killed | `test_ValidateRangeWidth_TooLarge` | 108 |
| tick_spacing | killed | `test_HookRejectsMisalignedRangeFromBuggyVault` | 231 |
| center_shift | killed | `test_ValidateCenterShift_TooLarge` | 103 |
| rebalance_interval | killed | `test_ValidateInterval` | 113 |
| price_impact | killed | `test_ValidatePriceImpact` | 109 |
| nav_loss | killed | `test_ValidateNavLoss` | 112 |
| twap_distance | killed | `test_ValidateTwapDistance` | 107 |
| hook_range_width | killed | `test_HookRejectsWideRangeFromBuggyVault` | 227 |
| is_vault_gate | killed | `test_NonFactoryAddressRejectedByHookGate` | 237 |
| tighten_envelope | killed | `test_TightenRevertsWhenAnyFieldLooser` | 104 |
| withdraw_oracle_gate | killed | `test_WithdrawWithFewerThanTwoSamplesPaysProRata` | 243 |
| fee_when_oracle_not_ready | killed | `test_WithdrawZeroFeeWhenOracleStale` | 274 |
| hold_basket_on_transfer | killed | `test_TransferMovesCostBasis` | 256 |
| deposit_deviation_guard | killed | `test_DepositRejectedWhenSpotDeviatesFromTwap` | 238 |
| oracle_tick_time_factor | killed | `test_ConstantTickHeldThirtyMinutesPositive` | 262 |
| vault_range_width_call | killed | `test_RevertOnRangeWidth` | 259 |
| vault_twap_distance_call | killed | `test_RebalanceRejectedWhenCenterTooFarFromTwap` | 239 |
| vault_interval_call | killed | `test_RevertOnInterval` | 273 |
| vault_center_shift_call | killed | `test_RevertOnCenterShift` | 257 |
| vault_price_impact_pre_call | killed | `test_RevertOnPriceImpact` | 265 |
| vault_price_impact_post_call | killed | `test_RebalanceStopsAtPriceLimitAndLeavesResidual` | 253 |
| vault_nav_loss_call | killed | `test_RevertOnNavLoss` | 260 |
| vault_alpha_cost_call | killed | `test_CostlyRebalanceChargesAlphaForNavLoss` | 239 |
| registry_checkpoint_interval_boundary | killed | `test_AlphaHistoryBoundedByRingBuffer` | 141 |
| leaderboard_page_cap_value | killed | `test_LeaderboardPageIsBounded` | 316 |
| protocol_price_impact_cap | killed | `test_DepositRejectedAboveProtocolCap` | 479 |
| registry_failure_exit_independence | killed | `test_WithdrawWithRegistryRevertPaysProRata` | 597 |
| oracle_one_sample_per_timestamp | killed | `test_OneSamplePerBlock` | 716 |
| poke_alpha_removes_accrue | killed | `test_PokeAlphaAccruesWithoutFlow` | 554 |
