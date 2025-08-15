const HOME = "/home/morgan";
module.exports = {
  apps: [{
    name: 'landledger-api',
    script: 'server.js',
    cwd: '/home/morgan/landledger/api',
    interpreter: 'node',
    watch: true,
    env_production: {
      NODE_ENV: 'production',
      PORT: 4000,
      CHANNEL: 'mychannel',
      CC_NAME: 'landledger', // must match your deployed chaincode name
      FABRIC_IDENTITY: 'appUser',
      CCP_PATH: `${HOME}/blockchain/fabric-samples/test-network/organizations/peerOrganizations/org1.example.com/connection-org1.json`,
      WALLET_PATH: `${HOME}/blockchain/fabric-samples/asset-transfer-basic/application-javascript/wallet`,
      REUSE_GATEWAY: 'true',
    },
  }]
};
