const { Wallets, X509Identity } = require('fabric-network');
const fs = require('fs');
const path = require('path');

(async () => {
  try {
    const MSPID = 'Org1MSP';
    const label = process.env.LABEL || 'appUser';
    const walletPath = process.env.WALLET_PATH ||
      path.join(process.env.HOME || process.env.USERPROFILE,
        'blockchain', 'fabric-samples',
        'asset-transfer-basic', 'application-javascript', 'wallet');

    const mspBase = process.env.MSP_BASE ||
      path.join(process.env.HOME || process.env.USERPROFILE,
        'blockchain', 'fabric-samples', 'test-network',
        'organizations', 'peerOrganizations', 'org1.example.com',
        'users', 'User1@org1.example.com', 'msp');

    const certPath = path.join(mspBase, 'signcerts');
    const keyPath  = path.join(mspBase, 'keystore');
    const certFile = fs.readdirSync(certPath).find(f => f.endsWith('.pem'));
    const keyFile  = fs.readdirSync(keyPath).find(f => f.endsWith('_sk') || f.endsWith('.pem'));

    if (!certFile || !keyFile) {
      throw new Error(`Could not find cert/key in ${certPath} or ${keyPath}`);
    }
    const certificate = fs.readFileSync(path.join(certPath, certFile), 'utf8');
    const privateKey  = fs.readFileSync(path.join(keyPath,  keyFile),  'utf8');

    const wallet = await Wallets.newFileSystemWallet(walletPath);
    const identity = { credentials: { certificate, privateKey }, mspId: MSPID, type: 'X.509' };
    await wallet.put(label, identity);

    console.log(`✅ Imported ${label} into wallet: ${walletPath}`);
  } catch (e) {
    console.error('❌ Import failed:', e.message || e);
    process.exit(1);
  }
})();
