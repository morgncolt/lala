#!/usr/bin/env bash
# start_landledger_api.sh — boot the Node API (PM2 if available)
set -Eeuo pipefail

API_DIR="${API_DIR:-$HOME/landledger/api}"
PM2_APP="${PM2_APP:-landledger-api}"

cd "$API_DIR"

# Env passed from safe_api_start.sh or defaulted here
export CCP_PATH="${CCP_PATH:-$API_DIR/connection/connection-org1.json}"
export WALLET_DIR="${WALLET_DIR:-$API_DIR/wallet}"
export CHANNEL="${CHANNEL:-mychannel}"
export CC_NAME="${CC_NAME:-landledger}"
export IDENTITY="${IDENTITY:-appUser}"
export DISCOVERY_AS_LOCALHOST="${DISCOVERY_AS_LOCALHOST:-true}"
export REUSE_GATEWAY="${REUSE_GATEWAY:-false}"
export PORT="${PORT:-4000}"
export NODE_ENV="${NODE_ENV:-production}"
# export DEBUG="${DEBUG:-fabric-network:*}"  # uncomment for verbose SDK logs

# Sanity checks
[[ -f "$CCP_PATH" ]]   || { echo "!! Missing connection profile: $CCP_PATH"; exit 1; }
[[ -d "$WALLET_DIR" ]] || { echo "!! Missing wallet dir: $WALLET_DIR"; exit 1; }
[[ -f "server.js" ]]   || { echo "!! server.js not found in $API_DIR"; exit 1; }

# Install deps if needed
if [[ ! -d node_modules ]]; then
  echo "-> Installing dependencies..."
  if command -v npm >/dev/null 2>&1; then
    npm ci --omit=dev || npm install --omit=dev
  else
    echo "!! npm not found; cannot install deps"; exit 1
  fi
fi

# Start the app
if command -v pm2 >/dev/null 2>&1; then
  if pm2 describe "$PM2_APP" >/dev/null 2>&1; then
    echo "-> Restarting PM2 app: $PM2_APP"
    pm2 restart "$PM2_APP" --update-env
  else
    echo "-> Starting PM2 app: $PM2_APP"
    pm2 start server.js --name "$PM2_APP" --update-env
  fi
  pm2 save || true
else
  echo "-> PM2 not found; running in foreground with node"
  exec node server.js
fi
