#!/bin/bash
set -euo pipefail

API_DIR="$HOME/landledger/api"
APP_NAME="landledger-api"

CHANNEL_NAME="${CHANNEL_NAME:-mychannel}"
CHAINCODE_NAME="${CHAINCODE_NAME:-landledger}"
CHAINCODE_LANG="${CHAINCODE_LANG:-go}"
CHAINCODE_PATH="${CHAINCODE_PATH:-$HOME/landledger/chaincode}"

# Behavior flags (export in your shell if you want them true)
DEPLOY_CC_IF_MISSING="${DEPLOY_CC_IF_MISSING:-false}"
COPY_CCP_ON_START="${COPY_CCP_ON_START:-true}"

# Locate fabric-samples
FAB_SAMPLES=""
for p in "$HOME/fabric-samples" "$HOME/blockchain/fabric-samples"; do
  [[ -d "$p" ]] && { FAB_SAMPLES="$p"; break; }
done
[[ -z "$FAB_SAMPLES" ]] && { echo "❌ fabric-samples not found"; exit 1; }

# CCP
mkdir -p "$API_DIR/connection"
SRC_CCP="$FAB_SAMPLES/test-network/organizations/peerOrganizations/org1.example.com/connection-org1.json"
DST_CCP="$API_DIR/connection/connection-org1.json"
if [[ "$COPY_CCP_ON_START" == "true" && -f "$SRC_CCP" ]]; then
  cp -f "$SRC_CCP" "$DST_CCP"
fi
[[ ! -f "$DST_CCP" ]] && { echo "❌ Missing CCP at $DST_CCP"; exit 1; }

# Wallet + env for enrollment
mkdir -p "$API_DIR/wallet"
export CCP_PATH="$DST_CCP"
export WALLET_PATH="$API_DIR/wallet"
export MSP_ID="${MSP_ID:-Org1MSP}"
export USER_ID="${USER_ID:-appUser}"
export USER_SECRET="${USER_SECRET:-apppw}"

# Idempotent enrollment
node "$API_DIR/scripts/enrollAdmin.js"
node "$API_DIR/scripts/resetAndEnrollUser.js"

# Optional: auto-deploy CC if not committed
if [[ "$DEPLOY_CC_IF_MISSING" == "true" ]]; then
  if docker ps -a --format '{{.Names}}' | grep -q '^peer0\.org1\.example\.com$'; then
    if docker exec peer0.org1.example.com peer lifecycle chaincode querycommitted -C "$CHANNEL_NAME" 2>/dev/null | grep -q "Name: $CHAINCODE_NAME,"; then
      echo "🧱 Chaincode '$CHAINCODE_NAME' already committed on $CHANNEL_NAME"
    else
      echo "🧱 Deploying chaincode '$CHAINCODE_NAME' to $CHANNEL_NAME ..."
      pushd "$FAB_SAMPLES/test-network" >/dev/null
      ./network.sh deployCC -ccn "$CHAINCODE_NAME" -ccl "$CHAINCODE_LANG" -ccp "$CHAINCODE_PATH"
      popd >/dev/null
    fi
  else
    echo "ℹ️ peer0.org1.* not running yet; skipping CC deploy"
  fi
fi

# Avoid .env overriding runtime vars
rm -f "$API_DIR/.env" 2>/dev/null || true

# PM2 start/restart
cd "$API_DIR"
if pm2 describe "$APP_NAME" >/dev/null 2>&1; then
  pm2 restart ecosystem.config.js --only "$APP_NAME" --update-env
else
  pm2 start ecosystem.config.js --only "$APP_NAME" --update-env
fi
pm2 save >/dev/null
pm2 status "$APP_NAME"
pm2 logs "$APP_NAME" --lines 30 --nostream
