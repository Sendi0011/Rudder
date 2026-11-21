#!/usr/bin/env bash
set -u

SOURCE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COPY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rudder-mutation.XXXXXX")"
REPORT="$COPY_DIR/evidence/mutation.md"
MUTATION_TIMEOUT="${MUTATION_TIMEOUT:-900}"
ONLY=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --only)
            ONLY="${2:-}"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

run_with_timeout() {
    local seconds="$1"
    local log="$2"
    shift 2

    python3 - "$seconds" "$log" "$@" <<'PY'
import subprocess
import sys

seconds = float(sys.argv[1])
log = sys.argv[2]
cmd = sys.argv[3:]
with open(log, "w") as handle:
    try:
        code = subprocess.run(cmd, stdout=handle, stderr=subprocess.STDOUT, timeout=seconds).returncode
    except subprocess.TimeoutExpired:
        code = 124
raise SystemExit(code)
PY
}

cleanup() {
    if [ "${MUTATION_KEEP:-0}" = "1" ]; then
        echo "$COPY_DIR" >&2
        return
    fi
    rm -rf "$COPY_DIR"
}
trap cleanup EXIT

rsync -a --exclude '.git' --exclude 'cache' "$SOURCE_DIR/" "$COPY_DIR/"
cd "$COPY_DIR"
mkdir -p "$COPY_DIR/.mutation-backup" "$COPY_DIR/.mutation-logs"

if [ -n "$ONLY" ] && [ -f "$SOURCE_DIR/evidence/mutation.md" ]; then
    cp "$SOURCE_DIR/evidence/mutation.md" "$REPORT"
else
    printf '# Mutation results\n\n| Mutation | Result | Regression test | Seconds |\n| --- | --- | --- | --- |\n' > "$REPORT"
fi

MUTATIONS=(
    range_width
    tick_spacing
    center_shift
    rebalance_interval
    price_impact
    nav_loss
    twap_distance
    hook_range_width
    is_vault_gate
    tighten_envelope
    withdraw_oracle_gate
    fee_when_oracle_not_ready
    hold_basket_on_transfer
    deposit_deviation_guard
    oracle_tick_time_factor
    vault_range_width_call
    vault_twap_distance_call
    vault_interval_call
    vault_center_shift_call
    vault_price_impact_pre_call
    vault_price_impact_post_call
    vault_nav_loss_call
    vault_alpha_cost_call
    registry_checkpoint_interval_boundary
    leaderboard_page_cap_value
    protocol_price_impact_cap
    registry_failure_exit_independence
    oracle_one_sample_per_timestamp
    poke_alpha_removes_accrue
)

TESTS=(
    test_ValidateRangeWidth_TooLarge
    test_HookRejectsMisalignedRangeFromBuggyVault
    test_ValidateCenterShift_TooLarge
    test_ValidateInterval
    test_ValidatePriceImpact
    test_ValidateNavLoss
    test_ValidateTwapDistance
    test_HookRejectsWideRangeFromBuggyVault
    test_NonFactoryAddressRejectedByHookGate
    test_TightenRevertsWhenAnyFieldLooser
    test_WithdrawWithFewerThanTwoSamplesPaysProRata
    test_WithdrawZeroFeeWhenOracleStale
    test_TransferMovesCostBasis
    test_DepositRejectedWhenSpotDeviatesFromTwap
    test_ConstantTickHeldThirtyMinutesPositive
    test_RevertOnRangeWidth
    test_RebalanceRejectedWhenCenterTooFarFromTwap
    test_RevertOnInterval
    test_RevertOnCenterShift
    test_RevertOnPriceImpact
    test_RebalanceStopsAtPriceLimitAndLeavesResidual
    test_RevertOnNavLoss
    test_CostlyRebalanceChargesAlphaForNavLoss
    test_AlphaHistoryBoundedByRingBuffer
    test_LeaderboardPageIsBounded
    test_DepositRejectedAboveProtocolCap
    test_WithdrawWithRegistryRevertPaysProRata
    test_OneSamplePerBlock
    test_PokeAlphaAccruesWithoutFlow
)

find_test() {
    local wanted="$1"
    local i
    for i in "${!MUTATIONS[@]}"; do
        if [ "${MUTATIONS[$i]}" = "$wanted" ]; then
            printf '%s\n' "${TESTS[$i]}"
            return 0
        fi
    done
    return 1
}

apply_mutation() {
    python3 - "$1" "$2" <<'PY'
import shutil
import sys
from pathlib import Path

name, root = sys.argv[1], Path(sys.argv[2])
patches = {
    "range_width": (
        "contracts/src/libraries/EnvelopeLib.sol",
        """        if (width > maxWidth) revert InvalidRangeWidth(width, maxWidth);""",
        """        {}""",
    ),
    "tick_spacing": (
        "contracts/src/RudderHook.sol",
        """        if (spacing <= 0 || lo % spacing != 0 || hi % spacing != 0) revert RangeNotAligned();""",
        """        {}""",
    ),
    "center_shift": (
        "contracts/src/libraries/EnvelopeLib.sol",
        """        if (dist > maxShift) revert InvalidCenterShift(dist, maxShift);""",
        """        {}""",
    ),
    "rebalance_interval": (
        "contracts/src/libraries/EnvelopeLib.sol",
        """        if (nowTs < lastTs || nowTs - lastTs < minInterval) {
            revert IntervalTooShort(lastTs, nowTs, minInterval);
        }""",
        """        {}""",
    ),
    "price_impact": (
        "contracts/src/libraries/EnvelopeLib.sol",
        """        if (impactBps > maxImpactBps) revert PriceImpactTooHigh(impactBps, maxImpactBps);""",
        """        {}""",
    ),
    "nav_loss": (
        "contracts/src/libraries/EnvelopeLib.sol",
        """        if (lossBps < maxLossBps) revert NavLossTooLarge(lossBps, maxLossBps);""",
        """        {}""",
    ),
    "twap_distance": (
        "contracts/src/libraries/EnvelopeLib.sol",
        """        if (dist > maxDistance) revert InvalidParams();""",
        """        {}""",
    ),
    "hook_range_width": (
        "contracts/src/RudderHook.sol",
        """        EnvelopeLib.validateRangeWidth(width, env.maxRangeWidth);""",
        """        {}""",
    ),
    "is_vault_gate": (
        "contracts/src/RudderHook.sol",
        """        if (!IVaultFactory(vaultFactory).isVault(sender)) revert OnlyVault();""",
        """        {}""",
    ),
    "tighten_envelope": (
        "contracts/src/StrategyRegistry.sol",
        """        if (!EnvelopeLib.isTighter(strategies[id].envelope, newEnv)) revert EnvelopeLib.NotTighter();""",
        """        {}""",
    ),
    "withdraw_oracle_gate": (
        "contracts/src/RudderVault.sol",
        """        if (userShares < shares) revert InsufficientBalance();
        uint256 supply = totalSupply();""",
        """        if (userShares < shares) revert InsufficientBalance();
        if (!IRudderHook(hook).isOracleReady(poolKey)) revert OracleBad();
        uint256 supply = totalSupply();""",
    ),
    "fee_when_oracle_not_ready": (
        "contracts/src/RudderVault.sol",
        """        if (!IRudderHook(hook).isOracleReady(poolKey)) return (0, 0);""",
        """        {}""",
    ),
    "hold_basket_on_transfer": (
        "contracts/src/RudderVault.sol",
        """        if (from != address(0) && to != address(0)) {""",
        """        if (false) {""",
    ),
    "deposit_deviation_guard": (
        "contracts/src/RudderVault.sol",
        """            if (_priceImpactBps(_spotSqrtPrice(), _twapSqrtPrice()) > cap) revert SpotTwapDeviation();""",
        """            {}""",
    ),
    "oracle_tick_time_factor": (
        "contracts/src/RudderHook.sol",
        """            tickCumulative = last.tickCumulative + int56(tick) * int56(uint56(block.timestamp - last.timestamp));""",
        """            tickCumulative = last.tickCumulative + int56(tick);""",
    ),
    "vault_range_width_call": (
        "contracts/src/RudderVault.sol",
        """        EnvelopeLib.validateRangeWidth(width, env.maxRangeWidth);""",
        """        {}""",
    ),
    "vault_twap_distance_call": (
        "contracts/src/RudderVault.sol",
        """        EnvelopeLib.validateTwapDistance(newCenter, TickMath.getTickAtSqrtPrice(twap), env.maxTwapDistanceTicks);""",
        """        {}""",
    ),
    "vault_interval_call": (
        "contracts/src/RudderVault.sol",
        """            EnvelopeLib.validateInterval(
                uint48(lastRebalanceTimestamp), uint48(block.timestamp), env.minRebalanceInterval
            );""",
        """            {}""",
    ),
    "vault_center_shift_call": (
        "contracts/src/RudderVault.sol",
        """            EnvelopeLib.validateCenterShift(newCenter - oldCenter, env.maxCenterShift);""",
        """            {}""",
    ),
    "vault_price_impact_pre_call": (
        "contracts/src/RudderVault.sol",
        """        EnvelopeLib.validatePriceImpact(_priceImpactBps(spot, twap), env.maxPriceImpactBps);""",
        """        revert("PRE_IMPACT");""",
    ),
    "vault_price_impact_post_call": (
        "contracts/src/RudderVault.sol",
        """        EnvelopeLib.validatePriceImpact(_priceImpactBps(_spotSqrtPrice(), twap), env.maxPriceImpactBps);""",
        """        revert("POST_IMPACT");""",
    ),
    "vault_nav_loss_call": (
        "contracts/src/RudderVault.sol",
        """        EnvelopeLib.validateNavLoss(_navLossBps(preNav, postNav), env.maxNavLossBps);""",
        """        {}""",
    ),
    "vault_alpha_cost_call": (
        "contracts/src/RudderVault.sol",
        """        _accrueAlphaInterval();

        lastRebalanceTimestamp = uint48(block.timestamp);""",
        """        lastRebalanceTimestamp = uint48(block.timestamp);""",
    ),
    "registry_checkpoint_interval_boundary": (
        "contracts/src/StrategyRegistry.sol",
        """        if (h.count == 0 || block.timestamp - _newestTs(h) >= CHECKPOINT_INTERVAL) {""",
        """        if (h.count == 0 || block.timestamp - _newestTs(h) > CHECKPOINT_INTERVAL) {""",
    ),
    "leaderboard_page_cap_value": (
        "contracts/src/StrategyRegistry.sol",
        """    uint256 public constant MAX_LEADERBOARD_PAGE = 100;""",
        """    uint256 public constant MAX_LEADERBOARD_PAGE = 1;""",
    ),
    "protocol_price_impact_cap": (
        "contracts/src/RudderVault.sol",
        """            uint32 cap = env.maxPriceImpactBps < PROTOCOL_MAX_PRICE_IMPACT_BPS
                ? env.maxPriceImpactBps
                : PROTOCOL_MAX_PRICE_IMPACT_BPS;""",
        """            uint32 cap = env.maxPriceImpactBps;""",
    ),
    "registry_failure_exit_independence": (
        "contracts/src/RudderVault.sol",
        """        try IStrategyRegistry(registry).checkpointAlpha(strategyId, cumulativeAlpha) {} catch {}""",
        """        IStrategyRegistry(registry).checkpointAlpha(strategyId, cumulativeAlpha);""",
    ),
    "oracle_one_sample_per_timestamp": (
        "contracts/src/RudderHook.sol",
        """        if (o.count > 0 && _newest(o).timestamp == uint32(block.timestamp)) return;""",
        """        {}""",
    ),
    "poke_alpha_removes_accrue": (
        "contracts/src/RudderVault.sol",
        """        _clearPriceCache();
        _accrueAlphaInterval();
        _rebaseAlphaBaseline();
        emit AlphaPoked(msg.sender, cumulativeAlpha);""",
        """        _clearPriceCache();
        _rebaseAlphaBaseline();
        emit AlphaPoked(msg.sender, cumulativeAlpha);""",
    ),
}

relative, old, new = patches[name]
path = root / relative
text = path.read_text()
if old not in text:
    raise SystemExit(f"mutation target not found: {name}: {relative}")
backup = root / ".mutation-backup" / f"{name}.sol"
shutil.copyfile(path, backup)
path.write_text(text.replace(old, new, 1))
print(relative)
PY
}

for mutation in "${MUTATIONS[@]}"; do
    if [ -n "$ONLY" ] && [ "$mutation" != "$ONLY" ]; then
        continue
    fi

    test_name="$(find_test "$mutation")"
    relative_file="$(apply_mutation "$mutation" "$COPY_DIR")"
    if [ -z "$relative_file" ]; then
        echo "failed to apply $mutation" >&2
        exit 1
    fi

    log="$COPY_DIR/.mutation-logs/$mutation.log"
    if [ -n "${MUTATION_DEBUG_LOG_DIR:-}" ]; then
        cp "$COPY_DIR/$relative_file" "$MUTATION_DEBUG_LOG_DIR/$mutation.sol"
    fi
    start="$(date +%s)"
    run_with_timeout "$MUTATION_TIMEOUT" "$log" env FOUNDRY_PROFILE=ci FOUNDRY_OPTIMIZER=false FOUNDRY_VIA_IR=true forge test --match-test "$test_name"
    code=$?
    duration=$(( $(date +%s) - start ))

    if [ "$code" -eq 124 ] || [ "$code" -eq 137 ]; then
        result="timeout"
    elif [ "$code" -ne 0 ]; then
        result="killed"
    else
        result="survivor"
    fi

    printf '| %s | %s | `%s` | %s |\n' "$mutation" "$result" "$test_name" "$duration" >> "$REPORT"
    if [ "$result" = "survivor" ] && [ -n "${MUTATION_DEBUG_LOG_DIR:-}" ]; then
        cp "$log" "$MUTATION_DEBUG_LOG_DIR/$mutation.log"
    fi
    cp "$COPY_DIR/.mutation-backup/$mutation.sol" "$COPY_DIR/$relative_file"
    echo "$mutation $result ${duration}s"
done

cp "$REPORT" "$SOURCE_DIR/evidence/mutation.md"
