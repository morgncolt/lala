const FabricCAServices = require('fabric-ca-client');
const { Wallets } = require('fabric-network');
const fs = require('fs'); const path = require('path');

const ccpPath   = process.env.CCP_PATH   || path.join(process.env.HOME, 'landledger/api/connection/connection-org1.json');
const walletDir = process.env.WALLET_PATH || path.join(process.env.HOME, 'landledger/api/wallet');
const mspId     = process.env.MSP_ID || 'Org1MSP';

// Use a fixed, known secret so we can re-enroll reliably
const USER_ID = process.env.USER_ID || 'appUser';
const USER_SECRET = process.env.USER_SECRET || 'apppw';  // << choose any string you like

(async () => {
  const ccp = JSON.parse(fs.readFileSync(ccpPath));
  const caInfo = ccp.certificateAuthorities['ca.org1.example.com'];
  const ca = new FabricCAServices(caInfo.url, { trustedRoots: caInfo.tlsCACerts.pem, verify: false });

  const wallet = await Wallets.newFileSystemWallet(walletDir);

  // admin must exist
  const adminIdentity = await wallet.get('admin');
  if (!adminIdentity) throw new Error('Admin not enrolled (run enrollAdmin.js first)');

  // If wallet already has the user, nothing to do
  if (await wallet.get(USER_ID)) { console.log(`${USER_ID} already in wallet`); return; }

  const provider = wallet.getProviderRegistry().getProvider(adminIdentity.type);
  const adminUser = await provider.getUserContext(adminIdentity, 'admin');
  const idService = ca.newIdentityService();

  let exists = false;
  try {
    await idService.getOne(USER_ID, adminUser);
    exists = true;
  } catch { /* not found */ }

  if (!exists) {
    // fresh register with our known secret
    await ca.register(
      { enrollmentID: USER_ID, role: 'client', affiliation: 'org1.department1', enrollmentSecret: USER_SECRET },
      adminUser
    );
  } else {
    // user exists on CA → reset secret so we can enroll
    await idService.update(USER_ID, { enrollmentSecret: USER_SECRET }, adminUser);
  }

  const enrollment = await ca.enroll({ enrollmentID: USER_ID, enrollmentSecret: USER_SECRET });
  await wallet.put(USER_ID, {
    credentials: { certificate: enrollment.certificate, privateKey: enrollment.key.toBytes() },
    mspId, type: 'X.509'
  });

  console.log(`✅ ${USER_ID} enrolled`);
})();
