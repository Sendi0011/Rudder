#!/usr/bin/env bash
set -euo pipefail

: "${UNICHAIN_SEPOLIA_RPC_URL:?set UNICHAIN_SEPOLIA_RPC_URL before running activity}"

SLEEP_SECONDS="${SLEEP_SECONDS:-60}"
ACTIVITY_RUN="${ACTIVITY_RUN:-0}"

if [[ -n "${DEPLOYER_ACCOUNT:-}" ]]; then
  SIGNER_FLAGS=(--account "$DEPLOYER_ACCOUNT" --sender "$DEPLOYER_ADDRESS")
else
  SIGNER_FLAGS=(--private-key "$PRIVATE_KEY" --sender "$DEPLOYER_ADDRESS")
fi

while true; do
  export ACTIVITY_RUN
  forge script contracts/script/Activity.s.sol:Activity \
    --rpc-url "$UNICHAIN_SEPOLIA_RPC_URL" \
    "${SIGNER_FLAGS[@]}" \
    --broadcast \
    --slow \
    -vv
  ACTIVITY_RUN=$((ACTIVITY_RUN + 1))
  sleep "$SLEEP_SECONDS"
done
