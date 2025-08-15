const FabricCAServices = require('fabric-ca-client');
const { Wallets } = require('fabric-network');
const fs = require('fs'); const path = require('path');

const ccpPath   = process.env.CCP_PATH   || path.join(process.env.HOME, 'landledger/api/connection/connection-org1.json');
const walletDir = process.env.WALLET_PATH || path.join(process.env.HOME, 'landledger/api/wallet');
const mspId     = process.env.MSP_ID || 'Org1MSP';

(async () => {
  const ccp = JSON.parse(fs.readFileSync(ccpPath));
  const caInfo = ccp.certificateAuthorities['ca.org1.example.com'];
  const ca = new FabricCAServices(caInfo.url, { trustedRoots: caInfo.tlsCACerts.pem, verify: false });

  const wallet = await Wallets.newFileSystemWallet(walletDir);
  if (await wallet.get('admin')) { console.log('Admin already enrolled'); return; }

  const enrollment = await ca.enroll({ enrollmentID: 'admin', enrollmentSecret: 'adminpw' });
  await wallet.put('admin', {
    credentials: { certificate: enrollment.certificate, privateKey: enrollment.key.toBytes() },
    mspId, type: 'X.509'
  });
  console.log('✅ Admin enrolled');
})();
