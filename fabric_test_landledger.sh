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
# fresh | upgrade
REDEPLOY_MODE="${REDEPLOY_MODE:-fresh}"
# true -> auto bump seq/version when REDEPLOY_MODE=upgrade
AUTO_BUMP="${AUTO_BUMP:-true}"

# Which tests to run
RUN_PARCELS_TESTS="${RUN_PARCELS_TESTS:-true}"
RUN_PROJECT_PUBLIC_TESTS="${RUN_PROJECT_PUBLIC_TESTS:-true}"
RUN_PROJECT_PRIVATE_TESTS="${RUN_PROJECT_PRIVATE_TESTS:-true}"
RUN_METADATA_CHECK="${RUN_METADATA_CHECK:-true}"

# Contract names inside the chaincode package
PARCELS_CONTRACT="${PARCELS_CONTRACT:-LandLedgerContract}"
PROJECTS_CONTRACT="${PROJECTS_CONTRACT:-ProjectContract}"

###############################################
# API sync (Node SDK / pm2) — optional
###############################################
# Set SYNC_API=false to skip API syncing/restart
SYNC_API="${SYNC_API:-true}"
# Your API repo paths & process
API_DIR="${API_DIR:-$HOME/landledger/api}"
API_CONN_DIR="$API_DIR/connection"
API_CCP="$API_CONN_DIR/connection-org1.json"
WALLET_DIR="${WALLET_DIR:-$API_DIR/wallet}"
PM2_APP="${PM2_APP:-landledger-api}"
IDENTITY="${IDENTITY:-appUser}"
# Pass these to pm2 on restart
DISCOVERY_AS_LOCALHOST="${DISCOVERY_AS_LOCALHOST:-true}"
REUSE_GATEWAY="${REUSE_GATEWAY:-false}"

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

json_pretty() {
  if command -v jq >/dev/null 2>&1; then
    buf=$(cat); echo "$buf" | jq . 2>/dev/null || echo "$buf"
  else
    python3 - <<'PY'
import sys,json
s=sys.stdin.read()
try: print(json.dumps(json.loads(s), indent=2))
except Exception: print(s)
PY
  fi
}

# Quote a raw string as JSON value
Q() {
  if command -v jq >/dev/null 2>&1; then printf '%s' "$1" | jq -Rs .; else
  python3 - <<'PY'
import json,sys; print(json.dumps(sys.stdin.read()))
PY
  fi
}
# Build "Args" payload pieces from raw strings
JARG() { local out=""; for a in "$@"; do out="${out},\"${a}\""; done; echo "$out"; }
# Build "Args" payload pieces where some are already JSON (e.g., Q or raw arrays/objects)
JARG_JSON() { local out=""; for a in "$@"; do out="${out},${a}"; done; echo "$out"; }

###############################################
# Checks
###############################################
need docker; need awk; need sed
[ -d "$TEST_NETWORK_DIR" ] || fail "fabric-samples test-network not found at: $TEST_NETWORK_DIR"
[ -d "$CC_SRC_PATH" ] || fail "Chaincode path not found: $CC_SRC_PATH"

if [[ "$SYNC_API" == "true" ]]; then
  need node
  # need pm2
  mkdir -p "$API_CONN_DIR" "$WALLET_DIR"
fi

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
# Auto bump seq/version (upgrade)
###############################################
if [[ "$REDEPLOY_MODE" == "upgrade" && "$AUTO_BUMP" == "true" ]]; then
  print_header "Auto-bumping chaincode sequence/version"
  CURRENT_SEQ=$(./network.sh chaincodeQueryCommitted -c "$CHANNEL_NAME" -ccn "$CC_NAME" 2>/dev/null \
    | awk -F'Sequence: ' 'NF>1{print $2}' | awk '{print $1}' | tr -d '\r' || true)
  if [[ -n "${CURRENT_SEQ:-}" ]]; then
    CC_SEQUENCE="$(( CURRENT_SEQ + 1 ))"
    if [[ "$CC_VERSION" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
      major="${BASH_REMATCH[1]}"; minor="${BASH_REMATCH[2]}"
      CC_VERSION="${major}.$(( minor + 1 ))"
    else
      ts=$(date +%s)
      CC_VERSION="${CC_VERSION}-rev${ts}"
    fi
    echo "-> New CC_VERSION=$CC_VERSION CC_SEQUENCE=$CC_SEQUENCE"
  else
    echo "Could not determine current sequence. Using provided CC_VERSION=$CC_VERSION CC_SEQUENCE=$CC_SEQUENCE"
  fi
fi

###############################################
# Deploy / upgrade chaincode
###############################################
print_header "Deploying chaincode '$CC_NAME' from $CC_SRC_PATH (version=$CC_VERSION sequence=$CC_SEQUENCE)"
./network.sh deployCC \
  -c "$CHANNEL_NAME" -ccn "$CC_NAME" -ccp "$CC_SRC_PATH" -ccl "$CC_LANG" \
  -ccv "$CC_VERSION" -ccs "$CC_SEQUENCE" -ccep "$CC_POLICY"

###############################################
# CLI env (peer, core.yaml, binaries)
###############################################
export FABRIC_CFG_PATH="$TEST_NETWORK_DIR/../config"
if [[ ! -f "$FABRIC_CFG_PATH/core.yaml" ]]; then
  FABRIC_CFG_PATH="$FABRIC_SAMPLES_DIR/config"
fi
[[ -f "$FABRIC_CFG_PATH/core.yaml" ]] || fail "core.yaml not found. Set FABRIC_CFG_PATH correctly."
export PATH="$FABRIC_SAMPLES_DIR/bin:$PATH"

# envVar.sh uses these; we’re under set -u
export OVERRIDE_ORG=""
export CORE_PEER_TLS_ENABLED=true
export VERBOSE=false
set +u; . ./scripts/envVar.sh; set -u

use_org1() { setGlobals 1; }
use_org2() { setGlobals 2; }

ORDERER_CA="$TEST_NETWORK_DIR/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"
ORDERER_ADDR="localhost:7050"

INVOKE() {
  local org="$1"; shift
  local fcn="$1"; shift
  local args="${1:-}"; shift || true
  local mode="invoke"
  [[ "${1:-}" == "--isQuery" ]] && mode="query"

  if [[ "$org" == "org1" ]]; then use_org1; else use_org2; fi

  local PEER_CONN_PARAMS=(--orderer "$ORDERER_ADDR" --tls --cafile "$ORDERER_CA" -C "$CHANNEL_NAME" -n "$CC_NAME")
  local payload="{\"Args\":[\"$fcn\"$args]}"

  set +e
  if [[ "$mode" == "invoke" ]]; then
    peer chaincode invoke "${PEER_CONN_PARAMS[@]}" -c "$payload" --waitForEvent
  else
    peer chaincode query  "${PEER_CONN_PARAMS[@]}" -c "$payload"
  fi
  local rc=$?
  set -e

  if (( rc != 0 )); then
    echo "❌ Chaincode $mode failed for: $fcn" >&2
    # show most recent chaincode container logs (org1 + org2 if present)
    for n in $(docker ps --format '{{.Names}}' | grep -E 'dev-peer0\.org(1|2)\.example\.com-.*'"$CC_NAME"'_'$CC_VERSION | head -n 2); do
      echo "---- docker logs $n (tail) ----" >&2
      docker logs --tail=200 "$n" >&2 || true
    done
    return $rc
  fi
}

###############################################
# Generate a fresh Org1 connection profile for the API
# - Uses absolute file PATHs to TLS CAs (not embedded PEM)
# - Adds proper channels->mychannel mapping and orderer
###############################################
write_api_connection_profile() {
  local ORG1_TLS_CA="$TEST_NETWORK_DIR/organizations/peerOrganizations/org1.example.com/tlsca/tlsca.org1.example.com-cert.pem"
  local ORDERER_TLS_CA="$TEST_NETWORK_DIR/organizations/ordererOrganizations/example.com/tlsca/tlsca.example.com-cert.pem"
  local CA_ORG1_CERT="$TEST_NETWORK_DIR/organizations/peerOrganizations/org1.example.com/ca/ca.org1.example.com-cert.pem"
  [[ -f "$ORG1_TLS_CA" && -f "$ORDERER_TLS_CA" && -f "$CA_ORG1_CERT" ]] || \
    fail "Missing CA files. Did you run test-network with -ca? Check $TEST_NETWORK_DIR"

  # Backup existing profile if present
  if [[ -f "$API_CCP" ]]; then
    cp -a "$API_CCP" "${API_CCP}.bak.$(date +%s)" || true
  fi

  cat >"$API_CCP" <<JSON
{
  "name": "test-network-org1",
  "version": "1.0.0",
  "client": {
    "organization": "Org1",
    "connection": { "timeout": { "peer": { "endorser": "300" } } }
  },
  "organizations": {
    "Org1": {
      "mspid": "Org1MSP",
      "peers": ["peer0.org1.example.com"],
      "certificateAuthorities": ["ca.org1.example.com"]
    }
  },
  "channels": {
    "mychannel": {
      "orderers": ["orderer.example.com"],
      "peers": {
        "peer0.org1.example.com": {
          "endorsingPeer": true,
          "chaincodeQuery": true,
          "ledgerQuery": true,
          "eventSource": true
        }
      }
    }
  },
  "peers": {
    "peer0.org1.example.com": {
      "url": "grpcs://localhost:7051",
      "tlsCACerts": { "path": "$ORG1_TLS_CA" },
      "grpcOptions": {
        "ssl-target-name-override": "peer0.org1.example.com",
        "hostnameOverride": "peer0.org1.example.com"
      }
    }
  },
  "orderers": {
    "orderer.example.com": {
      "url": "grpcs://localhost:7050",
      "tlsCACerts": { "path": "$ORDERER_TLS_CA" },
      "grpcOptions": {
        "ssl-target-name-override": "orderer.example.com",
        "hostnameOverride": "orderer.example.com"
      }
    }
  },
  "certificateAuthorities": {
    "ca.org1.example.com": {
      "url": "https://localhost:7054",
      "caName": "ca-org1",
      "tlsCACerts": { "path": "$CA_ORG1_CERT" },
      "httpOptions": { "verify": false }
    }
  }
}
JSON
  echo "✓ Wrote API connection profile: $API_CCP"
}

###############################################
# Ensure wallet identities exist (admin, appUser)
###############################################
ensure_wallet_identities() {
  pushd "$API_DIR" >/dev/null
    export CCP_PATH="$API_CCP"
    export WALLET_DIR="$WALLET_DIR"
    export IDENTITY="$IDENTITY"
    if [[ ! -f "$WALLET_DIR/admin.id" ]]; then
      node enrollAdmin.js || fail "enrollAdmin.js failed"
    fi
    if [[ ! -f "$WALLET_DIR/$IDENTITY.id" ]]; then
      node registerUser.js || fail "registerUser.js failed"
    fi
  popd >/dev/null
  echo "✓ Wallet ready at: $WALLET_DIR"
}

###############################################
# Restart pm2 API with fresh env
###############################################
restart_api_pm2() {
  export CCP_PATH="$API_CCP"
  export WALLET_DIR="$WALLET_DIR"
  export CHANNEL="$CHANNEL_NAME"
  export CC_NAME="$CC_NAME"
  export IDENTITY="$IDENTITY"
  export DISCOVERY_AS_LOCALHOST="$DISCOVERY_AS_LOCALHOST"
  export REUSE_GATEWAY="$REUSE_GATEWAY"
  pm2 restart "$PM2_APP" --update-env
  echo "✓ Restarted pm2 app: $PM2_APP"
}

###############################################
# Test data (PARCELS)
###############################################
PARCEL_ID="NG-ABJ-001"
TITLE_NO="NG-ABJ-001"
OWNER1="amaka@landledger.africa"
OWNER2="obi@landledger.africa"
COORDS_JSON='[{"lat":9.0000,"lng":7.3000},{"lat":9.0500,"lng":7.4000},{"lat":9.1000,"lng":7.3000},{"lat":9.0500,"lng":7.2000},{"lat":9.0000,"lng":7.3000}]'

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
# Test data (PROJECTS)
###############################################
PROJECT_ID="PRJ-1"
PROJECT_PUBLIC_JSON=$(cat <<JSON
{
  "projectId":"$PROJECT_ID",
  "parcelId":"$PARCEL_ID",
  "owner":"$OWNER1",
  "type":"public",
  "goal":50000,
  "requiredVotes":100,
  "amountPerVote":500,
  "description":"Community borehole"
}
JSON
)
PROJECT_ARG=$(Q "$PROJECT_PUBLIC_JSON")

# Private project with milestones
PROJECT_PRIV_ID="PRJ-2"
PROJECT_PRIVATE_JSON=$(cat <<JSON
{
  "projectId":"$PROJECT_PRIV_ID",
  "parcelId":"$PARCEL_ID",
  "owner":"$OWNER2",
  "type":"private",
  "description":"Estate perimeter fence"
}
JSON
)
PROJECT_PRIV_ARG=$(Q "$PROJECT_PRIVATE_JSON")

# Milestones config (keep in one place)
M1_LABEL="Mobilization"; M1_AMT="10000"
M2_LABEL="Materials";    M2_AMT="15000"
M3_LABEL="Completion";   M3_AMT="20000"

###############################################
# Optional: Metadata check (schema sanity)
###############################################
if [[ "$RUN_METADATA_CHECK" == "true" ]]; then
  print_header "GetMetadata (sanity check)"
  INVOKE org1 "org.hyperledger.fabric:GetMetadata" "" --isQuery | json_pretty
fi

###############################################
# Run PARCEL tests (LandLedgerContract)
###############################################
if [[ "$RUN_PARCELS_TESTS" == "true" ]]; then
  print_header "RegisterParcel"
  INVOKE org1 "${PARCELS_CONTRACT}:RegisterParcel" "$(JARG_JSON "$PARCEL_ARG")"

  print_header "GetParcel"
  INVOKE org1 "${PARCELS_CONTRACT}:GetParcel" "$(JARG "$PARCEL_ID")" --isQuery | json_pretty

  print_header "Exists"
  INVOKE org1 "${PARCELS_CONTRACT}:Exists" "$(JARG "$PARCEL_ID")" --isQuery

  print_header "GetAllParcels"
  INVOKE org1 "${PARCELS_CONTRACT}:GetAllParcels" "" --isQuery | json_pretty

  print_header "QueryByOwner OWNER1"
  INVOKE org1 "${PARCELS_CONTRACT}:QueryByOwner" "$(JARG "$OWNER1")" --isQuery | json_pretty

  print_header "QueryByTitle"
  INVOKE org1 "${PARCELS_CONTRACT}:QueryByTitle" "$(JARG "$TITLE_NO")" --isQuery | json_pretty

  print_header "UpdateDescription"
  INVOKE org1 "${PARCELS_CONTRACT}:UpdateDescription" "$(JARG "$PARCEL_ID" "Updated description: city center plot")"

  print_header "UpdateGeometry"
  INVOKE org1 "${PARCELS_CONTRACT}:UpdateGeometry" "$(JARG_JSON "$(Q "$PARCEL_ID")" "$COORDS_ARG" "$(Q "15.5")")"

  print_header "GetParcel after update"
  INVOKE org1 "${PARCELS_CONTRACT}:GetParcel" "$(JARG "$PARCEL_ID")" --isQuery | json_pretty

  print_header "TransferOwner -> OWNER2"
  INVOKE org1 "${PARCELS_CONTRACT}:TransferOwner" "$(JARG "$PARCEL_ID" "$OWNER2")"

  print_header "QueryByOwner OWNER2"
  INVOKE org1 "${PARCELS_CONTRACT}:QueryByOwner" "$(JARG "$OWNER2")" --isQuery | json_pretty

  print_header "GetHistory"
  INVOKE org1 "${PARCELS_CONTRACT}:GetHistory" "$(JARG "$PARCEL_ID")" --isQuery | json_pretty
fi

###############################################
# Run PROJECT tests (public)
###############################################
if [[ "$RUN_PROJECT_PUBLIC_TESTS" == "true" ]]; then
  print_header "CreateProject (public)"
  INVOKE org1 "${PROJECTS_CONTRACT}:CreateProject" "$(JARG_JSON "$PROJECT_ARG")"

  print_header "GetProject (public)"
  INVOKE org1 "${PROJECTS_CONTRACT}:GetProject" "$(JARG "$PROJECT_ID")" --isQuery | json_pretty

  print_header "ListProjectsByParcel"
  INVOKE org1 "${PROJECTS_CONTRACT}:ListProjectsByParcel" "$(JARG "$PARCEL_ID")" --isQuery | json_pretty

  print_header "ListProjectsByOwner OWNER1"
  INVOKE org1 "${PROJECTS_CONTRACT}:ListProjectsByOwner" "$(JARG "$OWNER1")" --isQuery | json_pretty

  print_header "Vote (Org1 peer voter uid X)"
  INVOKE org1 "${PROJECTS_CONTRACT}:Vote" "$(JARG "$PROJECT_ID" "uid-voter-1")"

  print_header "Fund (+2000)"
  INVOKE org1 "${PROJECTS_CONTRACT}:Fund" "$(JARG "$PROJECT_ID" "2000")"

  print_header "UpdateProjectStatus -> Active (no-op for public)"
  INVOKE org1 "${PROJECTS_CONTRACT}:UpdateProjectStatus" "$(JARG "$PROJECT_ID" "Active")"

  print_header "GetProject (after vote/fund)"
  INVOKE org1 "${PROJECTS_CONTRACT}:GetProject" "$(JARG "$PROJECT_ID")" --isQuery | json_pretty

  print_header "GetProjectHistory (public)"
  INVOKE org1 "${PROJECTS_CONTRACT}:GetProjectHistory" "$(JARG "$PROJECT_ID")" --isQuery | json_pretty
fi

###############################################
# Run PROJECT tests (private + milestones)
###############################################
if [[ "$RUN_PROJECT_PRIVATE_TESTS" == "true" ]]; then
  print_header "CreateProject (private)"
  INVOKE org1 "${PROJECTS_CONTRACT}:CreateProject" "$(JARG_JSON "$PROJECT_PRIV_ARG")"

  print_header "SetContractor"
  INVOKE org1 "${PROJECTS_CONTRACT}:SetContractor" "$(JARG "$PROJECT_PRIV_ID" "buildit@contractors.africa")"

  print_header "AddMilestone #1 ($M1_LABEL)"
  INVOKE org1 "${PROJECTS_CONTRACT}:AddMilestone" "$(JARG "$PROJECT_PRIV_ID" "$M1_LABEL" "$M1_AMT")"

  print_header "AddMilestone #2 ($M2_LABEL)"
  INVOKE org1 "${PROJECTS_CONTRACT}:AddMilestone" "$(JARG "$PROJECT_PRIV_ID" "$M2_LABEL" "$M2_AMT")"

  print_header "AddMilestone #3 ($M3_LABEL)"
  INVOKE org1 "${PROJECTS_CONTRACT}:AddMilestone" "$(JARG "$PROJECT_PRIV_ID" "$M3_LABEL" "$M3_AMT")"

  # >>> fund before releasing Materials (needs 15000) <<<
  print_header "Fund private (+$M2_AMT for $M2_LABEL)"
  INVOKE org1 "${PROJECTS_CONTRACT}:Fund" "$(JARG "$PROJECT_PRIV_ID" "$M2_AMT")"

  # Release by LABEL to avoid index confusion
  print_header "ReleaseMilestone ($M2_LABEL)"
  INVOKE org1 "${PROJECTS_CONTRACT}:ReleaseMilestone" "$(JARG "$PROJECT_PRIV_ID" "$M2_LABEL")"

  print_header "GetProject (private)"
  INVOKE org1 "${PROJECTS_CONTRACT}:GetProject" "$(JARG "$PROJECT_PRIV_ID")" --isQuery | json_pretty

  print_header "ListProjectsByOwner OWNER2"
  INVOKE org1 "${PROJECTS_CONTRACT}:ListProjectsByOwner" "$(JARG "$OWNER2")" --isQuery | json_pretty

  print_header "GetProjectHistory (private)"
  INVOKE org1 "${PROJECTS_CONTRACT}:GetProjectHistory" "$(JARG "$PROJECT_PRIV_ID")" --isQuery | json_pretty

  print_header "DeleteProject (private)"
  INVOKE org1 "${PROJECTS_CONTRACT}:DeleteProject" "$(JARG "$PROJECT_PRIV_ID")"
fi

###############################################
# Cleanup: delete the public project & parcel
###############################################
if [[ "$RUN_PROJECT_PUBLIC_TESTS" == "true" ]]; then
  print_header "DeleteProject (public)"
  INVOKE org1 "${PROJECTS_CONTRACT}:DeleteProject" "$(JARG "$PROJECT_ID")"
fi

if [[ "$RUN_PARCELS_TESTS" == "true" ]]; then
  print_header "DeleteParcel"
  INVOKE org1 "${PARCELS_CONTRACT}:DeleteParcel" "$(JARG "$PARCEL_ID")"

  print_header "Exists after delete"
  INVOKE org1 "${PARCELS_CONTRACT}:Exists" "$(JARG "$PARCEL_ID")" --isQuery
fi

# === Sync API (connection profile + wallet + pm2 restart) ===
if [[ "$SYNC_API" == "true" ]]; then
  print_header "Sync API: connection profile, wallet, and pm2 restart"
  write_api_connection_profile
  ensure_wallet_identities
  # restart_api_pm2
  echo ""
  echo "NOTE:"
  echo "  - Connection profile uses TLS CA *paths* and includes channels->mychannel."
  echo "  - Wallet contains 'admin' and '$IDENTITY'."
  echo "  - pm2 restarted with REUSE_GATEWAY=$REUSE_GATEWAY (recommended=false while stabilizing)."
  echo ""
fi

if [[ "$LEAVE_RUNNING" != "true" && "$REDEPLOY_MODE" == "fresh" ]]; then
  ./network.sh down
fi

popd >/dev/null
print_header "All done!"
