#!/usr/bin/env bash
set -euo pipefail

###############################################
# Morgan-specific defaults (override if needed)
###############################################
FABRIC_SAMPLES_DIR="${FABRIC_SAMPLES_DIR:-$HOME/blockchain/fabric-samples}"
CC_SRC_PATH="${CC_SRC_PATH:-$HOME/landledger/chaincode/landledger}"
CHANNEL_NAME="${CHANNEL_NAME:-mychannel}"
CC_NAME="${CC_NAME:-landledger}"
CC_LANG="${CC_LANG:-go}"
CC_VERSION="${CC_VERSION:-1.0}"
CC_SEQUENCE="${CC_SEQUENCE:-1}"
CC_POLICY="${CC_POLICY:-OR('Org1MSP.peer','Org2MSP.peer')}"
LEAVE_RUNNING="${LEAVE_RUNNING:-true}"
# fresh | upgrade   (fresh tears down & recreates; upgrade reuses network)
REDEPLOY_MODE="${REDEPLOY_MODE:-fresh}"

###############################################
# Derived paths
###############################################
TEST_NETWORK_DIR="$FABRIC_SAMPLES_DIR/test-network"

###############################################
# Helpers
###############################################
fail() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1"; }
print_header() { echo -e "\n=============================================\n$*\n============================================="; }

# Be tolerant: pretty-print JSON if possible; otherwise echo raw
json_pretty() {
  if command -v jq >/dev/null 2>&1; then
    buf=$(cat)
    echo "$buf" | jq . 2>/dev/null || echo "$buf"
  else
    python3 - <<'PY'
import sys,json
s=sys.stdin.read()
try: print(json.dumps(json.loads(s), indent=2))
except Exception: print(s)
PY
  fi
}

# Quote any shell string as a single JSON string token (handles newlines/quotes)
Q() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -Rs .
  else
    python3 - <<'PY'
import json,sys; print(json.dumps(sys.stdin.read()))
PY
  fi
}

# Build ",\"a\",\"b\"" for plain string args
JARG() { local out=""; for a in "$@"; do out="${out},\"${a}\""; done; echo "$out"; }
# Build ",<json1>,<json2>" for tokens already valid JSON (output of Q)
JARG_JSON() { local out=""; for a in "$@"; do out="${out},${a}"; done; echo "$out"; }

###############################################
# Checks
###############################################
need docker; need bash; need awk; need sed
[ -d "$TEST_NETWORK_DIR" ] || fail "fabric-samples test-network not found at: $TEST_NETWORK_DIR"
[ -d "$CC_SRC_PATH" ] || fail "Chaincode path not found: $CC_SRC_PATH"

###############################################
# Network (fresh vs upgrade)
###############################################
pushd "$TEST_NETWORK_DIR" >/dev/null
if [[ "$REDEPLOY_MODE" == "fresh" ]]; then
  print_header "Recreating network & channel: $CHANNEL_NAME"
  ./network.sh down || true
  ./network.sh up createChannel -ca -c "$CHANNEL_NAME"
else
  print_header "Upgrade mode: reusing existing network/channel $CHANNEL_NAME"
fi

###############################################
# Deploy / upgrade chaincode
###############################################
print_header "Deploying chaincode '$CC_NAME' from $CC_SRC_PATH (version=$CC_VERSION sequence=$CC_SEQUENCE)"
./network.sh deployCC \
  -c "$CHANNEL_NAME" -ccn "$CC_NAME" -ccp "$CC_SRC_PATH" -ccl "$CC_LANG" \
  -ccv "$CC_VERSION" -ccs "$CC_SEQUENCE" -ccep "$CC_POLICY"

# Make peer CLI find core.yaml + binaries
export FABRIC_CFG_PATH="$TEST_NETWORK_DIR/../config"
[[ -f "$FABRIC_CFG_PATH/core.yaml" ]] || FABRIC_CFG_PATH="$FABRIC_SAMPLES_DIR/config"
export PATH="$FABRIC_SAMPLES_DIR/bin:$PATH"

# envVar.sh references these; we’re under set -u
export OVERRIDE_ORG=""
export CORE_PEER_TLS_ENABLED=true
export VERBOSE=false
set +u; . ./scripts/envVar.sh; set -u

# Convenience wrappers
use_org1() { setGlobals 1; }
use_org2() { setGlobals 2; }

ORDERER_CA="$TEST_NETWORK_DIR/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"
ORDERER_ADDR="localhost:7050"

INVOKE() {
  local org="$1"; shift
  local fcn="$1"; shift
  local args="$1"; shift || true
  local mode="invoke"
  [[ "${1:-}" == "--isQuery" ]] && mode="query"

  if [[ "$org" == "org1" ]]; then use_org1; else use_org2; fi

  local PEER_CONN_PARAMS=(--orderer "$ORDERER_ADDR" --tls --cafile "$ORDERER_CA" -C "$CHANNEL_NAME" -n "$CC_NAME")
  if [[ "$mode" == "invoke" ]]; then
    peer chaincode invoke "${PEER_CONN_PARAMS[@]}" -c "{\"Args\":[\"$fcn\"$args]}" --waitForEvent 2>/dev/null
  else
    peer chaincode query  "${PEER_CONN_PARAMS[@]}" -c "{\"Args\":[\"$fcn\"$args]}" 2>/dev/null
  fi
}

###############################################
# Test data
###############################################
PARCEL_ID="NG-ABJ-001"
TITLE_NO="NG-ABJ-001"
OWNER1="amaka@landledger.africa"
OWNER2="obi@landledger.africa"
COORDS_JSON='[{"lat":9.0000,"lng":7.3000},{"lat":9.0500,"lng":7.4000},{"lat":9.1000,"lng":7.3000},{"lat":9.0500,"lng":7.2000},{"lat":9.0000,"lng":7.3000}]'

# Multi-line JSON -> will be quoted via Q before sending
PARCEL_JSON=$(cat <<'JSON'
{
  "parcelId": "NG-ABJ-001",
  "titleNumber": "NG-ABJ-001",
  "owner": "amaka@landledger.africa",
  "coordinates": [
    {"lat":9.0,"lng":7.3},
    {"lat":9.05,"lng":7.4},
    {"lat":9.1,"lng":7.3},
    {"lat":9.05,"lng":7.2},
    {"lat":9.0,"lng":7.3}
  ],
  "areaSqKm": 12.34,
  "description": "Abuja FCT",
  "createdAt": "2025-08-14T00:00:00Z",
  "verified": false
}
JSON
)
PARCEL_ARG=$(Q "$PARCEL_JSON")
COORDS_ARG=$(Q "$COORDS_JSON")

###############################################
# Run function tests
###############################################
print_header "RegisterParcel"
INVOKE org1 RegisterParcel "$(JARG_JSON "$PARCEL_ARG")"

print_header "GetParcel"
INVOKE org1 GetParcel "$(JARG "$PARCEL_ID")" --isQuery | json_pretty

print_header "Exists"
INVOKE org1 Exists "$(JARG "$PARCEL_ID")" --isQuery

print_header "GetAllParcels"
INVOKE org1 GetAllParcels "" --isQuery | json_pretty

print_header "QueryByOwner OWNER1"
INVOKE org1 QueryByOwner "$(JARG "$OWNER1")" --isQuery | json_pretty

print_header "QueryByTitle"
INVOKE org1 QueryByTitle "$(JARG "$TITLE_NO")" --isQuery | json_pretty

print_header "UpdateDescription"
INVOKE org1 UpdateDescription "$(JARG "$PARCEL_ID" "Updated description: city center plot")"

print_header "UpdateGeometry"
INVOKE org1 UpdateGeometry "$(JARG_JSON "$(Q "$PARCEL_ID")" "$COORDS_ARG" "$(Q "15.5")")"

print_header "GetParcel after update"
INVOKE org1 GetParcel "$(JARG "$PARCEL_ID")" --isQuery | json_pretty

print_header "TransferOwner -> OWNER2"
INVOKE org1 TransferOwner "$(JARG "$PARCEL_ID" "$OWNER2")"

print_header "QueryByOwner OWNER2"
INVOKE org1 QueryByOwner "$(JARG "$OWNER2")" --isQuery | json_pretty

print_header "GetHistory"
INVOKE org1 GetHistory "$(JARG "$PARCEL_ID")" --isQuery | json_pretty

print_header "DeleteParcel"
INVOKE org1 DeleteParcel "$(JARG "$PARCEL_ID")"

print_header "Exists after delete"
INVOKE org1 Exists "$(JARG "$PARCEL_ID")" --isQuery

if [[ "$LEAVE_RUNNING" != "true" && "$REDEPLOY_MODE" == "fresh" ]]; then
  ./network.sh down
fi

popd >/dev/null
print_header "All done!"
