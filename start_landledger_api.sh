#!/bin/bash
set -euo pipefail

API_DIR="$HOME/landledger/api"
APP_NAME="landledger-api"

# Ensure ecosystem exists (create once)
if [[ ! -f "$API_DIR/ecosystem.config.js" ]]; then
  cat > "$API_DIR/ecosystem.config.js" <<'EOF'
const path = require('path');
const HOME = process.env.HOME || process.env.USERPROFILE || '';
module.exports = {
  apps: [{
    name: 'landledger-api',
    script: 'server.js',
    cwd: '/home/morgan/landledger/api',
    interpreter: 'node',
    watch: true,
    env: {
      PORT: 4000,
      CHANNEL: 'mychannel',
      CC_NAME: 'landledger',
      FABRIC_IDENTITY: 'appUser',
      CCP_PATH: `${HOME}/blockchain/fabric-samples/test-network/organizations/peerOrganizations/org1.example.com/connection-org1.json`,
      WALLET_PATH: `${HOME}/blockchain/fabric-samples/asset-transfer-basic/application-javascript/wallet`,
      REUSE_GATEWAY: 'true',
      NODE_ENV: 'development',
    },
    env_production: {
      NODE_ENV: 'production',
      PORT: 4000,
      CHANNEL: 'mychannel',
      CC_NAME: 'landledger',
      FABRIC_IDENTITY: 'appUser',
      CCP_PATH: `${HOME}/blockchain/fabric-samples/test-network/organizations/peerOrganizations/org1.example.com/connection-org1.json`,
      WALLET_PATH: `${HOME}/blockchain/fabric-samples/asset-transfer-basic/application-javascript/wallet`,
      REUSE_GATEWAY: 'true',
    },
  }],
};
EOF
fi

echo "🚀 Starting or restarting $APP_NAME via ecosystem..."
cd "$API_DIR"

if pm2 describe "$APP_NAME" >/dev/null 2>&1; then
  pm2 restart ecosystem.config.js --only "$APP_NAME" --env production
else
  pm2 start ecosystem.config.js --only "$APP_NAME" --env production
fi

pm2 save
pm2 startup | tail -n 5

echo "✅ $APP_NAME should be running. Status:"
pm2 status "$APP_NAME"

echo -e "\n📜 Last 20 lines of logs:"
pm2 logs "$APP_NAME" --lines 20 --nostream
