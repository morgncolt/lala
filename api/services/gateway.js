const { Gateway, Wallets } = require('fabric-network');
const fs = require('fs');
const { walletPath, connectionProfile, channelName, chaincodeName } = require('../config/fabric');

async function withContract(label, fn) {
  const ccp = JSON.parse(fs.readFileSync(connectionProfile, 'utf8'));
  const wallet = await Wallets.newFileSystemWallet(walletPath);
  const identity = await wallet.get(label);
  if (!identity) throw new Error(`Identity not found in wallet: ${label}`);

  const gateway = new Gateway();
  try {
    await gateway.connect(ccp, { wallet, identity: label, discovery: { enabled: true, asLocalhost: true } });
    const network = await gateway.getNetwork(channelName);
    const contract = network.getContract(chaincodeName);
    return await fn(contract);
  } finally {
    gateway.disconnect();
  }
}

module.exports = { withContract };