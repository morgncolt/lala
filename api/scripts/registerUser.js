const fs = require('fs');
const path = require('path');
const FabricCAServices = require('fabric-ca-client');
const { Wallets, Gateway, X509Identity } = require('fabric-network');

(async () => {
  try {
    const ccpPath = process.env.CCP_PATH;
    const walletDir = process.env.WALLET_DIR || path.join(__dirname, 'wallet');
    const userId = process.env.IDENTITY || 'appUser';

    const ccp = JSON.parse(fs.readFileSync(ccpPath, 'utf8'));
    const caName = Object.keys(ccp.certificateAuthorities)[0];
    const caInfo = ccp.certificateAuthorities[caName];

    let tlsRoots;
    if (caInfo.tlsCACerts?.path) {
      tlsRoots = fs.readFileSync(caInfo.tlsCACerts.path);
    } else if (caInfo.tlsCACerts?.pem) {
      tlsRoots = Array.isArray(caInfo.tlsCACerts.pem) ? caInfo.tlsCACerts.pem.join('\n') : caInfo.tlsCACerts.pem;
    }
    const ca = new FabricCAServices(caInfo.url, { trustedRoots: tlsRoots, verify: false }, caInfo.caName);

    const wallet = await Wallets.newFileSystemWallet(walletDir);
    if (await wallet.get(userId)) {
      console.log(`✔ ${userId} already in wallet`);
      return;
    }
    const adminIdentity = await wallet.get('admin');
    if (!adminIdentity) throw new Error('Admin identity missing. Run enrollAdmin.js first.');

    // Use admin to register
    const gateway = new Gateway();
    await gateway.connect(ccp, {
      wallet,
      identity: 'admin',
      discovery: { enabled: true, asLocalhost: true },
    });

    const admin = gateway.getIdentity();
    const provider = wallet.getProviderRegistry().getProvider(admin.type);
    const adminUser = await provider.getUserContext(admin, 'admin');

    const affiliation = 'org1.department1'; // default from test-network
    try {
      await ca.newAffiliationService().create({ name: affiliation, force: true }, adminUser);
    } catch (_) {}

    const secret = await ca.register(
      { enrollmentID: userId, role: 'client', affiliation },
      adminUser
    );

    const enrollment = await ca.enroll({ enrollmentID: userId, enrollmentSecret: secret });
    const mspId = ccp.organizations.Org1.mspid || 'Org1MSP';
    const userIdentity = {
      credentials: {
        certificate: enrollment.certificate,
        privateKey: enrollment.key.toBytes(),
      },
      mspId,
      type: 'X.509',
    };
    await wallet.put(userId, userIdentity);
    await gateway.close();
    console.log(`✔ Registered & enrolled ${userId}, imported into wallet`);
  } catch (e) {
    console.error('registerUser error:', e);
    process.exit(1);
  }
})();
