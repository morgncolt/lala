// server.js
'use strict';

const express = require('express');
const cors = require('cors');
const morgan = require('morgan');
const dotenv = require('dotenv');
const { Wallets, Gateway } = require('fabric-network');
const fs = require('fs');
const path = require('path');

dotenv.config();

/* =========================
 * Config + sensible defaults
 * ========================= */
const CHANNEL  = process.env.CHANNEL || 'mychannel';
const CC_NAME  = process.env.CC_NAME || 'landledger';
const IDENTITY = process.env.FABRIC_IDENTITY || 'appUser';
const PORT     = Number(process.env.PORT || 4000);

// If true, we keep a single Gateway open and reuse it across requests.
const REUSE_GATEWAY = /^true$/i.test(process.env.REUSE_GATEWAY || 'true');

// Expand ~ or $HOME in env paths (works on WSL/Windows too)
const expandPath = (p) => {
  if (!p) return p;
  const home = process.env.HOME || process.env.USERPROFILE || '';
  return p
    .replace(/^~(?=\/|\\|$)/, home)
    .replace(/^\$HOME\b/, home)
    .replace(/^%USERPROFILE%/i, process.env.USERPROFILE || '');
};

// Default test-network Org1 CCP + wallet locations
const CCP_PATH = expandPath(process.env.CCP_PATH) ||
  path.join(process.env.HOME || process.env.USERPROFILE, 'blockchain', 'fabric-samples', 'test-network',
            'organizations', 'peerOrganizations', 'org1.example.com', 'connection-org1.json');

const WALLET_PATH = expandPath(process.env.WALLET_PATH) ||
  path.join(process.env.HOME || process.env.USERPROFILE, 'blockchain', 'fabric-samples',
            'asset-transfer-basic', 'application-javascript', 'wallet');

/* =========================
 * Startup sanity warnings (non-fatal)
 * ========================= */
(function startupWarnings() {
  try { if (!fs.existsSync(CCP_PATH)) console.warn(`[WARN] CCP file not found at ${CCP_PATH}`); } catch {}
  try { if (!fs.existsSync(WALLET_PATH)) console.warn(`[WARN] Wallet dir not found at ${WALLET_PATH}`); } catch {}
})();

/* =========================
 * Fabric helpers
 * ========================= */
let cached = /** @type {{gateway: Gateway, walletPath: string}|null} */ (null);

async function loadCCP() {
  const json = fs.readFileSync(CCP_PATH, 'utf8');
  return JSON.parse(json);
}

async function ensureIdentityExists(wallet, identityLabel) {
  const id = await wallet.get(identityLabel);
  if (!id) {
    const msg = `Identity "${identityLabel}" not found in wallet at ${WALLET_PATH}. Import/enroll it first.`;
    const err = new Error(msg);
    // @ts-ignore
    err.code = 'NO_IDENTITY';
    throw err;
  }
}

async function getGatewayAndContract() {
  // Reuse a single gateway if configured
  if (REUSE_GATEWAY && cached?.gateway) {
    const network = await cached.gateway.getNetwork(CHANNEL);
    const contract = network.getContract(CC_NAME);
    return { gateway: cached.gateway, contract, isShared: true };
  }

  const ccp = await loadCCP();
  const wallet = await Wallets.newFileSystemWallet(WALLET_PATH);
  await ensureIdentityExists(wallet, IDENTITY);

  const gateway = new Gateway();
  await gateway.connect(ccp, {
    wallet,
    identity: IDENTITY,
    discovery: { enabled: true, asLocalhost: true },
  });

  if (REUSE_GATEWAY) {
    cached = { gateway, walletPath: WALLET_PATH };
  }

  const network = await gateway.getNetwork(CHANNEL);
  const contract = network.getContract(CC_NAME);
  return { gateway, contract, isShared: REUSE_GATEWAY };
}

async function disconnectIfNeeded(gateway, isShared) {
  if (!isShared && gateway) {
    try { await gateway.disconnect(); } catch {}
  }
}

/* =========================
 * Express app
 * ========================= */
const app = express();
app.use(cors());

// Simple request id for log correlation
app.use((req, _res, next) => {
  req.id = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2,7)}`;
  next();
});
morgan.token('id', (req) => req.id);
app.use(morgan(':date[iso] [:id] :method :url :status :response-time ms - :res[content-length]'));
app.use(express.json({ limit: '10mb' }));

// Health endpoints
app.get('/healthz', (_req, res) => res.json({ ok: true, ts: new Date().toISOString() }));

app.get('/readyz', async (_req, res) => {
  const checks = { ccpExists: false, walletExists: false, identityOk: false, gatewayOk: false, contractOk: false, error: null };
  try {
    checks.ccpExists = fs.existsSync(CCP_PATH);
    checks.walletExists = fs.existsSync(WALLET_PATH);

    const ccp = await loadCCP();
    const wallet = await Wallets.newFileSystemWallet(WALLET_PATH);
    const id = await wallet.get(IDENTITY);
    checks.identityOk = !!id;

    const gateway = new Gateway();
    await gateway.connect(ccp, { wallet, identity: IDENTITY, discovery: { enabled: true, asLocalhost: true } });
    checks.gatewayOk = true;

    const network = await gateway.getNetwork(CHANNEL);
    const contract = network.getContract(CC_NAME);
    checks.contractOk = !!contract;

    try { await gateway.disconnect(); } catch {}
    return res.json({ ok: true, ...checks });
  } catch (e) {
    checks.error = e?.message || String(e);
    return res.status(500).json({ ok: false, ...checks });
  }
});

// Debug info (useful in prod)
app.get('/debug/info', (_req, res) => {
  res.json({
    CHANNEL, CC_NAME, IDENTITY, REUSE_GATEWAY,
    CCP_PATH, WALLET_PATH,
    cwd: process.cwd(),
    node: process.version,
    ts: new Date().toISOString(),
  });
});

/* =========================
 * Helpers
 * ========================= */

// Safely parse Fabric payloads (empty buffer => fallback)
function parseJSONOr(buf, fallback) {
  const s = Buffer.isBuffer(buf) ? buf.toString() : String(buf ?? '');
  if (!s || !s.trim()) return fallback;
  try { return JSON.parse(s); }
  catch (e) {
    const err = new Error('Failed to parse chaincode JSON payload');
    // @ts-ignore
    err.cause = e;
    throw err;
  }
}

// Uniform error response (+ logging)
function sendError(res, status, e, extra = {}) {
  const msg = e?.message || String(e);
  const payload = {
    error: msg,
    ...(process.env.NODE_ENV !== 'production' ? { stack: e?.stack } : {}),
  };
  try {
    console.error('API ERROR', {
      status,
      msg,
      stack: e?.stack,
      at: new Date().toISOString(),
      ...extra,
    });
  } catch {}
  return res.status(status).json(payload);
}

// Normalize/validate parcel payload from client
function buildParcelFromReq(body) {
  const {
    parcelId,
    titleNumber,
    owner,
    coordinates,
    areaSqKm,
    description,
    createdAt,
    verified
  } = body || {};

  if (!parcelId || typeof parcelId !== 'string') {
    const err = new Error('parcelId (string) is required'); err.status = 400; throw err;
  }
  if (!owner || typeof owner !== 'string') {
    const err = new Error('owner (string) is required'); err.status = 400; throw err;
  }

  const out = {
    parcelId: parcelId.trim(),
    titleNumber: (typeof titleNumber === 'string' && titleNumber.trim()) || titleNumber || undefined,
    owner: owner.trim(),
    coordinates: Array.isArray(coordinates) ? coordinates : (typeof coordinates === 'object' ? coordinates : undefined),
    areaSqKm: (typeof areaSqKm === 'number') ? areaSqKm : undefined,
    description: (typeof description === 'string' ? description : undefined),
    createdAt: createdAt || new Date().toISOString(),
  };
  if (typeof verified === 'boolean') out.verified = verified;
  return out;
}

/* =========================
 * Routes
 * ========================= */

/**
 * IMPORTANT: Define /blocks BEFORE "/:id"
 */

// Blocks (temporary feed) – maps to GetAllParcels
app.get('/api/landledger/blocks', async (_req, res) => {
  try {
    const { gateway, contract, isShared } = await getGatewayAndContract();
    try {
      const r = await contract.evaluateTransaction('GetAllParcels');
      const out = parseJSONOr(r, []);
      res.json(Array.isArray(out) ? out : []);
    } finally { await disconnectIfNeeded(gateway, isShared); }
  } catch (e) {
    return sendError(res, 404, e, { route: 'GET /api/landledger/blocks' });
  }
});

// Read all
app.get('/api/landledger', async (_req, res) => {
  try {
    const { gateway, contract, isShared } = await getGatewayAndContract();
    try {
      const r = await contract.evaluateTransaction('GetAllParcels');
      const out = parseJSONOr(r, []);        // <= defensive
      return res.json(Array.isArray(out) ? out : []);
    } finally { await disconnectIfNeeded(gateway, isShared); }
  } catch (e) {
    return sendError(res, 500, e, { route: 'GET /api/landledger' });
  }
});

// Create/Register
app.post('/api/landledger/register', async (req, res) => {
  try {
    const parcel = buildParcelFromReq(req.body);
    const { gateway, contract, isShared } = await getGatewayAndContract();
    try {
      await contract.submitTransaction('RegisterParcel', JSON.stringify(parcel));
      return res.json({ ok: true, id: parcel.parcelId });
    } finally { await disconnectIfNeeded(gateway, isShared); }
  } catch (e) {
    const status = e?.status || 500;
    return sendError(res, status, e, { route: 'POST /api/landledger/register', body: req.body });
  }
});

// Read one
app.get('/api/landledger/:id', async (req, res) => {
  try {
    const { gateway, contract, isShared } = await getGatewayAndContract();
    try {
      const r = await contract.evaluateTransaction('GetParcel', req.params.id);
      const out = parseJSONOr(r, null);
      if (out == null) return res.status(404).json({ error: `parcel ${req.params.id} not found` });
      return res.json(out);
    } finally { await disconnectIfNeeded(gateway, isShared); }
  } catch (e) {
    const status = /not found/i.test(e?.message || '') ? 404 : 500;
    return sendError(res, status, e, { route: 'GET /api/landledger/:id', id: req.params.id });
  }
});

// Query by owner
app.get('/api/landledger/owner/:owner', async (req, res) => {
  try {
    const owner = decodeURIComponent(req.params.owner);
    const { gateway, contract, isShared } = await getGatewayAndContract();
    try {
      const r = await contract.evaluateTransaction('QueryByOwner', owner);
      return res.json(parseJSONOr(r, []));
    } finally { await disconnectIfNeeded(gateway, isShared); }
  } catch (e) { return sendError(res, 500, e, { route: 'GET /api/landledger/owner/:owner', owner: req.params.owner }); }
});

// Query by title
app.get('/api/landledger/title/:titleNumber', async (req, res) => {
  try {
    const titleNumber = decodeURIComponent(req.params.titleNumber);
    const { gateway, contract, isShared } = await getGatewayAndContract();
    try {
      const r = await contract.evaluateTransaction('QueryByTitle', titleNumber);
      return res.json(parseJSONOr(r, []));
    } finally { await disconnectIfNeeded(gateway, isShared); }
  } catch (e) { return sendError(res, 500, e, { route: 'GET /api/landledger/title/:titleNumber', title: req.params.titleNumber }); }
});

// Transfer owner
app.post('/api/landledger/transfer', async (req, res) => {
  const { parcelId, newOwner } = req.body || {};
  if (!parcelId || !newOwner) return res.status(400).json({ error: 'parcelId and newOwner are required' });
  try {
    const { gateway, contract, isShared } = await getGatewayAndContract();
    try {
      await contract.submitTransaction('TransferOwner', parcelId, newOwner);
      return res.json({ ok: true, id: parcelId, newOwner });
    } finally { await disconnectIfNeeded(gateway, isShared); }
  } catch (e) { return sendError(res, 500, e, { route: 'POST /api/landledger/transfer', body: req.body }); }
});

// Update description
app.patch('/api/landledger/:id/description', async (req, res) => {
  const { description } = req.body || {};
  if (typeof description !== 'string' || description.trim() === '') {
    return res.status(400).json({ error: 'description is required (non-empty string)' });
  }
  try {
    const { gateway, contract, isShared } = await getGatewayAndContract();
    try {
      await contract.submitTransaction('UpdateDescription', req.params.id, description);
      return res.json({ ok: true, id: req.params.id });
    } finally { await disconnectIfNeeded(gateway, isShared); }
  } catch (e) { return sendError(res, 500, e, { route: 'PATCH /api/landledger/:id/description', id: req.params.id }); }
});

// Update geometry (coordinates and/or area)
app.patch('/api/landledger/:id/geometry', async (req, res) => {
  const { coordinates, areaSqKm } = req.body || {};
  if (!Array.isArray(coordinates) && typeof areaSqKm === 'undefined') {
    return res.status(400).json({ error: 'coordinates or areaSqKm required' });
  }
  const coordsJSON = Array.isArray(coordinates) ? JSON.stringify(coordinates) : '';
  const areaStr    = typeof areaSqKm !== 'undefined' ? String(areaSqKm) : '';
  try {
    const { gateway, contract, isShared } = await getGatewayAndContract();
    try {
      await contract.submitTransaction('UpdateGeometry', req.params.id, coordsJSON, areaStr);
      return res.json({ ok: true, id: req.params.id });
    } finally { await disconnectIfNeeded(gateway, isShared); }
  } catch (e) { return sendError(res, 500, e, { route: 'PATCH /api/landledger/:id/geometry', id: req.params.id }); }
});

// Delete parcel
app.delete('/api/landledger/:id', async (req, res) => {
  try {
    const { gateway, contract, isShared } = await getGatewayAndContract();
    try {
      await contract.submitTransaction('DeleteParcel', req.params.id);
      return res.json({ ok: true, id: req.params.id, deleted: true });
    } finally { await disconnectIfNeeded(gateway, isShared); }
  } catch (e) { return sendError(res, 500, e, { route: 'DELETE /api/landledger/:id', id: req.params.id }); }
});

// History
app.get('/api/landledger/:id/history', async (req, res) => {
  try {
    const { gateway, contract, isShared } = await getGatewayAndContract();
    try {
      const r = await contract.evaluateTransaction('GetHistory', req.params.id);
      return res.json(parseJSONOr(r, []));
    } finally { await disconnectIfNeeded(gateway, isShared); }
  } catch (e) { return sendError(res, 500, e, { route: 'GET /api/landledger/:id/history', id: req.params.id }); }
});

/* =========================
 * Fallback error handler (safety net)
 * ========================= */
app.use((err, req, res, _next) => {
  const status = err?.status || 500;
  return sendError(res, status, err, { route: `${req.method} ${req.originalUrl}`, id: req.id });
});

/* =========================
 * Start + graceful shutdown
 * ========================= */
const server = app.listen(PORT, '0.0.0.0', () => {
  console.log(`API listening on ${PORT}`);
});

async function shutdown(code = 0) {
  server.close(() => process.exit(code));
  try { if (cached?.gateway) await cached.gateway.disconnect(); } catch {}
}

process.on('SIGINT',  () => shutdown(0));
process.on('SIGTERM', () => shutdown(0));

module.exports = app; // useful for testing
