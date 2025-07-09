require('dotenv').config();
console.log('🔵 Environment variables loaded');

const express = require('express');
const cors = require('cors');
const { Gateway, Wallets } = require('fabric-network');
const path = require('path');
const fs = require('fs');

const app = express();
app.use(cors());
app.use(express.json());
console.log('🟢 Express middleware configured');

// Global error handlers
process.on('uncaughtException', err => {
  console.error('💥 Uncaught Exception:', err);
});
process.on('unhandledRejection', err => {
  console.error('💥 Unhandled Rejection:', err);
});

// Load connection profile
let ccp;
try {
  const ccpPath = path.resolve(__dirname, 'connection-org1.json');
  ccp = JSON.parse(fs.readFileSync(ccpPath, 'utf8'));
  console.log('🟢 Connection profile loaded successfully');
} catch (error) {
  console.error('🔴 Failed to load connection profile:', error);
  process.exit(1);
}

// Helper: Get contract from wallet and connection profile
async function getContract() {
  try {
    console.log('ℹ️  Initializing wallet...');
    const walletPath = path.join(__dirname, 'wallet');
    const wallet = await Wallets.newFileSystemWallet(walletPath);
    console.log(`ℹ️  Wallet path: ${walletPath}`);

    const identity = await wallet.get('appUser');
    if (!identity) {
      throw new Error('No identity "appUser" found in wallet');
    }
    console.log('🟢 Identity "appUser" found in wallet');

    const gateway = new Gateway();
    await gateway.connect(ccp, {
      wallet,
      identity: 'appUser',
      discovery: { enabled: true, asLocalhost: true }
    });

    const network = await gateway.getNetwork('mychannel');
    const contract = network.getContract('landledger');

    return { contract, gateway };
  } catch (error) {
    console.error('🔴 Gateway/contract setup error:', error);
    throw error;
  }
}

// 🔘 Register a land parcel
app.post('/api/landledger/register', async (req, res) => {
  console.log('ℹ️  POST /api/landledger/register received');
  try {
    const {
      parcelId, titleNumber, owner,
      coordinates, areaSqKm, description
    } = req.body;

    if (
      !parcelId || !titleNumber || !owner ||
      !coordinates || !Array.isArray(coordinates) ||
      typeof areaSqKm !== 'number' || !description
    ) {
      return res.status(400).json({ error: '❌ Missing or invalid fields in request body' });
    }

    console.log(`ℹ️  Creating parcel with ID: ${parcelId}`);

    const { contract, gateway } = await getContract();
    await contract.submitTransaction(
      'CreateLandRecord',
      parcelId,
      titleNumber,
      owner,
      JSON.stringify(coordinates),
      areaSqKm.toString(),
      description
    );

    await gateway.disconnect();
    console.log(`✅ Parcel ${parcelId} created successfully`);
    res.json({ success: true, message: '✅ Parcel created on blockchain.' });

  } catch (error) {
    console.error('❌ CreateLandRecord error:', error);
    res.status(500).json({ error: error.message });
  }
});

// 🔍 Retrieve a single parcel
app.get('/api/landledger/parcel/:id', async (req, res) => {
  const parcelId = req.params.id;
  console.log(`ℹ️  GET /api/landledger/parcel/${parcelId} received`);
  try {
    const { contract, gateway } = await getContract();
    const result = await contract.evaluateTransaction('ReadParcel', parcelId);
    await gateway.disconnect();

    res.json(JSON.parse(result.toString()));
  } catch (error) {
    console.error(`❌ ReadParcel error for ${parcelId}:`, error);
    res.status(404).json({ error: `Parcel ${parcelId} not found.` });
  }
});

// 📦 Get all parcel blocks (chain state)
app.get('/api/landledger/blocks', async (req, res) => {
  console.log('ℹ️  GET /api/landledger/blocks received');
  try {
    const { contract, gateway } = await getContract();
    const result = await contract.evaluateTransaction('GetAllParcels');
    await gateway.disconnect();

    res.json(JSON.parse(result.toString()));
  } catch (error) {
    console.error('❌ Failed to retrieve blockchain blocks:', error);
    res.status(500).json({ error: 'Parcel blocks not found' });
  }
});

// ✅ Health check
app.get('/api/health', (req, res) => {
  console.log('ℹ️  Health check requested');
  res.json({
    status: 'OK',
    message: 'Server is running',
    timestamp: new Date().toISOString()
  });
});

// 🌍 Start server
const PORT = 4000;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`🌍 Server running on http://0.0.0.0:${PORT}`);
  console.log('🔵 Available endpoints:');
  console.log('   - POST   /api/landledger/register');
  console.log('   - GET    /api/landledger/parcel/:id');
  console.log('   - GET    /api/landledger/blocks');
  console.log('   - GET    /api/health');
});
