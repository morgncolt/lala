// ~/landledger/api/scripts/resetAndEnrollUser.js
const FabricCAServices = require('fabric-ca-client');
const { Wallets } = require('fabric-network');
const fs = require('fs'); const path = require('path');

const ccpPath   = process.env.CCP_PATH   || path.join(process.env.HOME, 'landledger/api/connection/connection-org1.json');
const walletDir = process.env.WALLET_PATH || path.join(process.env.HOME, 'landledger/api/wallet');
const mspId     = process.env.MSP_ID || 'Org1MSP';
const USER_ID   = process.env.USER_ID || 'appUser';
const USER_SECRET = process.env.USER_SECRET || 'apppw'; // choose your known secret

(async () => {
  const ccp = JSON.parse(fs.readFileSync(ccpPath));
  const caInfo = ccp.certificateAuthorities['ca.org1.example.com'];
  const ca = new FabricCAServices(caInfo.url, { trustedRoots: caInfo.tlsCACerts.pem, verify: false });

  const wallet = await Wallets.newFileSystemWallet(walletDir);

  // Ensure CA admin is present
  const adminIdentity = await wallet.get('admin');
  if (!adminIdentity) throw new Error('Admin not enrolled. Run enrollAdmin.js first.');

  // If already in wallet, we're done
  if (await wallet.get(USER_ID)) { console.log(`${USER_ID} already in wallet`); return; }

  // Helper to enroll + store
  async function enrollWithSecret(secret, label = USER_ID) {
    const enr = await ca.enroll({ enrollmentID: USER_ID, enrollmentSecret: secret });
    await wallet.put(label, {
      credentials: { certificate: enr.certificate, privateKey: enr.key.toBytes() },
      mspId, type: 'X.509'
    });
    console.log(`✅ ${USER_ID} enrolled`);
  }

  // 1) First try: enroll directly with our chosen secret
  try {
    await enrollWithSecret(USER_SECRET);
    return;
  } catch (e) {
    const msg = String(e && e.message || e);
    if (!/Authentication failure|enroll failed|enrollment failed/i.test(msg)) {
      // Not an auth problem (e.g. CA offline); rethrow
      throw e;
    }
    // proceed to reset/register
  }

  // Build admin user context
  const provider = wallet.getProviderRegistry().getProvider(adminIdentity.type);
  const adminUser = await provider.getUserContext(adminIdentity, 'admin');

  // 2) Try to UPDATE the identity's secret on the CA (works if user already registered)
  try {
    await ca.newIdentityService().update(USER_ID, { enrollmentSecret: USER_SECRET }, adminUser);
    await enrollWithSecret(USER_SECRET);
    return;
  } catch (e) {
    const msg = String(e && e.message || e);
    // If the user truly doesn't exist, CA often returns code 86 or a "not found/does not exist" message
    const notFound = /code:\s*86|not\s*found|does\s*not\s*exist/i.test(msg);
    if (!notFound) {
      // Some CAs restrict visibility; if update is forbidden but user exists, try a last-chance enroll with default 'appUser' secret
      try {
        await enrollWithSecret('appUser');
        return;
      } catch { /* fall through to register */ }
    }
    // 3) Register then enroll
    await ca.register({
      enrollmentID: USER_ID,
      role: 'client',
      affiliation: 'org1.department1',
      enrollmentSecret: USER_SECRET
    }, adminUser);
    await enrollWithSecret(USER_SECRET);
  }
})();
