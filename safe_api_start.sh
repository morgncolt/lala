#!/usr/bin/env bash
set -Eeuo pipefail

EXPECTED_BLOCKS="${EXPECTED_BLOCKS:-4}"   # change or export EXPECTED_BLOCKS=...
API_BASE="${API_BASE:-http://localhost:4000}"
START_SCRIPT="${START_SCRIPT:-$HOME/landledger/start_landledger_api.sh}"
MAX_WAIT_SEC="${MAX_WAIT_SEC:-90}"

echo "==> Safe bring-up (reuse ledger volumes)"
echo "   EXPECTED_BLOCKS=$EXPECTED_BLOCKS"
echo "   API_BASE=$API_BASE"
echo "   START_SCRIPT=$START_SCRIPT"
echo

has_cmd() { command -v "$1" >/dev/null 2>&1; }

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

# 2) Start the Node API via your existing script (PM2)
if [[ -x "$START_SCRIPT" ]]; then
  echo "-> Launching API with: $START_SCRIPT"
  "$START_SCRIPT"
else
  echo "!! Start script not found or not executable at: $START_SCRIPT"
  echo "   Set START_SCRIPT to your path, e.g.:"
  echo "   START_SCRIPT=\$HOME/landledger/start_landledger_api.sh $0"
  exit 1
fi

# 3) Wait for API health (land list endpoint)
echo "-> Waiting for API to respond at $API_BASE ..."
deadline=$(( $(date +%s) + MAX_WAIT_SEC ))
until curl -fsS "$API_BASE/api/landledger" >/dev/null 2>&1; do
  if (( $(date +%s) > deadline )); then
    echo "!! API did not come up within ${MAX_WAIT_SEC}s"
    exit 2
  fi
  sleep 2
done
echo "   API is up."

# 4) Check blocks count (tolerate temporary 404 if endpoint not implemented)
echo "-> Checking blocks at $API_BASE/api/landledger/blocks ..."
blocks_json="$(curl -fsS "$API_BASE/api/landledger/blocks" || true)"

# If endpoint returns 404 (not implemented), warn but continue.
if [[ -z "$blocks_json" ]]; then
  echo "   (No response) — proceeding."
elif echo "$blocks_json" | grep -qi '"error"'; then
  echo "   (Endpoint error) — proceeding: $blocks_json"
else
  # Determine array length using jq or Python fallback
  if has_cmd jq; then
    length="$(echo "$blocks_json" | jq 'length' 2>/dev/null || echo "")"
  else
    length="$(python3 - <<'PY' 2>/dev/null
import sys, json
try:
    print(len(json.load(sys.stdin)))
except Exception:
    pass
PY
<<<"$blocks_json")"
  fi

  if [[ -n "${length:-}" ]]; then
    echo "   Blocks reported: $length"
    if [[ "$length" -lt "$EXPECTED_BLOCKS" ]]; then
      echo "!! WARNING: expected at least $EXPECTED_BLOCKS block(s), got $length."
      echo "   If you recently re-registered parcels, block height may increase over time."
    else
      echo "✅ Block count OK (>= $EXPECTED_BLOCKS)."
    fi
  else
    echo "   Could not parse blocks JSON — continuing."
  fi
fi

# 5) Show a couple of quick examples to confirm persistence
echo
echo "-> Sample checks:"
echo "   curl -s $API_BASE/api/landledger | head -c 200 && echo"
echo "   curl -s $API_BASE/api/landledger/LL-Buea-DA6480 | head -c 200 && echo"
echo
echo "✅ Bring-up complete."
