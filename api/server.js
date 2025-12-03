// server.js
const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const firebaseAuth = require('./middleware/firebaseAuth');

// Create app FIRST
const app = express();

// Middlewares
app.use(cors());
app.use(bodyParser.json());

// Health
app.get('/healthz', (req, res) => res.json({ ok: true, ts: new Date().toISOString() }));

// Identity & TX routes you added earlier
const { registerAndEnroll } = require('./services/identity');
const { withContract } = require('./services/gateway');

// Shared handler for identity registration
const registerHandler = async (req, res) => {
  try {
    const uid = (req.user && req.user.uid) || req.body.uid || req.body.email;
    const email = req.body.email;

    if (!uid || !email) {
      return res.status(400).json({ ok:false, error:'uid or email required' });
    }

    const out = await registerAndEnroll({
      label: uid,
      email,
      attrs: req.body.role ? [{ name: 'role', value: req.body.role, ecert: true }] : []
    });

    res.json({ ok: true, ...out, mspId: process.env.FABRIC_MSP_ID || 'Org1MSP' });
  } catch (e) { res.status(500).json({ ok: false, error: e.message }); }
};

// Deprecated: remove or protect this route in production
app.post('/api/identity/register', (req, res) => {
  return res.status(410).json({ ok:false, error:'Deprecated. Use POST /identity/provision with Firebase auth' });
});

// Alias for old client calls
app.post('/api/identity/provision', registerHandler);

app.post('/api/identity/link', (req, res) => {
  const b = req.body || {};
  const uid = b.uid ?? b.userId ?? b.user ?? b.email;
  const displayAddress =
    b.displayAddress ?? b.address ?? b.walletAddress ?? b.addr;

  if (!uid || !displayAddress) {
    // Log but don’t crash; tell the client exactly what was missing
    console.warn('[LINK] 400 missing fields', { uid, displayAddress, body: b });
    return res.status(400).json({
      ok: false,
      error: 'uid and displayAddress are required',
      got: { uid: !!uid, displayAddress: !!displayAddress }
    });
  }

  // TODO: persist to DB (e.g., Firestore). For now just log & succeed.
  console.log('[LINK] uid=%s addr=%s', uid, displayAddress);
  return res.json({ ok: true });
});

// Optional compatibility aliases
app.post('/api/wallet/link', (req, res, next) => {
  req.url = '/api/identity/link';
  app._router.handle(req, res, next);
});
app.post('/api/identity/provision', (req, res, next) => {
  req.url = '/api/identity/register';
  app._router.handle(req, res, next);
});

// Protect TX endpoints with Firebase (once creds are set)
app.post('/api/tx/submit', /*firebaseAuth,*/ async (req, res) => {
  try {
    const { uid, fcn, args } = req.body;
    const payload = await withContract(uid, async (contract) => {
      const r = await contract.submitTransaction(fcn, ...(args || []));
      return r.toString();
    });
    res.json({ ok: true, payload, receipt: { fcn, args, signerLabel: uid, ts: new Date().toISOString() } });
  } catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

app.post('/api/tx/evaluate', /*firebaseAuth,*/ async (req, res) => {
  try {
    const { uid, fcn, args } = req.body;
    const payload = await withContract(uid, async (contract) => {
      const r = await contract.evaluateTransaction(fcn, ...(args || []));
      return r.toString();
    });
    res.json({ ok: true, payload });
  } catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

// Read-only wallet endpoint (idempotent)
app.get('/api/identity/me', async (req, res) => {
  try {
    const uid = (req.user && req.user.uid) || req.query.uid || req.body?.uid;
    const email = req.query.email || req.body?.email;
    if (!uid) return res.status(400).json({ ok:false, error:'uid required' });

    // Ensure identity exists; safe if already enrolled
    const out = await registerAndEnroll({
      label: uid,
      email: email || `${uid}@example.local`,
      attrs: []
    });

    res.json({ ok: true, walletLabel: uid, mspId: process.env.FABRIC_MSP_ID || 'Org1MSP', ...out });
  } catch (e) {
    res.status(500).json({ ok:false, error: e.message });
  }
});

// Mount your land routes LAST (and NEVER require server.js inside routes)
const landRoutes = require('./routes/land');
app.use('/api/landledger', landRoutes);

// Start
const port = process.env.PORT || 4000;
app.listen(port, '0.0.0.0', () => console.log(`API listening on :${port}`));

module.exports = app; // exported only for tests
