// routes/identity.js
const router = require('express').Router();
const FabricCAServices = require('fabric-ca-client');
const { Wallets } = require('fabric-network');
const fs = require('fs');
const crypto = require('crypto');
const auth = require('../middleware/firebaseAuth');

const {
  caURL,
  caName,
  mspId,
  walletPath,
  connectionProfile,
  adminLabel,
  defaultAffiliation,
} = require('../config/fabric');

function displayAddressFromCertPEM(pem) {
  const fp = crypto.createHash('sha256').update(pem).digest('hex');
  return { displayAddress: '0x' + fp.slice(-40), fingerprint: fp };
}

async function getAdminUser(wallet) {
  const adminIdentity = await wallet.get(adminLabel);
  if (!adminIdentity) {
    throw new Error(
      `Admin identity "${adminLabel}" missing in wallet (run enrollAdmin.js with same CA/url/name and walletPath)`
    );
  }
  const provider = wallet.getProviderRegistry().getProvider(adminIdentity.type);
  return provider.getUserContext(adminIdentity, adminLabel);
}

router.post('/provision', auth, async (req, res) => {
  try {
    const { uid, email } = req.user;
    const label = `org1-${uid}`; // stable per user

    // ----- Build CA client from your CCP (preferred) -----
    const ccp = JSON.parse(fs.readFileSync(connectionProfile, 'utf8'));
    const caFromCCP = ccp.certificateAuthorities?.[caName];
    const ca = caFromCCP
      ? new FabricCAServices(
          caFromCCP.url,
          { trustedRoots: caFromCCP.tlsCACerts?.pem, verify: true },
          caFromCCP.caName
        )
      : new FabricCAServices(caURL, { verify: false }, caName); // dev fallback

    const wallet = await Wallets.newFileSystemWallet(walletPath);

    // If identity already in wallet, return quickly with derived address
    const existing = await wallet.get(label);
    if (existing?.credentials?.certificate) {
      const { displayAddress, fingerprint } = displayAddressFromCertPEM(
        existing.credentials.certificate
      );
      return res.json({
        ok: true,
        message: 'Identity already provisioned',
        walletLabel: label,
        displayAddress,
        fingerprint,
      });
    }

    // Admin context
    const adminUser = await getAdminUser(wallet);

    // ----- Register (or reset secret if already registered) -----
    let secret;
    try {
      secret = await ca.register(
        {
          enrollmentID: label,
          affiliation: defaultAffiliation, // e.g., 'org1.department1'
          role: 'client',
          attrs: [
            { name: 'email', value: email || 'unknown', ecert: true },
            { name: 'cif.voter', value: 'true', ecert: true },
          ],
        },
        adminUser
      );
    } catch (e) {
      // If already registered, reset secret via IdentityService (admin-only)
      if (/already registered/i.test(e.message)) {
        const identityService = ca.newIdentityService();
        secret = crypto.randomBytes(16).toString('hex');
        await identityService.update(label, { secret }, adminUser);
      } else {
        throw e;
      }
    }

    // ----- Enroll -----
    const enrollment = await ca.enroll({
      enrollmentID: label,
      enrollmentSecret: secret,
    });

    const x509 = {
      credentials: {
        certificate: enrollment.certificate,
        privateKey: enrollment.key.toBytes(),
      },
      mspId,
      type: 'X.509',
    };

    await wallet.put(label, x509);

    const { displayAddress, fingerprint } = displayAddressFromCertPEM(
      enrollment.certificate
    );

    return res.json({
      ok: true,
      message: 'Identity provisioned',
      walletLabel: label,
      displayAddress,
      fingerprint,
    });
  } catch (e) {
    console.error('[provision] error:', e);
    return res.status(500).json({
      ok: false,
      error: e.message || String(e),
    });
  }
});

module.exports = router;
