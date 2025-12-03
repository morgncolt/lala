// lib/fabricGateway.js
const { Gateway, Wallets } = require('fabric-network');
const fs = require('fs');

async function withGateway(uid, fn) {
  const ccp = JSON.parse(fs.readFileSync(process.env.CONNECTION_PROFILE));
  const wallet = await Wallets.newFileSystemWallet(process.env.WALLET_PATH);

  const gateway = new Gateway();
  await gateway.connect(ccp, {
    wallet,
    identity: uid,         // <-- use Firebase UID-bound identity
    discovery: { enabled: true, asLocalhost: true },
  });

  try {
    const network = await gateway.getNetwork('mychannel');
    const contract = network.getContract('landledger'); // your chaincode name
    return await fn(contract);
  } finally {
    gateway.disconnect();
  }
}
module.exports = { withGateway };
