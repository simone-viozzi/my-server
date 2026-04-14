#!/usr/bin/env bash
# Backup runner. Static script, parameterized by env vars + JSON config.
#
# Required env vars (set by the systemd unit):
#   SERVICE              service name (also used as restic repo suffix)
#   BACKUP_CONFIG        path to JSON config file (see shape below)
#   RESTIC_REPO_BASE     e.g. s3:s3.example.com/bucket  (from sops env file)
#   AWS_ACCESS_KEY_ID    from sops env file
#   AWS_SECRET_ACCESS_KEY from sops env file
#   RESTIC_PASSWORD_FILE path to per-service restic password
#   NOTIFY_BIN           path to notification helper (called with: title body)
#   XDG_CACHE_HOME       restic cache dir
#
# BACKUP_CONFIG JSON shape:
#   {
#     "service": "...",
#     "containers": ["..."],
#     "volumes": [{"name": "...", "snapshotDir": "...", "currentDir": "..."}],
#     "retention": {"daily": N, "weekly": N, "monthly": N},
#     "btrbkConfig": "/etc/btrbk/<svc>.conf",
#     "lockFile": "/var/lock/backup.lock"
#   }

set -euo pipefail

STEP="init"
START_TIME=$(date +%s)
JSON_LOG=""

log() { echo "[$(date +%H:%M:%S)] [$STEP] $*"; }
err() { echo "[$(date +%H:%M:%S)] [$STEP] ERROR: $*" >&2; }

human_size() {
  numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "${1}B"
}

restic_cmd() {
  restic -r "${RESTIC_REPO_BASE}/${SERVICE}" --password-file "$RESTIC_PASSWORD_FILE" "$@"
}

cleanup() {
  local exit_code=$?
  [ -n "$JSON_LOG" ] && rm -f "$JSON_LOG"
  if [ "$exit_code" -ne 0 ]; then
    err "Backup failed at step=$STEP exit=$exit_code"
    # Best-effort container restart so the service is never left stopped.
    local prev_step="$STEP"
    STEP="recovery-restart"
    if [ -n "${BACKUP_CONFIG:-}" ] && [ -r "$BACKUP_CONFIG" ]; then
      while IFS= read -r c; do
        log "Restarting $c..."
        systemctl start "podman-$c.service" || true
      done < <(jq -r '.containers[]' "$BACKUP_CONFIG")
    fi
    "$NOTIFY_BIN" \
      "BACKUP FAILED: $SERVICE" \
      "*host:* \`$(hostname)\`
*step:* \`$prev_step\`
*exit:* \`$exit_code\`

Logs: \`journalctl -u backup-$SERVICE -n 100\`"
  fi
  exec 9>&- || true
}
trap cleanup EXIT

# --- Parse config ---
CFG="$BACKUP_CONFIG"
LOCK_FILE=$(jq -r '.lockFile' "$CFG")
BTRBK_CONF=$(jq -r '.btrbkConfig' "$CFG")
KEEP_DAILY=$(jq -r '.retention.daily' "$CFG")
KEEP_WEEKLY=$(jq -r '.retention.weekly' "$CFG")
KEEP_MONTHLY=$(jq -r '.retention.monthly' "$CFG")

echo "=== Backup starting: $SERVICE ==="

# --- Acquire lock ---
STEP="acquiring-lock"
log "Waiting for lock $LOCK_FILE..."
exec 9>"$LOCK_FILE"
flock 9
log "Lock acquired"

# --- Stop containers ---
STEP="stopping-containers"
while IFS= read -r c; do
  log "Stopping $c..."
  systemctl stop "podman-$c.service" || true
done < <(jq -r '.containers[]' "$CFG")

# --- btrbk snapshots ---
STEP="creating-snapshots"
while IFS= read -r vol; do
  log "Snapshotting $vol..."
  btrbk -c "$BTRBK_CONF" snapshot "docker-volumes/@$vol"
done < <(jq -r '.volumes[].name' "$CFG")

# --- Restart containers ---
STEP="starting-containers"
while IFS= read -r c; do
  log "Starting $c..."
  systemctl start "podman-$c.service" || true
done < <(jq -r '.containers[]' "$CFG")

# --- Refresh stable .current/@<vol> CoW snapshots ---
# Gives restic an identical source path across runs so parent lookup and
# per-file reuse work. Idempotent under crash: delete-if-exists then snapshot.
STEP="refreshing-stable"
RESTIC_PATHS=()
while IFS=$'\t' read -r vol snapdir curdir; do
  NEWEST=$(find "$snapdir" -maxdepth 1 -name "@$vol.[0-9]*" | sort | tail -1)
  if [ -z "$NEWEST" ]; then
    err "no btrbk snapshot found for $vol in $snapdir"
    exit 1
  fi
  log "Picked snapshot for $vol: $NEWEST"
  STABLE="$curdir/@$vol"
  if [ -e "$STABLE" ]; then
    log "Removing prior stable snapshot $STABLE"
    btrfs subvolume delete "$STABLE"
  fi
  btrfs subvolume snapshot -r "$NEWEST" "$STABLE"
  RESTIC_PATHS+=("$STABLE")
done < <(jq -r '.volumes[] | [.name, .snapshotDir, .currentDir] | @tsv' "$CFG")

# --- Restic init (if needed) ---
STEP="restic-init"
if ! restic_cmd cat config >/dev/null 2>&1; then
  log "Initializing restic repo at ${RESTIC_REPO_BASE}/${SERVICE}"
  restic_cmd init
fi

# --- Restic backup (capture --json for stats) ---
STEP="restic-backup"
log "Backing up ${#RESTIC_PATHS[@]} path(s) to ${RESTIC_REPO_BASE}/${SERVICE}"
JSON_LOG=$(mktemp)
restic_cmd backup --json "${RESTIC_PATHS[@]}" | tee "$JSON_LOG"

SUMMARY=$(grep '"message_type":"summary"' "$JSON_LOG" | tail -1 || echo "{}")
FILES_NEW=$(echo "$SUMMARY" | jq -r '.files_new // 0')
FILES_CHANGED=$(echo "$SUMMARY" | jq -r '.files_changed // 0')
FILES_UNMODIFIED=$(echo "$SUMMARY" | jq -r '.files_unmodified // 0')
DATA_ADDED=$(echo "$SUMMARY" | jq -r '.data_added // 0')
TOTAL_PROCESSED=$(echo "$SUMMARY" | jq -r '.total_bytes_processed // 0')
SNAPSHOT_ID_FULL=$(echo "$SUMMARY" | jq -r '.snapshot_id // "unknown"')
SNAPSHOT_ID="${SNAPSHOT_ID_FULL:0:8}"

DATA_ADDED_H=$(human_size "$DATA_ADDED")
TOTAL_H=$(human_size "$TOTAL_PROCESSED")

log "Summary: new=$FILES_NEW changed=$FILES_CHANGED unmodified=$FILES_UNMODIFIED added=$DATA_ADDED_H total=$TOTAL_H snapshot=$SNAPSHOT_ID"

# --- Prune ---
STEP="restic-prune"
log "Pruning (keep: ${KEEP_DAILY}d ${KEEP_WEEKLY}w ${KEEP_MONTHLY}m)"
restic_cmd forget --prune \
  --keep-daily "$KEEP_DAILY" \
  --keep-weekly "$KEEP_WEEKLY" \
  --keep-monthly "$KEEP_MONTHLY"

# --- Success ---
STEP="done"
END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))
DURATION_FMT="$(( DURATION / 60 ))m$(( DURATION % 60 ))s"

# Disarm failure trap before notifying success (cleanup still runs for $JSON_LOG rm + fd close).
trap - EXIT
rm -f "$JSON_LOG"
exec 9>&- || true

"$NOTIFY_BIN" \
  "Backup OK: $SERVICE" \
  "*duration:* \`$DURATION_FMT\`
*files:* \`$FILES_NEW\` new / \`$FILES_CHANGED\` changed / \`$FILES_UNMODIFIED\` unchanged
*added:* \`$DATA_ADDED_H\` of \`$TOTAL_H\`
*snapshot:* \`$SNAPSHOT_ID\`"
echo "=== Backup complete: $SERVICE ($DURATION_FMT) ==="
