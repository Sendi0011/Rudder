#!/usr/bin/env bash
set -euo pipefail

: "${UNICHAIN_SEPOLIA_RPC_URL:?set UNICHAIN_SEPOLIA_RPC_URL before running activity}"

SLEEP_SECONDS="${SLEEP_SECONDS:-60}"

while true; do
  forge script contracts/script/Activity.s.sol:Activity \
    --rpc-url "$UNICHAIN_SEPOLIA_RPC_URL" \
    --broadcast \
    -vv
  sleep "$SLEEP_SECONDS"
done
