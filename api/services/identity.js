const FabricCAServices = require('fabric-ca-client');
const { Wallets } = require('fabric-network');
const crypto = require('crypto');
const {
  caURL, caName, mspId, walletPath, adminLabel, defaultAffiliation,
} = require('../config/fabric');

function displayAddressFromCertPEM(pem) {
  const fp = crypto.createHash('sha256').update(pem).digest('hex');
  return { displayAddress: '0x' + fp.slice(-40), fingerprint: fp };
}

async function getAdminUser(wallet) {
  const adminIdentity = await wallet.get(adminLabel);
  if (!adminIdentity) {
    throw new Error('Admin identity missing in wallet (run enrollAdmin.js)');
  }
  const provider = wallet.getProviderRegistry().getProvider(adminIdentity.type);
  return provider.getUserContext(adminIdentity, adminLabel);
}

/**
 * Idempotent:
 * - If identity already exists in wallet => return derived address.
 * - Else: register (or reset secret if already registered), then enroll and store in wallet.
 */
async function registerAndEnroll({ label, email, attrs = [] }) {
  if (!label) throw new Error('label is required');

  const ca = new FabricCAServices(caURL, { verify: false }, caName);
  const wallet = await Wallets.newFileSystemWallet(walletPath);

  // 0) If already in wallet, don’t touch the CA again.
  const existing = await wallet.get(label);
  if (existing) {
    // Derive address from existing cert for consistency
    const certPEM = existing.credentials?.certificate;
    if (!certPEM) return { walletLabel: label, displayAddress: null, fingerprint: null };
    const { displayAddress, fingerprint } = displayAddressFromCertPEM(certPEM);
    return { walletLabel: label, displayAddress, fingerprint, certPEM };
  }

  const adminUser = await getAdminUser(wallet);

  // 1) Try to register a fresh identity to obtain a secret
  let secret;
  try {
    secret = await ca.register(
      {
        enrollmentID: label,
        affiliation: defaultAffiliation, // <- org1.department1 is the fabric-samples default
        attrs: [{ name: 'email', value: email || '', ecert: true }, ...attrs],
      },
      adminUser
    );
  } catch (e) {
    // If already registered, we can't retrieve the original secret.
    // Use IdentityService to set a NEW secret, then enroll with it.
    if (/already registered/i.test(e.message)) {
      const identityService = ca.newIdentityService();
      // Choose a new strong secret; you may want to persist this mapping.
      secret = crypto.randomBytes(16).toString('hex');

      await identityService.update(label, { secret }, adminUser);
    } else {
      throw e;
    }
  }

  // 2) Enroll with the (new or fresh) secret
  const enrollment = await ca.enroll({ enrollmentID: label, enrollmentSecret: secret });

  const x509 = {
    credentials: {
      certificate: enrollment.certificate,
      privateKey: enrollment.key.toBytes(),
    },
    mspId,
    type: 'X.509',
  };

  await wallet.put(label, x509);

  const { displayAddress, fingerprint } = displayAddressFromCertPEM(enrollment.certificate);
  return { walletLabel: label, displayAddress, fingerprint, certPEM: enrollment.certificate };
}

module.exports = { registerAndEnroll };
