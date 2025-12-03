// scripts/show-identity.js
const fs = require('fs');
const path = require('path');
const { Wallets } = require('fabric-network');
const { Certificate } = require('@fidm/x509'); // npm i @fidm/x509 (dev dep is fine)

(async () => {
  const wallet = await Wallets.newFileSystemWallet(path.join(__dirname, '../wallet'));
  const id = await wallet.get(process.env.LL_ID || 'appUser');
  if (!id) { console.error('Identity not found in wallet'); process.exit(1); }
  console.log('Label:', process.env.LL_ID || 'appUser');
  console.log('MSP ID:', id.mspId);
  const cert = Certificate.fromPEM(Buffer.from(id.credentials.certificate));
  console.log('Subject CN:', cert.subject.commonName);
  console.log('Issuer CN:', cert.issuer.commonName);
  console.log('Not Before:', cert.validFrom);
  console.log('Not After :', cert.validTo);
})();
