// enrollAdmin.js

'use strict';

const FabricCAServices = require('fabric-ca-client');
const { Wallets } = require('fabric-network');
const path = require('path');
const fs = require('fs');

async function main() {
  try {
    // Step 1: Load the network configuration (connection profile)
    const ccpPath = path.resolve(__dirname, 'connection-org1.json');
    const ccp = JSON.parse(fs.readFileSync(ccpPath, 'utf8'));

    // Step 2: Create a new CA client for interacting with the CA
    const caInfo = ccp.certificateAuthorities['ca.org1.example.com'];
    const caTLSCACerts = caInfo.tlsCACerts.pem;
    const ca = new FabricCAServices(caInfo.url, { trustedRoots: caTLSCACerts, verify: false });

    // Step 3: Create a new file system–based wallet for managing identities
    const walletPath = path.join(__dirname, 'wallet');
    const wallet = await Wallets.newFileSystemWallet(walletPath);
    console.log(`🔐 Wallet path: ${walletPath}`);

    // Step 4: Check to see if the admin identity already exists in the wallet
    const identity = await wallet.get('admin');
    if (identity) {
      console.log('✅ Admin identity already exists in the wallet.');
      return;
    }

    // Step 5: Enroll the admin user with the CA
    const enrollment = await ca.enroll({
      enrollmentID: 'admin',
      enrollmentSecret: 'adminpw',
    });

    const x509Identity = {
      credentials: {
        certificate: enrollment.certificate,
        privateKey: enrollment.key.toBytes(),
      },
      mspId: 'Org1MSP',
      type: 'X.509',
    };

    // Step 6: Import the identity into the wallet
    await wallet.put('admin', x509Identity);
    console.log('✅ Successfully enrolled admin and imported it into the wallet.');

  } catch (error) {
    console.error(`❌ Failed to enroll admin: ${error}`);
    process.exit(1);
  }
}

main();
