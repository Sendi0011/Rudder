#!/usr/bin/env bash
set -euo pipefail

: "${UNICHAIN_SEPOLIA_RPC_URL:?set UNICHAIN_SEPOLIA_RPC_URL before running activity}"

SLEEP_SECONDS="${SLEEP_SECONDS:-60}"
ACTIVITY_RUN="${ACTIVITY_RUN:-0}"

while true; do
  export ACTIVITY_RUN
  forge script contracts/script/Activity.s.sol:Activity \
    --rpc-url "$UNICHAIN_SEPOLIA_RPC_URL" \
    --broadcast \
    -vv
  ACTIVITY_RUN=$((ACTIVITY_RUN + 1))
  sleep "$SLEEP_SECONDS"
done
