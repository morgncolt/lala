// quickEnroll.js
const fs = require('fs');
const path = require('path');
const { Wallets, X509Identity } = require('fabric-network');
const FabricCAServices = require('fabric-ca-client');

async function loadCCP() {
  const connDir = path.join(__dirname, 'connection');
  const files = fs.readdirSync(connDir).filter(f => f.endsWith('.json'));
  if (!files.length) throw new Error(`No connection JSON found in ${connDir}`);
  // Prefer an org1 profile if present, otherwise the first JSON.
  const pick = files.find(f => /org1/i.test(f)) || files[0];
  const ccpPath = path.join(connDir, pick);
  const ccp = JSON.parse(fs.readFileSync(ccpPath, 'utf8'));
  return { ccp, ccpPath };
}

function extractOrgAndCa(ccp) {
  const orgName = Object.keys(ccp.organizations)[0];
  const org = ccp.organizations[orgName];
  const mspId = org.mspid || org.mspId || org.mspID || 'Org1MSP';

  const caKey = Object.keys(ccp.certificateAuthorities)[0];
  const caEntry = ccp.certificateAuthorities[caKey];
  const caURL = caEntry.url;
  const caName = caEntry.caName || caKey;

  // TLS root for CA (string pem or file path)
  let tlsRootCert;
  if (caEntry.tlsCACerts?.pem) tlsRootCert = caEntry.tlsCACerts.pem;
  if (caEntry.tlsCACerts?.path) tlsRootCert = fs.readFileSync(caEntry.tlsCACerts.path, 'utf8');

  // Default affiliation for test-network CAs
  const affiliation = org?.certificateAuthorities?.length ? `${orgName.toLowerCase()}.department1` : 'org1.department1';

  return { mspId, caURL, caName, tlsRootCert, affiliation };
}

async function ensureAdmin(ca, wallet, mspId) {
  const label = 'admin';
  const exists = await wallet.get(label);
  if (exists) return label;

  // Default test-network bootstrap creds:
  const enrollmentID = process.env.CA_ADMIN || 'admin';
  const enrollmentSecret = process.env.CA_ADMINPW || 'adminpw';

  const { certificate, key } = await ca.enroll({ enrollmentID, enrollmentSecret });
  const identity = {
    credentials: { certificate, privateKey: key.toBytes() },
    mspId,
    type: 'X.509',
  };
  await wallet.put(label, identity);
  return label;
}

async function ensureAppUser(ca, wallet, mspId, adminLabel, affiliation) {
  const userLabel = process.env.LL_ID || 'appUser';
  const exists = await wallet.get(userLabel);
  if (exists) return userLabel;

  const provider = wallet.getProviderRegistry().getProvider('X.509');
  const adminIdentity = await wallet.get(adminLabel);
  const adminUser = await provider.getUserContext(adminIdentity, adminLabel);

  let secret;
  try {
    secret = await ca.register({
      enrollmentID: userLabel,
      role: 'client',
      affiliation,
      attrs: [{ name: 'hf.Registrar.Roles', value: 'client', ecert: true }],
    }, adminUser);
  } catch (e) {
    if (!/already registered/i.test(String(e))) throw e;
    // If already registered, you must know the secret; for test-network we re-use a known value if set.
    secret = process.env.LL_SECRET || 'appUserpw';
  }

  const { certificate, key } = await ca.enroll({ enrollmentID: userLabel, enrollmentSecret: secret });
  /** @type {X509Identity} */
  const userId = {
    credentials: { certificate, privateKey: key.toBytes() },
    mspId,
    type: 'X.509',
  };
  await wallet.put(userLabel, userId);
  return userLabel;
}

(async () => {
  const { ccp, ccpPath } = await loadCCP();
  const { mspId, caURL, caName, tlsRootCert, affiliation } = extractOrgAndCa(ccp);

  const ca = new FabricCAServices(caURL, tlsRootCert ? { trustedRoots: tlsRootCert, verify: true } : undefined, caName);
  const wallet = await Wallets.newFileSystemWallet(path.join(__dirname, 'wallet'));

  console.log('Using CCP:', ccpPath);
  console.log('MSP:', mspId, '| CA:', caName, '| Affiliation:', affiliation);

  const admin = await ensureAdmin(ca, wallet, mspId);
  const user = await ensureAppUser(ca, wallet, mspId, admin, affiliation);

  console.log('✅ Enrolled identities ->', { admin, user });
})();
