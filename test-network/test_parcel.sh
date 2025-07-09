#!/bin/bash

# Set paths
export PATH=${HOME}/fabric-samples/bin:$PATH
export FABRIC_CFG_PATH=${HOME}/fabric-samples/config

# TLS and identity config
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID="Org1MSP"
export CORE_PEER_MSPCONFIGPATH=${HOME}/fabric-samples/test-network/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_ADDRESS=localhost:7051
export CORE_PEER_TLS_ROOTCERT_FILE=${HOME}/fabric-samples/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt

# Additional peer certs
export ORDERER_CA=$HOME/fabric-samples/test-network/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem
export PEER0_ORG1_CA=$HOME/fabric-samples/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
export PEER0_ORG2_CA=$HOME/fabric-samples/test-network/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt

# Generate a unique Parcel ID
UUID=$(date +%s)
PARCEL_ID="LL-TEST-$UUID"
TITLE="TN-$UUID"
OWNER="test_wallet_$UUID"
COORDS="[{\\\"lat\\\":37.421,\\\"lng\\\":-122.084}]"
AREA="3.1"
DESC="Automated parcel test $UUID"

echo "👉 Creating parcel: $PARCEL_ID"

# Invoke transaction (write)
peer chaincode invoke -o localhost:7050 \
  --ordererTLSHostnameOverride orderer.example.com \
  --tls \
  --cafile $ORDERER_CA \
  --peerAddresses localhost:7051 \
  --tlsRootCertFiles $PEER0_ORG1_CA \
  --peerAddresses localhost:9051 \
  --tlsRootCertFiles $PEER0_ORG2_CA \
  -C mychannel -n landledger \
  -c "{\"function\":\"CreateParcel\",\"Args\":[\"$PARCEL_ID\",\"$TITLE\",\"$OWNER\",\"$COORDS\",\"$AREA\",\"$DESC\"]}"

# Wait for transaction to commit
echo "⏳ Waiting for block commit..."
sleep 5

# Query transaction (read)
echo "🔍 Querying parcel: $PARCEL_ID"
peer chaincode query -C mychannel -n landledger \
  -c "{\"function\":\"ReadParcel\",\"Args\":[\"$PARCEL_ID\"]}"

