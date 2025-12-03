// scripts/resetAndEnrollUser.js
const fs = require('fs');
const { Wallets } = require('fabric-network');
const FabricCAServices = require('fabric-ca-client');

(async () => {
  const ccpPath = process.env.CCP_PATH;
  const walletPath = process.env.WALLET_PATH || 'wallet';
  const mspId = process.env.MSP_ID || 'Org1MSP';
  const userId = process.env.USER_ID || 'appUser';
  const userSecret = process.env.USER_SECRET || 'apppw';

  if (!fs.existsSync(ccpPath)) throw new Error(`Missing CCP at ${ccpPath}`);
  const ccp = JSON.parse(fs.readFileSync(ccpPath, 'utf8'));

  // CA config
  const caKey = Object.keys(ccp.certificateAuthorities)[0];
  const caInfo = ccp.certificateAuthorities[caKey];
  const ca = new FabricCAServices(
    caInfo.url,
    { trustedRoots: caInfo.tlsCACerts?.pem, verify: false },
    caInfo.caName
  );

  const wallet = await Wallets.newFileSystemWallet(walletPath);

  // Ensure admin exists
  let admin = await wallet.get('admin');
  if (!admin) throw new Error('Admin identity missing in wallet. Run enrollAdmin.js first.');

  // Remove old user (to avoid stale certs)
  const existing = await wallet.get(userId);
  if (existing) await wallet.remove(userId);

  // Build admin user context
  const provider = wallet.getProviderRegistry().getProvider(admin.type);
  const adminUser = await provider.getUserContext(admin, 'admin');

  // Register (idempotent—ignore “already registered”)
  try {
    await ca.register({
      enrollmentID: userId,
      enrollmentSecret: userSecret,
      role: 'client',
      affiliation: 'org1.department1',
      attrs: [{ name: 'hf.Registrar.Roles', value: 'client', ecert: true }],
    }, adminUser);
  } catch (e) {
    if (!String(e.message).includes('already registered')) throw e;
  }

  // Enroll
  const enrollment = await ca.enroll({
    enrollmentID: userId,
    enrollmentSecret: userSecret,
  });

  const x509Identity = {
    credentials: {
      certificate: enrollment.certificate,
      privateKey: enrollment.key.toBytes(),
    },
    mspId,
    type: 'X.509',
  };

  await wallet.put(userId, x509Identity);
  console.log(`✅ Enrolled and imported '${userId}' into wallet: ${walletPath}`);
})().catch((e) => {
  console.error('❌ resetAndEnrollUser failed:', e);
  process.exit(1);
});
