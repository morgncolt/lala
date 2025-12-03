const path = require('path');

module.exports = {
  // --- CA connectivity ---
  caURL: process.env.FABRIC_CA_URL || 'https://localhost:7054',
  caName: process.env.FABRIC_CA_NAME || 'ca-org1',          // <-- IMPORTANT
  tlsCACertsPath: process.env.FABRIC_CA_TLSCERT
    || path.join(process.env.HOME || '', 'fabric-samples', 'test-network',
                 'organizations', 'fabric-ca', 'org1', 'tls-cert.pem'),

  // --- MSP / Wallet / Network ---
  mspId: process.env.FABRIC_MSP_ID || 'Org1MSP',
  walletPath: process.env.FABRIC_WALLET_PATH
    || path.join(__dirname, '..', 'wallet'),
  connectionProfile: process.env.FABRIC_CCP
    || path.join(__dirname, '..', 'connection', 'connection-org1.json'),
  channelName: process.env.FABRIC_CHANNEL || 'mychannel',
  chaincodeName: process.env.FABRIC_CC || 'landledger',

  // --- Admin identity in wallet ---
  adminLabel: process.env.FABRIC_ADMIN_LABEL || 'admin',
  adminEnrollId: process.env.FABRIC_ADMIN_ID || 'admin',
  adminEnrollSecret: process.env.FABRIC_ADMIN_SECRET || 'adminpw',

  // --- Affiliation (must exist on your CA) ---
  defaultAffiliation: process.env.FABRIC_AFFILIATION || 'org1.department1', // <-- IMPORTANT

  // --- Gateway discovery options (single source of truth) ---
  discovery: {
    enabled: true,
    asLocalhost: process.env.FABRIC_DISCOVERY_LOCALHOST !== 'false', // default true
  },
};
