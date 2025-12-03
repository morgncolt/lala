// routes/land.js
const express = require('express');
const router = express.Router();

// Use the gateway helper we added before:
const { withContract } = require('../services/gateway');
// const firebaseAuth = require('../middleware/firebaseAuth'); // enable later

// Example endpoints — adjust chaincode fn names to yours
router.get('/', async (req, res) => {
  try {
    const label = req.query.uid || 'admin'; // or derive from auth middleware
    const payload = await withContract(label, async (contract) => {
      const r = await contract.evaluateTransaction('GetAllParcels'); // <-- your CC fn
      return r.toString();
    });
    res.json({ ok: true, payload: JSON.parse(payload || '[]') });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const label = req.query.uid || 'admin';
    const payload = await withContract(label, async (contract) => {
      const r = await contract.evaluateTransaction('ReadParcel', id); // <-- your CC fn
      return r.toString();
    });
    if (!payload) return res.status(404).json({ ok: false, error: 'Not found' });
    res.json({ ok: true, payload: JSON.parse(payload) });
  } catch (e) {
    res.status(404).json({ ok: false, error: e.message });
  }
});

router.post('/polygons', /*firebaseAuth,*/ async (req, res) => {
  try {
    // Prefer req.user.uid once auth is enabled
    const uid = (req.user && req.user.uid) || req.body.uid;
    const polygon = req.body.polygon;
    if (!uid || !polygon) {
      return res.status(400).json({ ok:false, error:'uid and polygon required' });
    }

    const args = [JSON.stringify(polygon)];
    const payload = await withContract(uid, async (contract) => {
      const r = await contract.submitTransaction('RegisterParcel', ...args);
      return r.toString();
    });

    res.json({ ok:true, payload });
  } catch (e) {
    res.status(500).json({ ok:false, error: e.message });
  }
});

module.exports = router;
