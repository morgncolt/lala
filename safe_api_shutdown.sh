#!/usr/bin/env bash
set -Eeuo pipefail

###############################################
# Tunables (override via env)
###############################################
PM2_APP="${PM2_APP:-landledger-api}"              # pm2 process name
DUMP_LOGS="${DUMP_LOGS:-true}"                    # save PM2 & docker logs before stopping
LOG_LINES="${LOG_LINES:-400}"                      # how many lines per log to capture
DOCKER_STOP_TIMEOUT="${DOCKER_STOP_TIMEOUT:-15}"   # docker stop -t seconds
CONTAINER_GREP="${CONTAINER_GREP:-orderer|peer|couchdb|ca|ccaas|chaincode|cli|dev-peer}"  # patterns to stop
LOG_ROOT="${LOG_ROOT:-$HOME/landledger/_shutdown_artifacts}"
TS="$(date +%Y%m%d-%H%M%S)"
LOG_DIR="$LOG_ROOT/$TS"

echo "==> Safe shutdown (preserve ledger data)"
echo "   PM2_APP=$PM2_APP"
echo "   DUMP_LOGS=$DUMP_LOGS  LOG_LINES=$LOG_LINES"
echo "   DOCKER_STOP_TIMEOUT=$DOCKER_STOP_TIMEOUT"
echo "   Patterns: $CONTAINER_GREP"
echo "   Artifacts: $LOG_DIR"
echo

###############################################
# Helpers
###############################################
has_cmd() { command -v "$1" >/dev/null 2>&1; }

snapshot_pm2_logs() {
  [[ "$DUMP_LOGS" == "true" ]] || return 0
  [[ -d "$LOG_DIR" ]] || mkdir -p "$LOG_DIR"
  local pm2_logs_dir="$HOME/.pm2/logs"
  if [[ -d "$pm2_logs_dir" ]]; then
    # copy raw logs for the app if present
    for f in "$pm2_logs_dir/${PM2_APP}-out.log" "$pm2_logs_dir/${PM2_APP}-error.log"; do
      [[ -f "$f" ]] && tail -n "$LOG_LINES" "$f" > "$LOG_DIR/$(basename "$f").tail.txt" || true
    done
    # also snapshot pm2 jlist for debugging
    if has_cmd pm2; then
      pm2 jlist > "$LOG_DIR/pm2-jlist.json" 2>/dev/null || true
    fi
  fi
}

snapshot_docker_logs() {
  [[ "$DUMP_LOGS" == "true" ]] || return 0
  [[ -d "$LOG_DIR" ]] || mkdir -p "$LOG_DIR"
  echo "-> Snapshotting docker ps (running & all) to $LOG_DIR"
  docker ps --no-trunc > "$LOG_DIR/docker-ps.txt" || true
  docker ps -a --no-trunc > "$LOG_DIR/docker-ps-a.txt" || true

  # Grab brief tails for matching containers (won't fail shutdown if any error)
  mapfile -t RUNNING_IDS < <(docker ps --format '{{.ID}} {{.Names}}' \
    | egrep "$CONTAINER_GREP" | awk '{print $1}' || true)
  if (( ${#RUNNING_IDS[@]} )); then
    echo "-> Saving docker logs (tail $LOG_LINES lines) for ${#RUNNING_IDS[@]} container(s)"
    for id in "${RUNNING_IDS[@]}"; do
      name="$(docker ps --filter "id=$id" --format '{{.Names}}' 2>/dev/null || echo "$id")"
      docker logs --tail "$LOG_LINES" "$id" > "$LOG_DIR/docker-${name}.tail.txt" 2>&1 || true
    done
  fi
}

###############################################
# 1) Snapshot logs (optional, before stopping)
###############################################
snapshot_pm2_logs
snapshot_docker_logs

###############################################
# 2) Stop API (PM2) if present
###############################################
if has_cmd pm2; then
  if pm2 jlist | grep -q "\"name\":\"$PM2_APP\""; then
    echo "-> Stopping PM2 service: $PM2_APP"
    pm2 stop "$PM2_APP" || true
  else
    echo "-> PM2 found, but $PM2_APP is not running."
  fi
else
  echo "-> PM2 not found; skipping API stop."
fi

###############################################
# 3) Stop Fabric containers (keep volumes)
###############################################
echo "-> Stopping Fabric containers (patterns: $CONTAINER_GREP)"
mapfile -t FABRIC_IDS < <(docker ps --format '{{.ID}} {{.Names}}' \
  | egrep "$CONTAINER_GREP" \
  | awk '{print $1}' || true)

if (( ${#FABRIC_IDS[@]} )); then
  # Use timeout to allow graceful shutdown (orderer/peers flush state)
  docker stop -t "$DOCKER_STOP_TIMEOUT" "${FABRIC_IDS[@]}" || true
  echo "   Stopped ${#FABRIC_IDS[@]} container(s)."
else
  echo "-> No running Fabric containers matched."
fi

###############################################
# 4) Done
###############################################
echo
echo "✅ Done. Ledger volumes were NOT removed."
echo "   Artifacts (logs, ps snapshots): $LOG_DIR"
