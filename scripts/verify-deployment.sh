#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACT="${DEPLOYMENTS_FILE:-$ROOT/contracts/deployments.json}"
README="$ROOT/README.md"

python3 - "$ARTIFACT" "$README" <<'PY'
import json
import os
import subprocess
import sys
from pathlib import Path

artifact = Path(sys.argv[1])
readme = Path(sys.argv[2])
data = json.loads(artifact.read_text(encoding="utf-8"))

keys = {
    "RudderHook": "rudderHook",
    "StrategyRegistry": "strategyRegistry",
    "RudderVault implementation": "vaultImplementation",
    "VaultFactory": "vaultFactory",
    "PoolManager": "poolManager",
}

table = {}
lines = readme.read_text(encoding="utf-8").splitlines()
start = next((i for i, line in enumerate(lines) if line.strip() == "## Deployed addresses"), None)
if start is not None:
    for line in lines[start + 1 :]:
        if line.startswith("## ") and line.strip() != "## Deployed addresses":
            break
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) == 2 and cells[0] in keys and cells[1]:
            table[cells[0]] = cells[1]


def norm(value):
    return f"{int(str(value).strip(), 16):040x}"


if not any(data.get(key) for key in keys.values()):
    if table:
        raise SystemExit("README lists addresses but the deployment artifact is empty")
    print("DEPLOYMENTS_NONE")
    raise SystemExit(0)

missing = [name for name, key in keys.items() if not data.get(key)]
if missing:
    raise SystemExit(f"missing artifact address: {', '.join(missing)}")

for name, key in keys.items():
    if name not in table:
        raise SystemExit(f"README has no address for {name}")
    if norm(table[name]) != norm(data[key]):
        raise SystemExit(f"README address differs from artifact for {name}")

rpc = os.environ.get("UNICHAIN_SEPOLIA_RPC_URL", "")
if not rpc:
    raise SystemExit("UNICHAIN_SEPOLIA_RPC_URL is required when addresses are recorded")


def call(address, signature):
    result = subprocess.run(
        ["cast", "call", address, signature, "--rpc-url", rpc],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def code(address):
    result = subprocess.run(
        ["cast", "code", address, "--rpc-url", rpc],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


for name, key in keys.items():
    address = data[key]
    if code(address) in ("", "0x"):
        raise SystemExit(f"no contract code at {name}")

hook = data["rudderHook"]
registry = data["strategyRegistry"]
if norm(call(hook, "owner()(address)")) == norm("0x0000000000000000000000000000000000000000"):
    raise SystemExit("hook owner is unset")
if norm(call(hook, "vaultFactory()(address)")) != norm(data["vaultFactory"]):
    raise SystemExit("hook factory does not match the artifact")
if norm(call(hook, "poolManager()(address)")) != norm(data["poolManager"]):
    raise SystemExit("hook pool manager does not match the artifact")
if norm(call(registry, "factory()(address)")) != norm(data["vaultFactory"]):
    raise SystemExit("registry factory does not match the artifact")

print(f"DEPLOYMENTS_OK: {len(keys)} addresses")
PY
