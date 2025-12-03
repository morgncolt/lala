const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const { registerAndEnroll } = require('./services/identity');
const { withContract } = require('./services/gateway');

const app = express();
app.use(cors());
app.use(bodyParser.json());

/** 1) Register identity for a Firebase user */
app.post('/api/identity/register', async (req, res) => {
  try {
    const { uid, email, role } = req.body; // uid from Firebase; role optional
    const result = await registerAndEnroll({
      label: uid, email,
      attrs: role ? [{ name: 'role', value: role, ecert: true }] : []
    });
    // TODO: also persist to Firestore from backend if you want
    res.json({ ok: true, ...result, mspId: 'Org1MSP' });
  } catch (e) { res.status(500).json({ ok:false, error: e.message }); }
});

app.post('/api/identity/provision', async (req, res) => {
  // simply forward to the same handler logic
  req.url = '/api/identity/register';
  app._router.handle(req, res, () => {});
});

app.post('/api/identity/revoke', async (req, res) => {
  // Use Fabric CA revoke API with admin; add serial/aki from user cert
  res.status(501).json({ ok:false, error:'Not implemented' });
});

app.post('/api/identity/rotate', async (req, res) => {
  // Enroll new keypair (server or client CSR), update wallet entry under same label
  res.status(501).json({ ok:false, error:'Not implemented' });
});

/** 2) Submit transaction (server-managed keys) */
app.post('/api/tx/submit', async (req, res) => {
  try {
    const { uid, fcn, args } = req.body;
    const payload = await withContract(uid, async (contract) => {
      const result = await contract.submitTransaction(fcn, ...(args || []));
      return result.toString();
    });
    // Minimal receipt you can also store in Firestore
    const receipt = {
      txFunction: fcn, args, signerLabel: uid,
      // you can extend by reading event/txid using commit listener if desired
      timestamp: new Date().toISOString()
    };
    res.json({ ok: true, payload, receipt });
  } catch (e) { res.status(500).json({ ok:false, error: e.message }); }
});

/** 3) Evaluate (query) */
app.post('/api/tx/evaluate', async (req, res) => {
  try {
    const { uid, fcn, args } = req.body;
    const payload = await withContract(uid, async (contract) => {
      const result = await contract.evaluateTransaction(fcn, ...(args || []));
      return result.toString();
    });
    res.json({ ok: true, payload });
  } catch (e) { res.status(500).json({ ok:false, error: e.message }); }
});

// (Optional Phase 2) OFFLINE SIGNING endpoints scaffold
app.post('/api/offline/prepare', async (req, res) => {
  // Prepare proposal bytes for client to sign (advanced; fill when you switch to offline signing)
  res.status(501).json({ ok:false, error:'Not implemented yet' });
});

app.post('/api/offline/submit', async (req, res) => {
  // Accept signed proposal + endorsements; submit to orderer
  res.status(501).json({ ok:false, error:'Not implemented yet' });
});

const port = process.env.PORT || 4000;
app.listen(port, () => console.log(`API on :${port}`));