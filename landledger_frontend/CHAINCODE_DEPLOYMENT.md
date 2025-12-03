# Chaincode Redeployment Instructions

The chaincode has been updated to support property addresses. Follow these steps to redeploy the updated chaincode to your Hyperledger Fabric network.

## What Changed

### 1. Chaincode Updates (Go)
**File**: `/home/morgan/landledger/chaincode/landledger/types.go`

Added two new structs and fields:
- **New Struct**: `PropertyAddress` - Structured address with optional fields for international support
- **LandParcel Updates**:
  - Added `Address *PropertyAddress` - Full structured address object
  - Added `AddressString string` - Formatted display string

### 2. Flutter App Updates
**File**: `lib/map_screen.dart`

Updated `saveToBlockchainSilent()` to send address data:
```dart
"address": address?.toJson(),
"addressString": address?.toDisplayString() ?? '',
```

## Redeployment Steps

### Option 1: Using Your Existing Deployment Script

If you have a Fabric network deployment script, run it from WSL:

```bash
wsl -d Ubuntu-20.04 bash -c "cd /home/morgan/landledger && ./fabric_test_landledger.sh"
```

### Option 2: Manual Redeployment

Run these commands in WSL (Ubuntu-20.04):

```bash
# 1. Navigate to your landledger directory
cd /home/morgan/landledger

# 2. Package the updated chaincode
peer lifecycle chaincode package landledger.tar.gz \
  --path ./chaincode/landledger \
  --lang golang \
  --label landledger_2.0

# 3. Install on your peer
peer lifecycle chaincode install landledger.tar.gz

# 4. Get the package ID (save this!)
peer lifecycle chaincode queryinstalled

# 5. Approve the chaincode for your org (replace PACKAGE_ID with the output from step 4)
export PACKAGE_ID=<your-package-id>
peer lifecycle chaincode approveformyorg \
  --channelID mychannel \
  --name landledger \
  --version 2.0 \
  --package-id $PACKAGE_ID \
  --sequence 2 \
  --orderer localhost:7050 \
  --tls \
  --cafile /path/to/orderer/ca.crt

# 6. Commit the chaincode definition
peer lifecycle chaincode commit \
  --channelID mychannel \
  --name landledger \
  --version 2.0 \
  --sequence 2 \
  --orderer localhost:7050 \
  --tls \
  --cafile /path/to/orderer/ca.crt

# 7. Verify deployment
peer lifecycle chaincode querycommitted \
  --channelID mychannel \
  --name landledger
```

### Option 3: Test Network Quick Redeploy

If using Fabric test-network:

```bash
cd /home/morgan/fabric-samples/test-network

# Redeploy with updated chaincode
./network.sh deployCC \
  -ccn landledger \
  -ccp /home/morgan/landledger/chaincode/landledger \
  -ccl go \
  -ccv 2.0 \
  -ccs 2
```

## Verification

After redeployment, verify the address fields are being stored:

### 1. Test via Flutter App
- Create a new property with address information
- Check the blockchain explorer or query the ledger

### 2. Test via API
```bash
# Create a test parcel with address
curl -X POST http://localhost:4000/api/landledger/polygons \
  -H "Content-Type: application/json" \
  -d '{
    "uid": "test-user",
    "polygon": {
      "parcelId": "TEST-001",
      "titleNumber": "TEST-001",
      "owner": "0x1234...",
      "coordinates": [{"lat": 6.5244, "lng": 3.3792}],
      "areaSqKm": 0.5,
      "description": "Test property",
      "address": {
        "city": "Lagos",
        "country": "Nigeria"
      },
      "addressString": "Lagos, Nigeria"
    }
  }'

# Query the parcel to verify address was stored
curl http://localhost:4000/api/landledger/TEST-001?uid=test-user
```

### 3. Expected Response
The response should now include:
```json
{
  "parcelId": "TEST-001",
  "address": {
    "city": "Lagos",
    "country": "Nigeria"
  },
  "addressString": "Lagos, Nigeria",
  ...
}
```

## Troubleshooting

### Error: "Chaincode already exists"
- Increment the version number (e.g., 2.1, 2.2)
- Increment the sequence number in the approve/commit commands

### Error: "Package not found"
- Ensure the chaincode was packaged successfully
- Check the PACKAGE_ID matches the output from `queryinstalled`

### Error: "Endorsement policy not met"
- Ensure all required organizations have approved the chaincode
- Check that you're using the correct MSP IDs

## Rollback

If you need to rollback to the previous version:

```bash
# The backup is saved at:
/home/morgan/landledger/chaincode/landledger/types.go.backup

# Restore it:
cd /home/morgan/landledger/chaincode/landledger
cp types.go.backup types.go

# Then redeploy following the steps above
```

## Notes

- **Backward Compatibility**: The new fields use `omitempty` JSON tags, so old parcels without addresses will still work
- **Optional Fields**: All address fields are optional to support both formal address systems (USA) and informal systems (many African countries)
- **Existing Data**: Properties created before this update will not have address data, but will continue to function normally
- **Flutter App**: The app automatically sends address data for all new properties

## Next Steps

After successful redeployment:
1. Restart the LandLedger API server to ensure it uses the updated chaincode
2. Test creating a new property in the Flutter app
3. Verify the blockchain display shows the address information
4. Check that the LandLedger screen displays addresses correctly

For questions or issues, check the chaincode logs:
```bash
docker logs -f <peer-container-name>
```
