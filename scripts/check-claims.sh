#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLAIMS="$ROOT/docs/CLAIMS.md"

if [ ! -f "$CLAIMS" ]; then
    echo "missing docs/CLAIMS.md" >&2
    exit 1
fi

python3 - "$CLAIMS" "$ROOT" <<'PY'
import re
import sys
from pathlib import Path

claims = Path(sys.argv[1])
root = Path(sys.argv[2])
lines = claims.read_text(encoding="utf-8").splitlines()
try:
    start = lines.index("## Claims")
except ValueError:
    raise SystemExit("Claims section not found")
end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")), len(lines))

rows = []
for line in lines[start + 1 : end]:
    if not line.startswith("| ") or line.startswith("| ---"):
        continue
    cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
    if len(cells) != 4:
        raise SystemExit(f"claim row must have four cells: {line}")
    rows.append(cells)

if not rows:
    raise SystemExit("no claim rows found")

seen = set()
failures = []
for claim, evidence, reproduce, limit in rows:
    if not claim or claim.lower() == "claim":
        continue
    if claim in seen:
        failures.append(f"duplicate claim: {claim}")
    seen.add(claim)

    links = re.findall(r"\[[^\]]+\]\(([^)]+)\)", evidence)
    if len(links) != 1:
        failures.append(f"claim must link one artifact: {claim}")
        continue
    target = claims.parent / links[0]
    if not target.is_file():
        failures.append(f"missing artifact: {links[0]}")

    commands = re.findall(r"`([^`]+)`", reproduce)
    if len(commands) != 1 or not commands[0].strip():
        failures.append(f"claim must name one command: {claim}")

    if not limit or limit.lower() == "limit":
        failures.append(f"claim must state a limit: {claim}")

count = len(seen)
if failures:
    for failure in failures:
        print(f"FAIL: {failure}", file=sys.stderr)
    raise SystemExit(1)

print(f"CLAIMS_OK: {count} claims checked")
PY
