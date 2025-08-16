#!/usr/bin/env bash
set -Eeuo pipefail

echo "==> Safe shutdown (preserve ledger data)"

has_cmd() { command -v "$1" >/dev/null 2>&1; }

# 1) Stop API (PM2) if present
if has_cmd pm2; then
  if pm2 jlist | grep -q '"name":"landledger-api"'; then
    echo "-> Stopping PM2 service: landledger-api"
    pm2 stop landledger-api || true
  else
    echo "-> PM2 found, but landledger-api is not running."
  fi
else
  echo "-> PM2 not found; skipping API stop."
fi

# 2) Stop Fabric containers (keep volumes)
echo "-> Stopping Fabric containers (orderer/peer/couchdb/ca/ccaas/chaincode/cli)"
mapfile -t FABRIC_IDS < <(docker ps --format '{{.ID}} {{.Names}}' \
  | egrep 'orderer|peer|couchdb|ca|ccaas|chaincode|cli' \
  | awk '{print $1}' || true)

if (( ${#FABRIC_IDS[@]} )); then
  docker stop "${FABRIC_IDS[@]}"
else
  echo "-> No running Fabric containers matched."
fi

echo "✅ Done. Ledger volumes were NOT removed."

