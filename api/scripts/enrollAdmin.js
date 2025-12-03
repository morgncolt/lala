const FabricCAServices = require('fabric-ca-client');
const { Wallets } = require('fabric-network');
const fs = require('fs');
const { caURL, mspId, walletPath, adminLabel, adminEnrollId, adminEnrollSecret } = require('../config/fabric');

(async () => {
  const ca = new FabricCAServices(caURL, { verify: false });
  const wallet = await Wallets.newFileSystemWallet(walletPath);

  const exists = await wallet.get(adminLabel);
  if (exists) { console.log('Admin already in wallet'); return; }

  const enrollment = await ca.enroll({ enrollmentID: adminEnrollId, enrollmentSecret: adminEnrollSecret });
  const x509Identity = {
    credentials: { certificate: enrollment.certificate, privateKey: enrollment.key.toBytes() },
    mspId, type: 'X.509',
  };
  await wallet.put(adminLabel, x509Identity);
  console.log('Enrolled admin and imported to wallet');
})().catch(e => { console.error(e); process.exit(1); });
