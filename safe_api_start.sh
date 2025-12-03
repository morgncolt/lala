#!/usr/bin/env bash
# safe_api_start.sh — start Fabric containers, ensure CC is committed (skip re-deploy if already true),
# write a connection profile, ensure wallet identities, launch the API, then health-check it.
set -Eeuo pipefail

###############################################
# Tunables (override via env)
###############################################
EXPECTED_BLOCKS="${EXPECTED_BLOCKS:-4}"
API_BASE="${API_BASE:-http://localhost:4000}"
START_SCRIPT="${START_SCRIPT:-$HOME/landledger/start_landledger_api.sh}"
MAX_WAIT_SEC="${MAX_WAIT_SEC:-90}"

# Fabric/test-network + chaincode
FABRIC_SAMPLES_DIR="${FABRIC_SAMPLES_DIR:-$HOME/blockchain/fabric-samples}"
TEST_NET="${TEST_NET:-$FABRIC_SAMPLES_DIR/test-network}"
CC_NAME="${CC_NAME:-landledger}"
CHANNEL_NAME="${CHANNEL_NAME:-mychannel}"
CC_SRC_PATH="${CC_SRC_PATH:-$HOME/landledger/chaincode/landledger}"
CC_LANG="${CC_LANG:-go}"
CC_VERSION="${CC_VERSION:-1.1}"
CC_SEQUENCE="${CC_SEQUENCE:-2}"
CC_POLICY="${CC_POLICY:-OR('Org1MSP.peer','Org2MSP.peer')}"
ORDERER_ADDR="${ORDERER_ADDR:-localhost:7050}"
ORDERER_CA="${ORDERER_CA:-$TEST_NET/organizations/ordererOrganizations/example.com/tlsca/tlsca.example.com-cert.pem}"

# API / Node SDK bits
API_DIR="${API_DIR:-$HOME/landledger/api}"
API_CONN_DIR="${API_CONN_DIR:-$API_DIR/connection}"
API_CCP="${API_CCP:-$API_CONN_DIR/connection-org1.json}"
WALLET_DIR="${WALLET_DIR:-$API_DIR/wallet}"
IDENTITY="${IDENTITY:-appUser}"
DISCOVERY_AS_LOCALHOST="${DISCOVERY_AS_LOCALHOST:-true}"
REUSE_GATEWAY="${REUSE_GATEWAY:-false}"

###############################################
# Helpers
###############################################
has_cmd() { command -v "$1" >/dev/null 2>&1; }
fail() { echo "ERROR: $*" >&2; exit 1; }
logh() { echo -e "\n== $* ==\n"; }
require_files_exist() { for f in "$@"; do [[ -f "$f" ]] || fail "Missing file: $f"; done; }

retry() {
  # retry <max_tries> <sleep_seconds> <cmd...>
  local tries="${1:-5}"; shift
  local sleep_s="${1:-6}"; shift
  local n=1
  while true; do
    "$@" && return 0
    if (( n >= tries )); then
      echo "!! Command failed after $tries attempt(s): $*" >&2
      return 1
    fi
    echo "-> Retry $((n++))/$tries in ${sleep_s}s: $*"
    sleep "$sleep_s"
  done
}

# Source peer CLI env (Org1) to use peer commands reliably
load_cli_env() {
  export PATH="$FABRIC_SAMPLES_DIR/bin:$PATH"
  export FABRIC_CFG_PATH="$TEST_NET/../config"
  [[ -f "$FABRIC_CFG_PATH/core.yaml" ]] || FABRIC_CFG_PATH="$FABRIC_SAMPLES_DIR/config"
  [[ -f "$FABRIC_CFG_PATH/core.yaml" ]] || fail "core.yaml not found; set FABRIC_CFG_PATH."

  export CORE_PEER_TLS_ENABLED=true
  export VERBOSE=false
  export OVERRIDE_ORG=""   # envVar.sh expects this to exist under set -u

  # Source from inside test-network so relative includes resolve
  pushd "$TEST_NET" >/dev/null
    set +u
    # shellcheck disable=SC1091
    . ./scripts/envVar.sh
    set -u
    setGlobals 1   # Org1 context for readiness & lifecycle checks
  popd >/dev/null
}

# Wait until orderer is ready by polling channel info
wait_for_orderer_ready() {
  echo "-> Waiting for orderer readiness on $ORDERER_ADDR (Raft leader)..."
  load_cli_env
  require_files_exist "$ORDERER_CA"
  local deadline=$(( $(date +%s) + 90 ))
  while true; do
    if peer channel getinfo -o "$ORDERER_ADDR" --tls --cafile "$ORDERER_CA" -c "$CHANNEL_NAME" >/dev/null 2>&1; then
      echo "   Orderer responded; proceeding."
      return 0
    fi
    if (( $(date +%s) > deadline )); then
      echo "!! Orderer did not become ready within timeout." >&2
      return 1
    fi
    sleep 3
  done
}

# Write connection profile with TLS CA *paths* and channel mapping
write_api_connection_profile() {
  mkdir -p "$API_CONN_DIR"
  local ORG1_TLS_CA="$TEST_NET/organizations/peerOrganizations/org1.example.com/tlsca/tlsca.org1.example.com-cert.pem"
  local ORDERER_TLS_CA="$TEST_NET/organizations/ordererOrganizations/example.com/tlsca/tlsca.example.com-cert.pem"
  local CA_ORG1_CERT="$TEST_NET/organizations/peerOrganizations/org1.example.com/ca/ca.org1.example.com-cert.pem"
  require_files_exist "$ORG1_TLS_CA" "$ORDERER_TLS_CA" "$CA_ORG1_CERT"

  [[ -f "$API_CCP" ]] && cp -a "$API_CCP" "${API_CCP}.bak.$(date +%s)" || true
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
    "${CHANNEL_NAME}": {
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

# Ensure wallet has admin + user
ensure_wallet() {
  mkdir -p "$WALLET_DIR"
  if ! has_cmd node; then
    echo "!! Node not found; skipping wallet enrollment. Ensure wallet exists at: $WALLET_DIR"
    return 0
  fi
  pushd "$API_DIR" >/dev/null
    export CCP_PATH="$API_CCP" WALLET_DIR="$WALLET_DIR" IDENTITY="$IDENTITY"
    if [[ ! -f "$WALLET_DIR/admin.id" ]]; then
      [[ -f enrollAdmin.js ]] || fail "enrollAdmin.js not found in $API_DIR"
      node enrollAdmin.js
    fi
    if [[ ! -f "$WALLET_DIR/$IDENTITY.id" ]]; then
      [[ -f registerUser.js ]] || fail "registerUser.js not found in $API_DIR"
      node registerUser.js
    fi
  popd >/dev/null
  echo "✓ Wallet ready at $WALLET_DIR (admin + $IDENTITY)"
}

launch_api() {
  if [[ ! -x "$START_SCRIPT" ]]; then
    echo "!! Start script not found or not executable at: $START_SCRIPT"
    echo "   Set START_SCRIPT to your path, e.g.:"
    echo "   START_SCRIPT=\$HOME/landledger/start_landledger_api.sh $0"
    exit 1
  fi
  export CCP_PATH="$API_CCP" WALLET_DIR="$WALLET_DIR" CHANNEL="$CHANNEL_NAME" CC_NAME="$CC_NAME" IDENTITY="$IDENTITY"
  export DISCOVERY_AS_LOCALHOST="$DISCOVERY_AS_LOCALHOST" REUSE_GATEWAY="$REUSE_GATEWAY"
  echo "-> Launching API with env { CHANNEL=$CHANNEL_NAME CC_NAME=$CC_NAME IDENTITY=$IDENTITY REUSE_GATEWAY=$REUSE_GATEWAY }"
  "$START_SCRIPT"
}

wait_api() {
  echo "-> Waiting for API to respond at $API_BASE ..."
  local deadline=$(( $(date +%s) + MAX_WAIT_SEC ))
  until curl -fsS "$API_BASE/healthz" >/dev/null 2>&1; do
    if (( $(date +%s) > deadline )); then
      echo "!! API did not come up within ${MAX_WAIT_SEC}s"
      exit 2
    fi
    sleep 2
  done
  echo "   API is up."
}

check_blocks() {
  echo "-> Checking blocks at $API_BASE/healthz/blocks ..."
  local blocks_json length
  blocks_json="$(curl -fsS "$API_BASE/healthz/blocks" || true)"
  [[ -z "$blocks_json" ]] && { echo "   (No response) — proceeding."; return 0; }
  if echo "$blocks_json" | grep -qi '"error"'; then
    echo "   (Endpoint error) — proceeding: $blocks_json"; return 0
  fi
  if has_cmd jq; then
    length="$(echo "$blocks_json" | jq 'length' 2>/dev/null || echo "")"
  else
    length="$(python3 - <<'PY' 2>/dev/null
import sys, json
try: print(len(json.load(sys.stdin)))
except Exception: pass
PY
<<<"$blocks_json")"
  fi
  if [[ -n "${length:-}" ]]; then
    echo "   Blocks reported: $length"
    if [[ "$length" -lt "$EXPECTED_BLOCKS" ]]; then
      echo "!! WARNING: expected at least $EXPECTED_BLOCKS block(s), got $length."
      echo "   Height may climb as transactions settle."
    else
      echo "✅ Block count OK (>= $EXPECTED_BLOCKS)."
    fi
  else
    echo "   Could not parse blocks JSON — continuing."
  fi
}

# Query committed via peer CLI (reliable when reusing volumes)
cc_query_committed() {
  load_cli_env
  set +e
  local out rc ver seq
  out="$(peer lifecycle chaincode querycommitted -C "$CHANNEL_NAME" -n "$CC_NAME" 2>/dev/null)"
  rc=$?
  set -e
  if (( rc == 0 )) && echo "$out" | grep -q "Sequence:"; then
    ver="$(echo "$out" | sed -n 's/.*Version: \([^,]*\).*/\1/p' | head -n1)"
    seq="$(echo "$out" | sed -n 's/.*Sequence: \([0-9][0-9]*\).*/\1/p' | head -n1)"
    echo "-> Found committed definition: version=$ver sequence=$seq"
    return 0
  fi
  return 1
}

###############################################
# Bring-up flow
###############################################
echo "==> Safe bring-up (reuse ledger volumes)"
echo "   EXPECTED_BLOCKS=$EXPECTED_BLOCKS"
echo "   API_BASE=$API_BASE"
echo "   START_SCRIPT=$START_SCRIPT"
echo "   TEST_NET=$TEST_NET"
echo

# 1) Start Fabric containers that were previously stopped
echo "-> Starting Fabric containers by name pattern"
mapfile -t ALL_IDS < <(docker ps -a --format '{{.ID}} {{.Names}}' \
  | egrep 'orderer|peer|couchdb|ca|ccaas|chaincode|cli' \
  | awk '{print $1}' || true)
if (( ${#ALL_IDS[@]} )); then
  docker start "${ALL_IDS[@]}" >/dev/null
  echo "   Started ${#ALL_IDS[@]} container(s)."
else
  echo "   No Fabric containers found. (If you used compose, start them with 'docker compose start'.)"
fi

# 2) Ensure chaincode is committed (after orderer is actually ready) — NO forced redeploy loop
wait_for_orderer_ready || {
  echo "!! Orderer readiness check failed; showing recent logs:"
  docker logs --tail=200 orderer.example.com 2>&1 || true
  exit 1
}

echo "-> Checking committed status of '$CC_NAME' on '$CHANNEL_NAME' (peer CLI)..."
if cc_query_committed; then
  echo "-> Chaincode already committed; skipping redeploy."
else
  echo "!! Not committed (peer CLI). Attempting deploy (with retry)..."
  pushd "$TEST_NET" >/dev/null
    if retry 5 6 ./network.sh deployCC \
      -c "$CHANNEL_NAME" \
      -ccn "$CC_NAME" \
      -ccp "$CC_SRC_PATH" \
      -ccl "$CC_LANG" \
      -ccv "$CC_VERSION" \
      -ccs "$CC_SEQUENCE" \
      -ccep "$CC_POLICY"
    then
      echo "-> Deploy script reported success."
    else
      echo "!! Deploy script failed. Re-checking committed status..."
      if cc_query_committed; then
        echo "-> It is actually committed; continuing."
      else
        echo "!! Still not committed. Dumping quick lifecycle diagnostics:"
        load_cli_env
        echo "== querycommitted ==";  peer lifecycle chaincode querycommitted -C "$CHANNEL_NAME" 2>&1 || true
        echo "== queryapproved (Org1, seq=$CC_SEQUENCE) =="; peer lifecycle chaincode queryapproved -C "$CHANNEL_NAME" -n "$CC_NAME" --sequence "$CC_SEQUENCE" 2>&1 || true
        echo "== queryinstalled (Org1) ==";  peer lifecycle chaincode queryinstalled 2>&1 || true
        exit 1
      fi
    fi
  popd >/dev/null
fi

# 3) Write a fresh connection profile (TLS CA paths + channels mapping)
logh "Writing API connection profile"
write_api_connection_profile

# 4) Ensure wallet identities exist
logh "Ensuring wallet identities"
ensure_wallet

# 5) Start the Node API (PM2 or your script)
logh "Starting API"
launch_api

# 6) Wait for API and run basic checks
wait_api
check_blocks

# 7) Show quick examples
echo
echo "-> Sample checks:"
echo "   curl -s $API_BASE/healthz | head -c 200 && echo"
echo "   curl -s $API_BASE/healthz/LL-Buea-DA6480 | head -c 200 && echo"
echo
echo "✅ Bring-up complete."
