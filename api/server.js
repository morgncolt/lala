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
    const msg = `Identity "${identityLabel}" not found in wallet at ${WALLET_PATH}. ` +
                `Import or enroll the identity before starting the API.`;
    const err = new Error(msg);
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
app.use(morgan('dev'));
app.use(express.json({ limit: '10mb' }));

// Health endpoints
app.get('/healthz', (_req, res) => res.json({ ok: true, ts: new Date().toISOString() }));
app.get('/readyz', async (_req, res) => {
  try {
    const { gateway, contract, isShared } = await getGatewayAndContract();
    // a very light ping (evaluate chaincode name querycommitted is heavier; just ensure we got a contract)
    await disconnectIfNeeded(gateway, isShared);
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ ok: false, error: e?.message || String(e) });
  }
});

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
  const out = {
    parcelId,
    titleNumber,         // chaincode will default to parcelId if empty
    owner,
    coordinates: Array.isArray(coordinates) ? coordinates : undefined,
    areaSqKm: (typeof areaSqKm === 'number') ? areaSqKm : undefined,
    description,
    createdAt: createdAt || new Date().toISOString(),
  };
  // Optional: allow client to set verified explicitly (bool)
  if (typeof verified === 'boolean') out.verified = verified;
  return out;
}

// Uniform error response helper
function sendError(res, status, e) {
  const msg = e?.message || String(e);
  return res.status(status).json({ error: msg });
}

/* =========================
 * Routes
 * ========================= */

// Create/Register
app.post('/api/landledger/register', async (req, res) => {
  try {
    const parcel = buildParcelFromReq(req.body);
    if (!parcel.parcelId || !parcel.owner) {
      return res.status(400).json({ error: 'parcelId and owner are required' });
    }
    const { gateway, contract, isShared } = await getGatewayAndContract();
    try {
      await contract.submitTransaction('RegisterParcel', JSON.stringify(parcel));
      return res.json({ ok: true, id: parcel.parcelId });
    } finally { await disconnectIfNeeded(gateway, isShared); }
  } catch (e) { return sendError(res, 500, e); }
});

// Read one
app.get('/api/landledger/:id', async (req, res) => {
  try {
    const { gateway, contract, isShared } = await getGatewayAndContract();
    try {
      const r = await contract.evaluateTransaction('GetParcel', req.params.id);
      return res.json(JSON.parse(r.toString()));
    } finally { await disconnectIfNeeded(gateway, isShared); }
  } catch (e) {
    // chaincode returns "parcel <id> not found" -> map to 404
    const status = /not found/i.test(e?.message || '') ? 404 : 500;
    return sendError(res, status, e);
  }
});

// Read all
app.get('/api/landledger', async (_req, res) => {
  try {
    const { gateway, contract, isShared } = await getGatewayAndContract();
    try {
      const r = await contract.evaluateTransaction('GetAllParcels');
      return res.json(JSON.parse(r.toString()));
    } finally { await disconnectIfNeeded(gateway, isShared); }
  } catch (e) { return sendError(res, 500, e); }
});

// Query by owner
app.get('/api/landledger/owner/:owner', async (req, res) => {
  try {
    const owner = decodeURIComponent(req.params.owner);
    const { gateway, contract, isShared } = await getGatewayAndContract();
    try {
      const r = await contract.evaluateTransaction('QueryByOwner', owner);
      return res.json(JSON.parse(r.toString()));
    } finally { await disconnectIfNeeded(gateway, isShared); }
  } catch (e) { return sendError(res, 500, e); }
});

// Query by title
app.get('/api/landledger/title/:titleNumber', async (req, res) => {
  try {
    const titleNumber = decodeURIComponent(req.params.titleNumber);
    const { gateway, contract, isShared } = await getGatewayAndContract();
    try {
      const r = await contract.evaluateTransaction('QueryByTitle', titleNumber);
      return res.json(JSON.parse(r.toString()));
    } finally { await disconnectIfNeeded(gateway, isShared); }
  } catch (e) { return sendError(res, 500, e); }
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
  } catch (e) { return sendError(res, 500, e); }
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
  } catch (e) { return sendError(res, 500, e); }
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
  } catch (e) { return sendError(res, 500, e); }
});

// Delete parcel
app.delete('/api/landledger/:id', async (req, res) => {
  try {
    const { gateway, contract, isShared } = await getGatewayAndContract();
    try {
      await contract.submitTransaction('DeleteParcel', req.params.id);
      return res.json({ ok: true, id: req.params.id, deleted: true });
    } finally { await disconnectIfNeeded(gateway, isShared); }
  } catch (e) { return sendError(res, 500, e); }
});

// History
app.get('/api/landledger/:id/history', async (req, res) => {
  try {
    const { gateway, contract, isShared } = await getGatewayAndContract();
    try {
      const r = await contract.evaluateTransaction('GetHistory', req.params.id);
      return res.json(JSON.parse(r.toString()));
    } finally { await disconnectIfNeeded(gateway, isShared); }
  } catch (e) { return sendError(res, 500, e); }
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
