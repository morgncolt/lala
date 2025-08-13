const express = require('express');
const cors = require('cors');
const morgan = require('morgan');
const dotenv = require('dotenv');
const { Wallets, Gateway } = require('fabric-network');
const fs = require('fs');
const path = require('path');

dotenv.config();

const CHANNEL = process.env.CHANNEL || 'mychannel';
const CC_NAME = process.env.CC_NAME || 'landledger';
const IDENTITY = process.env.FABRIC_IDENTITY || 'appUser';
const CCP_PATH = process.env.CCP_PATH ||
  path.join(process.env.HOME || process.env.USERPROFILE, 'blockchain', 'fabric-samples', 'test-network',
            'organizations', 'peerOrganizations', 'org1.example.com', 'connection-org1.json');
const WALLET_PATH = process.env.WALLET_PATH ||
  path.join(process.env.HOME || process.env.USERPROFILE, 'blockchain', 'fabric-samples',
            'asset-transfer-basic', 'application-javascript', 'wallet');

async function getContract() {
  const ccp = JSON.parse(fs.readFileSync(CCP_PATH, 'utf8'));
  const wallet = await Wallets.newFileSystemWallet(WALLET_PATH);
  const gateway = new Gateway();
  await gateway.connect(ccp, { wallet, identity: IDENTITY, discovery: { enabled: true, asLocalhost: true } });
  const network = await gateway.getNetwork(CHANNEL);
  return { gateway, contract: network.getContract(CC_NAME) };
}

const app = express();
app.use(cors());
app.use(morgan('dev'));
app.use(express.json({ limit: '5mb' }));

app.post('/api/landledger/register', async (req, res) => {
  try {
    const { id, owner, geojson, description, createdAt } = req.body || {};
    if (!id || !owner || !geojson) return res.status(400).json({ error: 'id, owner, geojson required' });
    const { gateway, contract } = await getContract();
    await contract.submitTransaction('Register', id, owner, JSON.stringify(geojson), description || '', createdAt || new Date().toISOString());
    await gateway.disconnect();
    res.json({ ok: true, id });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.get('/api/landledger/:id', async (req, res) => {
  try {
    const { gateway, contract } = await getContract();
    const r = await contract.evaluateTransaction('Get', req.params.id);
    await gateway.disconnect();
    res.json(JSON.parse(r.toString()));
  } catch (e) { res.status(404).json({ error: e.message }); }
});

app.get('/api/landledger', async (_req, res) => {
  try {
    const { gateway, contract } = await getContract();
    const r = await contract.evaluateTransaction('GetAll');
    await gateway.disconnect();
    res.json(JSON.parse(r.toString()));
  } catch (e) { res.status(500).json({ error: e.message }); }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`API listening on ${PORT}`));
