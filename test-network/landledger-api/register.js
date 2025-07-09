// registerUser.js
const { Gateway, Wallets } = require('fabric-network');
const FabricCAServices = require('fabric-ca-client');
const path = require('path');
const fs = require('fs');

async function main() {
  try {
    const ccpPath = path.resolve(__dirname, 'connection-org1.json');
    const ccp = JSON.parse(fs.readFileSync(ccpPath, 'utf8'));

    const caURL = ccp.certificateAuthorities['ca.org1.example.com'].url;
    const ca = new FabricCAServices(caURL);

    const walletPath = path.join(__dirname, 'wallet');
    const wallet = await Wallets.newFileSystemWallet(walletPath);
    console.log(`🔐 Wallet path: ${walletPath}`);

    // Check if appUser already exists
    const userExists = await wallet.get('appUser');
    if (userExists) {
      console.log('✅ appUser already enrolled');
      return;
    }

    // Check if admin exists
    const adminExists = await wallet.get('admin');
    if (!adminExists) {
      console.log('⚠️ Admin identity not found in wallet. Enroll admin first.');
      return;
    }

    // Build admin identity from wallet
    const provider = wallet.getProviderRegistry().getProvider(adminExists.type);
    const adminUser = await provider.getUserContext(adminExists, 'admin');

    // Register and enroll appUser
    const secret = await ca.register({
      affiliation: 'org1.department1',
      enrollmentID: 'appUser',
      role: 'client'
    }, adminUser);

    const enrollment = await ca.enroll({
      enrollmentID: 'appUser',
      enrollmentSecret: secret
    });

    const x509Identity = {
      credentials: {
        certificate: enrollment.certificate,
        privateKey: enrollment.key.toBytes()
      },
      mspId: 'Org1MSP',
      type: 'X.509'
    };

    await wallet.put('appUser', x509Identity);
    console.log('✅ Successfully enrolled appUser and added to wallet');
  } catch (error) {
    console.error('❌ Failed to register appUser:', error);
  }
}

main();

