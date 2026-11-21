#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLAIMS="$ROOT/docs/CLAIMS.md"
README="$ROOT/README.md"
PRIOR_ART="$ROOT/docs/prior-art.md"

for required in "$CLAIMS" "$README" "$PRIOR_ART"; do
    if [ ! -f "$required" ]; then
        echo "missing ${required#$ROOT/}" >&2
        exit 1
    fi
done

python3 - "$CLAIMS" "$README" "$PRIOR_ART" "$ROOT" <<'PY'
import re
import sys
from pathlib import Path

claims = Path(sys.argv[1])
readme = Path(sys.argv[2])
prior_art = Path(sys.argv[3])
root = Path(sys.argv[4])
lines = claims.read_text(encoding="utf-8").splitlines()
try:
    start = lines.index("## Claims")
except ValueError:
    raise SystemExit("Claims section not found")
end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")), len(lines))

header = [cell.strip() for cell in lines[start + 1].strip().strip("|").split("|")] if start + 1 < end else []
expected_header = ["Claim", "Contract line", "Test name", "Evidence file", "Reproduce", "Limit"]
if header != expected_header:
    raise SystemExit(f"claim header must be: {' | '.join(expected_header)}")

rows = []
for line in lines[start + 2 : end]:
    if not line.startswith("| ") or line.startswith("| ---"):
        continue
    cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
    if len(cells) != 6:
        raise SystemExit(f"claim row must have six cells: {line}")
    rows.append(cells)

if not rows:
    raise SystemExit("no claim rows found")

marker_pattern = re.compile(r"<!--\s*claim:([A-Za-z0-9_.-]+)\s*-->")
row_marker = re.compile(r"(?:^|\s)claim:([A-Za-z0-9_.-]+)(?:\s|$)")
source_markers = {}
for path in (readme, prior_art):
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        for match in marker_pattern.finditer(line):
            marker = match.group(1)
            if marker in source_markers:
                raise SystemExit(f"duplicate marker: {marker}")
            source_markers[marker] = (path.name, number)

test_files = sorted((root / "contracts" / "test").glob("*.sol"))
test_definitions = set()
for path in test_files:
    for line in path.read_text(encoding="utf-8").splitlines():
        found = re.search(r"\bfunction\s+(test[A-Za-z0-9_]*|invariant[A-Za-z0-9_]*)\s*\(", line)
        if found:
            test_definitions.add(found.group(1))

failures = []
seen = set()
for claim, code, test, evidence, reproduce, limit in rows:
    matches = row_marker.findall(claim)
    if len(matches) != 1:
        failures.append(f"claim must carry one marker: {claim}")
        continue
    marker = matches[0]
    if marker in seen:
        failures.append(f"duplicate claim row: {marker}")
    seen.add(marker)
    if marker not in source_markers:
        failures.append(f"orphan claim row: {marker}")
    if not claim.replace(f"claim:{marker}", "").strip(" :|"):
        failures.append(f"claim has no text: {marker}")

    if code and code.lower() != "none":
        reference = re.search(r"([A-Za-z0-9_./-]+\.(?:sol|md)):(\d+)(?:-(\d+))?", code)
        if not reference:
            failures.append(f"bad contract line: {marker}")
        else:
            path = root / reference.group(1)
            if not path.is_file():
                failures.append(f"missing file: {reference.group(1)}")
            else:
                count = len(path.read_text(encoding="utf-8").splitlines())
                first = int(reference.group(2))
                last = int(reference.group(3) or first)
                if first < 1 or last < first or last > count:
                    failures.append(f"line reference no longer exists: {code}")

    if test and test.lower() != "none":
        if test not in test_definitions:
            failures.append(f"missing test function: {test}")

    paths = [item for group in re.findall(r"`([^`]+)`|\[[^\]]*\]\(([^)]+)\)", evidence) for item in group if item]
    if len(paths) != 1:
        failures.append(f"claim must name one evidence file: {marker}")
    elif not (root / paths[0]).is_file():
        failures.append(f"missing evidence file: {paths[0]}")

    commands = re.findall(r"`([^`]+)`", reproduce)
    if len(commands) != 1 or not commands[0].strip():
        failures.append(f"claim must name one command: {marker}")

    if not limit or limit.lower() == "limit":
        failures.append(f"claim must state a limit: {marker}")

for marker, (name, number) in source_markers.items():
    if marker not in seen:
        failures.append(f"README/prior-art claim with no row: {marker} ({name}:{number})")

if failures:
    for failure in failures:
        print(f"FAIL: {failure}", file=sys.stderr)
    raise SystemExit(1)

print(f"CLAIMS_OK: {len(rows)} claims checked, {len(source_markers)} markers covered")
PY
