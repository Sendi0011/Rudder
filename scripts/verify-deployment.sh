#!/usr/bin/env bash
set -euo pipefail

PHASE="full"
if [[ $# -gt 0 ]]; then
  case "$1" in
    --phase)
      PHASE="${2:-}"
      shift 2
      ;;
    --phase=*)
      PHASE="${1#--phase=}"
      shift
      ;;
    *)
      printf 'usage: %s [--phase deploy|full]\n' "$0" >&2
      exit 2
      ;;
  esac
fi
if [[ "$PHASE" != "deploy" && "$PHASE" != "full" ]]; then
  printf 'invalid phase %s: use deploy or full\n' "$PHASE" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACT="${DEPLOYMENTS_FILE:-$ROOT/contracts/deployments.json}"
README="$ROOT/README.md"

python3 - "$ARTIFACT" "$README" "$ROOT" "$PHASE" <<'PY'
import json
import os
import subprocess
import sys
from pathlib import Path

artifact = Path(sys.argv[1])
readme = Path(sys.argv[2])
root = Path(sys.argv[3])
phase = sys.argv[4]
results = []
success_line = None
if phase == "deploy":
    success_line = "DEPLOY_OK: artifact, code and bindings"

keys = {
    "RudderHook": "rudderHook",
    "StrategyRegistry": "strategyRegistry",
    "RudderVault implementation": "vaultImplementation",
    "VaultFactory": "vaultFactory",
    "PoolManager": "poolManager",
}

artifact_contracts = {
    "RudderHook": "RudderHook",
    "StrategyRegistry": "StrategyRegistry",
    "RudderVault implementation": "RudderVault",
    "VaultFactory": "VaultFactory",
}


def cell(value):
    return str(value).replace("|", "/").replace("\n", " ").strip()


def add(name, ok, detail=""):
    results.append((name, bool(ok), cell(detail)))


def emit():
    print("| Check | Result | Detail |")
    print("| --- | --- | --- |")
    for name, ok, detail in results:
        print(f"| {cell(name)} | {'PASS' if ok else 'FAIL'} | {detail} |")
    ok = all(item[1] for item in results)
    if ok:
        print(success_line or f"DEPLOYMENTS_OK: {len(keys)} addresses")
    raise SystemExit(0 if ok else 1)


def run(cmd):
    try:
        result = subprocess.run(cmd, check=False, capture_output=True, text=True)
        return result.returncode == 0, result.stdout.strip(), result.stderr.strip()
    except OSError as exc:
        return False, "", str(exc)


def norm(value):
    try:
        return f"{int(str(value).strip(), 16):040x}"
    except (TypeError, ValueError):
        return None


def same_addr(left, right):
    a, b = norm(left), norm(right)
    return a is not None and b is not None and a == b


def call(address, signature, *args):
    cmd = ["cast", "call", address, signature, *args, "--rpc-url", rpc]
    ok, out, err = run(cmd)
    return ok, out, err


def fetch_code(address):
    return run(["cast", "code", address, "--rpc-url", rpc])


def masked_hash(contract, deployed_hex):
    path = root / "contracts" / "out" / f"{contract}.sol" / f"{contract}.json"
    if not path.is_file():
        return False, f"missing artifact {path.relative_to(root)}"
    try:
        build = json.loads(path.read_text(encoding="utf-8"))["deployedBytecode"]
    except (KeyError, OSError, ValueError) as exc:
        return False, str(exc)
    try:
        expected = bytearray(bytes.fromhex(build["object"][2:]))
        actual = bytearray(bytes.fromhex(deployed_hex[2:]))
    except ValueError as exc:
        return False, str(exc)
    if len(expected) != len(actual):
        return False, f"runtime length {len(actual)} != artifact length {len(expected)}"
    spans = []
    for refs in build.get("immutableReferences", {}).values():
        for ref in refs:
            spans.append((int(ref["start"]), int(ref["length"])))
    for start, length in spans:
        for index in range(start, min(start + length, len(expected))):
            expected[index] = 0
            actual[index] = 0
    ok1, left, err1 = run(["cast", "keccak", "0x" + expected.hex()])
    ok2, right, err2 = run(["cast", "keccak", "0x" + actual.hex()])
    if not (ok1 and ok2):
        return False, (err1 or err2 or "cast keccak failed")
    if left.lower() != right.lower():
        return False, f"runtime hash {right} != artifact hash {left}"
    return True, f"{len(spans)} immutable spans zeroed"


def as_bool(value):
    text = value.strip().lower()
    if text in ("true", "1", "0x1", "0x01"):
        return True
    if text in ("false", "0", "0x0", "0x00"):
        return False
    if text.startswith("0x"):
        try:
            return int(text, 16) == 1
        except ValueError:
            return False
    return False


try:
    data = json.loads(artifact.read_text(encoding="utf-8"))
except (OSError, ValueError) as exc:
    add("deployment artifact", False, str(exc))
    emit()

table = {}
lines = readme.read_text(encoding="utf-8").splitlines()
start = next((i for i, line in enumerate(lines) if line.strip() == "## Deployed addresses"), None)
if start is not None:
    for line in lines[start + 1 :]:
        if line.startswith("## "):
            break
        parts = [part.strip() for part in line.strip().strip("|").split("|")]
        if len(parts) == 2 and parts[0] in keys and parts[1]:
            table[parts[0]] = parts[1]

if not any(data.get(key) for key in keys.values()):
    add("deployment artifact", not table, "DEPLOYMENTS_NONE" if not table else "README lists addresses")
    success_line = "DEPLOYMENTS_NONE"
    emit()

for name, key in keys.items():
    if not data.get(key):
        add(f"artifact address: {name}", False, "missing")
emit_if_missing = any(not item[1] for item in results)
if emit_if_missing:
    emit()

if phase == "full":
    for name, key in keys.items():
        listed = table.get(name, "")
        add(f"README address: {name}", same_addr(listed, data[key]), listed or "missing")

rpc = os.environ.get("UNICHAIN_SEPOLIA_RPC_URL", "")
if not rpc:
    add("rpc endpoint", False, "UNICHAIN_SEPOLIA_RPC_URL is required")
    emit()

codes = {}
for name, key in keys.items():
    ok, value, err = fetch_code(data[key])
    codes[name] = value if ok and value not in ("", "0x") else ""
    add(f"runtime code: {name}", bool(codes[name]), err or f"{len(codes[name][2:]) // 2} bytes")

for name, contract in artifact_contracts.items():
    if not codes.get(name):
        add(f"code hash: {name}", False, "no runtime code")
        continue
    ok, detail = masked_hash(contract, codes[name])
    add(f"code hash: {name}", ok, detail)

hook = data["rudderHook"]
factory = data["vaultFactory"]
registry = data["strategyRegistry"]

expected_owner = os.environ.get("OWNER", "")
if not expected_owner:
    add("hook owner", False, "OWNER is required")
else:
    ok, value, err = call(hook, "owner()(address)")
    add("hook owner", ok and same_addr(value, expected_owner), err or value)

for label, address, signature, expected in (
    ("factory hook", factory, "hook()(address)", hook),
    ("hook factory", hook, "vaultFactory()(address)", factory),
    ("hook pool manager", hook, "poolManager()(address)", data["poolManager"]),
    ("registry factory", registry, "factory()(address)", factory),
):
    ok, value, err = call(address, signature)
    add(label, ok and same_addr(value, expected), err or value)

if phase == "full":
    seed_path = root / "contracts" / "seed.json"
    if not seed_path.is_file():
        add("oracle ready after activity", False, f"missing {seed_path.relative_to(root)}")
    else:
        try:
            seed = json.loads(seed_path.read_text(encoding="utf-8"))
            key_tuple = (
                f"({seed['token0']},{seed['token1']},{seed['fee']},"
                f"{seed['tickSpacing']},{hook})"
            )
            signature = "isOracleReady((address,address,uint24,int24,address)) returns (bool)"
            ok, value, err = call(hook, signature, key_tuple)
            add("oracle ready after activity", ok and as_bool(value), err or value or "false")
        except (KeyError, OSError, ValueError) as exc:
            add("oracle ready after activity", False, str(exc))

emit()
PY
