# Mutation results

| Mutation | Result | Regression test | Seconds |
| --- | --- | --- | --- |
| range_width | killed | `test_ValidateRangeWidth_TooLarge` | 77 |
| tick_spacing | killed | `test_HookRejectsMisalignedRangeFromBuggyVault` | 159 |
| center_shift | killed | `test_ValidateCenterShift_TooLarge` | 82 |
| rebalance_interval | killed | `test_ValidateInterval` | 83 |
| price_impact | killed | `test_ValidatePriceImpact` | 99 |
| nav_loss | killed | `test_ValidateNavLoss` | 103 |
| twap_distance | killed | `test_ValidateTwapDistance` | 81 |
| hook_range_width | killed | `test_HookRejectsWideRangeFromBuggyVault` | 173 |
| is_vault_gate | killed | `test_NonFactoryAddressRejectedByHookGate` | 186 |
| tighten_envelope | killed | `test_TightenRevertsWhenAnyFieldLooser` | 73 |
| withdraw_oracle_gate | killed | `test_WithdrawWithFewerThanTwoSamplesPaysProRata` | 187 |
| fee_when_oracle_not_ready | killed | `test_WithdrawZeroFeeWhenOracleStale` | 190 |
| hold_basket_on_transfer | killed | `test_TransferMovesCostBasis` | 181 |
| deposit_deviation_guard | killed | `test_DepositRejectedWhenSpotDeviatesFromTwap` | 177 |
| oracle_tick_time_factor | killed | `test_ConstantTickHeldThirtyMinutesPositive` | 200 |
| vault_range_width_call | killed | `test_RevertOnRangeWidth` | 221 |
| vault_twap_distance_call | killed | `test_RebalanceRejectedWhenCenterTooFarFromTwap` | 228 |
| vault_interval_call | killed | `test_RevertOnInterval` | 341 |
| vault_center_shift_call | killed | `test_RevertOnCenterShift` | 434 |
| vault_price_impact_pre_call | killed | `test_RevertOnPriceImpact` | 291 |
| vault_price_impact_post_call | killed | `test_RebalanceStopsAtPriceLimitAndLeavesResidual` | 185 |
| vault_nav_loss_call | killed | `test_RevertOnNavLoss` | 202 |
| vault_alpha_cost_call | killed | `test_CostlyRebalanceChargesAlphaForNavLoss` | 178 |
| registry_checkpoint_interval_boundary | killed | `test_AlphaHistoryBoundedByRingBuffer` | 78 |
| leaderboard_page_cap_value | killed | `test_LeaderboardPageIsBounded` | 58 |
| protocol_price_impact_cap | killed | `test_DepositRejectedAboveProtocolCap` | 181 |
| registry_failure_exit_independence | killed | `test_WithdrawWithRegistryRevertPaysProRata` | 183 |
| oracle_one_sample_per_timestamp | killed | `test_OneSamplePerBlock` | 199 |
| poke_alpha_removes_accrue | killed | `test_PokeAlphaAccruesWithoutFlow` | 179 |
