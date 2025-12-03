let admin;
try {
  admin = require('firebase-admin');
} catch (e) {
  // Don’t crash the process—log and allow dev fallback
  console.error('firebase-admin not installed. Run: npm i firebase-admin');
  module.exports = (req, res, next) => res.status(500).json({ ok:false, error:'firebase-admin missing' });
  return;
}

function ensureInitialized() {
  if (admin.apps.length) return;
  // Prefer GOOGLE_APPLICATION_CREDENTIALS
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    admin.initializeApp({ credential: admin.credential.applicationDefault() });
  } else if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    const creds = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
    admin.initializeApp({ credential: admin.credential.cert(creds) });
  } else {
    console.warn('[firebaseAuth] No credentials set. Auth will reject requests.');
    // Initialize without creds to avoid crash, but fail closed on verify
    admin.initializeApp();
  }
}

module.exports = async function firebaseAuth(req, res, next) {
  ensureInitialized();
  const authHeader = req.headers.authorization || '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;

  if (!token) {
    return res.status(401).json({ ok:false, error:'Missing Bearer token' });
  }

  try {
    const decoded = await admin.auth().verifyIdToken(token);
    // Attach uid/email for downstream handlers
    req.user = { uid: decoded.uid, email: decoded.email };
    return next();
  } catch (e) {
    return res.status(401).json({ ok:false, error:'Invalid Firebase token', detail: e.message });
  }
};
