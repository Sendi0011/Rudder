#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
README="$ROOT/README.md"

if ! grep -q '^## Numbers$' "$README"; then
    echo "Numbers section not found; skipping."
    exit 0
fi

python3 - "$README" "$ROOT" <<'PY'
import json
import re
import sys
from pathlib import Path

readme = Path(sys.argv[1])
root = Path(sys.argv[2])

fields = {
    "oracle_gas.json": [
        ["oracle_gas.json:earlyGas"],
        ["oracle_gas.json:lateGas"],
        ["oracle_gas.json:capacity"],
        ["oracle_gas.json:twapWindow"],
        ["oracle_gas.json:maxObservationAge"],
    ],
    "twap_accuracy.json": [
        ["twap_accuracy.json:startTick"],
        ["twap_accuracy.json:pushedTick"],
        ["oracle_gas.json:twapWindow"],
        ["twap_accuracy.json:twapTick"],
        ["twap_accuracy.json:observations"],
        ["twap_accuracy.json:tickError"],
        ["twap_accuracy.json:sqrtDeviationBps"],
    ],
    "rebalance_bounds.json": [
        ["rebalance_bounds.json:width"],
        ["rebalance_bounds.json:centerShift"],
        ["rebalance_bounds.json:elapsed"],
        ["rebalance_bounds.json:navChangeBps"],
    ],
    "deposit_guard.json": [
        ["deposit_guard.json:deviationBps"],
        ["deposit_guard.json:capBps"],
        ["deposit_guard.json:protocolCapBps"],
    ],
    "flow_invariance.json": [
        ["flow_invariance.json:bigAlphaDelta"],
        ["flow_invariance.json:relativeDifferenceBps"],
        ["flow_invariance.json:depositAlphaDelta", "flow_invariance.json:withdrawAlphaDelta"],
    ],
    "rebalance_alpha_cost.json": [
        ["rebalance_alpha_cost.json:navLossBps"],
        ["rebalance_alpha_cost.json:alphaCostBps"],
    ],
    "churner_alpha.json": [
        ["churner_alpha.json:rebalanceCount"],
        ["churner_alpha.json:rankingGapBps"],
        ["churner_alpha.json:summedCostBps"],
    ],
    "worst_case_loss.json": [
        ["worst_case_loss.json:lossCapBps"],
        ["worst_case_loss.json:elapsedSeconds"],
        ["worst_case_loss.json:intervalSeconds"],
        ["worst_case_loss.json:boundBps"],
        ["worst_case_loss.json:boundRebalances"],
        ["worst_case_loss.json:observedLossBps"],
        ["worst_case_loss.json:chargedRebalances"],
    ],
    "placebo_curators.json": [
        ["placebo_curators.json:k"],
        ["placebo_curators.json:regimes"],
        ["placebo_curators.json:envelopes"],
        ["placebo_curators.json:reactiveMeanBps"],
        ["placebo_curators.json:placeboMeanBps"],
        ["placebo_curators.json:placeboStdBps"],
        ["placebo_curators.json:worstRebalanceLossBps"],
        ["placebo_curators.json:lossBoundBps"],
        ["placebo_curators.json:maxDrawdownVsHoldBps"],
    ],
}

lines = readme.read_text(encoding="utf-8").splitlines()
start = next(index for index, line in enumerate(lines) if line.strip() == "## Numbers")
end = next((index for index in range(start + 1, len(lines)) if lines[index].startswith("## ")), len(lines))

bullets = []
current = []
for line in lines[start + 1 : end]:
    if line.startswith("- "):
        if current:
            bullets.append(" ".join(current))
        current = [line[2:]]
    elif current and line.strip():
        current.append(line.strip())
    elif current:
        bullets.append(" ".join(current))
        current = []
if current:
    bullets.append(" ".join(current))

cache = {}


def expected(spec):
    filename, field = spec.split(":", 1)
    if filename not in cache:
        path = root / "evidence" / filename
        if not path.exists():
            raise SystemExit(f"missing evidence file: evidence/{filename}")
        cache[filename] = json.loads(path.read_text(encoding="utf-8"))
    if field not in cache[filename]:
        raise SystemExit(f"missing field: evidence/{filename}:{field}")
    return cache[filename][field]


failures = []
checked = 0
for bullet in bullets:
    link = re.search(r"\]\((evidence/[A-Za-z0-9_./-]+\.json)\)", bullet)
    if not link:
        failures.append(f"no evidence link in bullet: {bullet[:80]}")
        continue
    artifact = Path(link.group(1)).name
    if artifact not in fields:
        failures.append(f"no field map for evidence/{artifact}")
        continue
    text = re.sub(r"<!--.*?-->", "", bullet)
    text = re.sub(r"\[[^\]]*\]\([^)]*\)", "", text)
    text = text.replace("`", "").replace("**", "")
    numbers = [int(token.replace(",", "")) for token in re.findall(r"(?<![\w])-?\d[\d,]*(?![\w])", text)]
    specs = fields[artifact]
    if len(numbers) != len(specs):
        failures.append(
            f"evidence/{artifact}: found {len(numbers)} figures but expected {len(specs)}: {numbers}"
        )
        continue
    for number, group in zip(numbers, specs):
        for spec in group:
            checked += 1
            actual = expected(spec)
            if actual != number:
                failures.append(f"evidence/{spec}: README has {number}, artifact has {actual}")

if failures:
    print("README number check failed:")
    for failure in failures:
        print(f"- {failure}")
    raise SystemExit(1)

print(f"README number check: {checked} field comparisons across {len(bullets)} bullets.")
PY
