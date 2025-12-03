'use strict';

const { Wallets } = require('fabric-network');
const FabricCAServices = require('fabric-ca-client');
const fs = require('fs');
const path = require('path');

const CA_URL  = process.env.CA_URL  || 'https://localhost:7054';
const CA_NAME = process.env.CA_NAME || 'ca-org1';
const MSPID   = process.env.MSPID   || 'Org1MSP';
const WALLET_DIR = process.env.WALLET_DIR || path.join(__dirname, '../wallet');

const ADMIN_ID = process.env.ADMIN_ID || 'admin';
const ADMIN_SECRET = process.env.ADMIN_SECRET || 'adminpw';
const APPUSER_ID = process.env.APPUSER_ID || 'appUser';
const APPUSER_SECRET = process.env.APPUSER_SECRET || 'appUserpw-fixed';

const CA_TLS_CERT = process.env.CA_TLS_CERT ||
  path.join(process.env.HOME || '/home/morgan',
    'blockchain/fabric-samples/test-network/organizations/fabric-ca/org1/ca-cert.pem');

function x509Identity(certificate, privateKey) {
  return {
    credentials: { certificate, privateKey },
    mspId: MSPID,
    type: 'X.509',
  };
}

async function enrollAdmin(ca, wallet) {
  const admin = await wallet.get(ADMIN_ID);
  if (admin) return;

  const enrollment = await ca.enroll({
    enrollmentID: ADMIN_ID,
    enrollmentSecret: ADMIN_SECRET,
    attr_reqs: [],
  });

  await wallet.put(ADMIN_ID, x509Identity(enrollment.certificate, enrollment.key.toBytes()));
}

async function ensureAppUser(ca, wallet) {
  const existing = await wallet.get(APPUSER_ID);
  if (existing) return;

  // Build admin user context for IdentityService
  const provider = wallet.getProviderRegistry().getProvider('X.509');
  const adminIdentity = await wallet.get(ADMIN_ID);
  if (!adminIdentity) throw new Error('Admin not in wallet; enrollAdmin first.');
  const adminUser = await provider.getUserContext(adminIdentity, ADMIN_ID);

  const idService = ca.newIdentityService();

  // Does appUser exist on the CA?
  let exists = false;
  try { await idService.get(APPUSER_ID, adminUser); exists = true; } catch { exists = false; }

  if (!exists) {
    await ca.register({
      enrollmentID: APPUSER_ID,
      enrollmentSecret: APPUSER_SECRET,
      affiliation: 'org1.department1',
      role: 'client',
    }, adminUser);
  } else {
    // Reset secret to known value so enroll always works
    await idService.update(APPUSER_ID, { secret: APPUSER_SECRET }, adminUser);
  }

  const enrollment = await ca.enroll({
    enrollmentID: APPUSER_ID,
    enrollmentSecret: APPUSER_SECRET,
  });

  await wallet.put(APPUSER_ID, x509Identity(enrollment.certificate, enrollment.key.toBytes()));
}

(async () => {
  // TLS trust (verify the real CA cert)
  if (!fs.existsSync(CA_TLS_CERT)) {
    throw new Error(`CA TLS cert not found at ${CA_TLS_CERT}`);
  }
  const tlsOptions = { trustedRoots: [fs.readFileSync(CA_TLS_CERT)], verify: true };

  const ca = new FabricCAServices(CA_URL, tlsOptions, CA_NAME);
  const wallet = await Wallets.newFileSystemWallet(WALLET_DIR);

  await enrollAdmin(ca, wallet);
  await ensureAppUser(ca, wallet);

  console.log('CA bootstrap complete: admin + appUser present in wallet.');
})();
