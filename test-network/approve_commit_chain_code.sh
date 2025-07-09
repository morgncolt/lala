#!/bin/bash

set -e

CC_NAME="landledger"
CC_VERSION="1.0"
CC_LABEL="landledger_1.0"
CC_SEQUENCE="1"
CC_PACKAGE_ID=""

# Set paths
export FABRIC_CFG_PATH=$PWD/../config
CHAINCODE_PACKAGE=../chaincode/landledger/go/landledger.tar.gz

echo "👉 Extracting Package ID..."
peer lifecycle chaincode queryinstalled > log.txt
CC_PACKAGE_ID=$(sed -n "/${CC_LABEL}/{s/^Package ID: //; s/, Label:.*$//; p;}" log.txt)
echo "📦 Package ID: $CC_PACKAGE_ID"

echo "🔐 Approving chaincode for Org1..."
export CORE_PEER_LOCALMSPID="Org1MSP"
export CORE_PEER_MSPCONFIGPATH=$PWD/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_ADDRESS=localhost:7051
export CORE_PEER_TLS_ROOTCERT_FILE=$PWD/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt

peer lifecycle chaincode approveformyorg -o localhost:7050 \
  --ordererTLSHostnameOverride orderer.example.com \
  --tls --cafile $PWD/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem \
  --channelID mychannel --name $CC_NAME \
  --version $CC_VERSION --package-id $CC_PACKAGE_ID --sequence $CC_SEQUENCE

echo "🔐 Approving chaincode for Org2..."
export CORE_PEER_LOCALMSPID="Org2MSP"
export CORE_PEER_MSPCONFIGPATH=$PWD/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
export CORE_PEER_ADDRESS=localhost:9051
export CORE_PEER_TLS_ROOTCERT_FILE=$PWD/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt

peer lifecycle chaincode approveformyorg -o localhost:7050 \
  --ordererTLSHostnameOverride orderer.example.com \
  --tls --cafile $PWD/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem \
  --channelID mychannel --name $CC_NAME \
  --version $CC_VERSION --package-id $CC_PACKAGE_ID --sequence $CC_SEQUENCE

echo "🧾 Committing chaincode definition..."
peer lifecycle chaincode commit -o localhost:7050 \
  --ordererTLSHostnameOverride orderer.example.com \
  --tls --cafile $PWD/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem \
  --channelID mychannel --name $CC_NAME \
  --peerAddresses localhost:7051 --tlsRootCertFiles $PWD/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt \
  --peerAddresses localhost:9051 --tlsRootCertFiles $PWD/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt \
  --version $CC_VERSION --sequence $CC_SEQUENCE

echo "✅ Chaincode approved and committed by Org1 and Org2."

