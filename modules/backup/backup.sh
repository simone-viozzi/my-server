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
# Classification of the service's units, made before the stop. The question is
# not "was it running" but "why wasn't it" — a oneshot that exited cleanly and a
# container that crashed both read as inactive, and they want opposite handling.
#   RESTART   — bring these back up afterwards
#   FAILED    — were down unexpectedly; restarted, but reported
#   LEFT      — down cleanly (finished oneshot, or stopped by hand); left alone
# All empty until the classification runs, which is also correct for the
# recovery path: if we failed before stopping anything, there is nothing to
# start.
RESTART=()
FAILED=()
LEFT=()

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
    if [ "${#RESTART[@]}" -gt 0 ]; then
      log "Restarting ${#RESTART[@]} container(s): ${RESTART[*]}"
      systemctl start "${RESTART[@]}" || true
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

# --- Stop containers (single call — systemd resolves dependency order) ---
STEP="stopping-containers"
mapfile -t CONTAINERS < <(jq -r '.containers[]' "$CFG")
UNITS=("${CONTAINERS[@]/#/podman-}")
UNITS=("${UNITS[@]/%/.service}")
# Classify before stopping. ActiveState is read explicitly rather than via
# `is-active --quiet`, which is true only for "active" and so would misfile a
# container caught mid-start as down and leave it stopped.
for unit in "${UNITS[@]}"; do
  short="${unit#podman-}"
  short="${short%.service}"
  state=$(systemctl show "$unit" --property=ActiveState --value)
  result=$(systemctl show "$unit" --property=Result --value)
  case "$state" in
    active | activating | reloading)
      RESTART+=("$unit")
      ;;
    failed)
      log "$short is failed (result=$result); restarting it and reporting"
      RESTART+=("$unit")
      FAILED+=("$short")
      ;;
    *)
      if [ "$result" != "success" ]; then
        # Down with a non-success result: it was meant to be up.
        log "$short is $state (result=$result); restarting it and reporting"
        RESTART+=("$unit")
        FAILED+=("$short")
      else
        # Exited cleanly — a finished oneshot, or stopped by hand. Either way
        # the intent is "down", so honour it; just don't let it go unnoticed.
        log "$short exited cleanly; leaving it stopped"
        LEFT+=("$short")
      fi
      ;;
  esac
done
log "Stopping ${#CONTAINERS[@]} container(s): ${CONTAINERS[*]}"
systemctl stop "${UNITS[@]}"

# --- btrbk snapshots ---
STEP="creating-snapshots"
while IFS= read -r vol; do
  log "Snapshotting $vol..."
  btrbk -c "$BTRBK_CONF" snapshot "docker-volumes/@$vol"
done < <(jq -r '.volumes[].name' "$CFG")

# --- Restart containers (single call — systemd resolves dependency order) ---
STEP="starting-containers"
if [ "${#RESTART[@]}" -gt 0 ]; then
  log "Starting ${#RESTART[@]} container(s): ${RESTART[*]}"
  systemctl start "${RESTART[@]}"
else
  log "Nothing to start: every container was already down"
fi

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

# Container anomalies. A backup must never quietly resurrect something that was
# stopped on purpose — but it must never quietly hide it either, or a container
# that is down stays down unnoticed until someone goes looking.
CONTAINER_NOTE=""
if [ "${#FAILED[@]}" -gt 0 ]; then
  CONTAINER_NOTE+="
*was down:* \`${FAILED[*]}\` — restarted"
fi
if [ "${#LEFT[@]}" -gt 0 ]; then
  CONTAINER_NOTE+="
*left stopped:* \`${LEFT[*]}\` (clean exit)"
fi

# Disarm failure trap before notifying success (cleanup still runs for $JSON_LOG rm + fd close).
trap - EXIT
rm -f "$JSON_LOG"
exec 9>&- || true

"$NOTIFY_BIN" \
  "Backup OK: $SERVICE" \
  "*duration:* \`$DURATION_FMT\`
*files:* \`$FILES_NEW\` new / \`$FILES_CHANGED\` changed / \`$FILES_UNMODIFIED\` unchanged
*added:* \`$DATA_ADDED_H\` of \`$TOTAL_H\`
*snapshot:* \`$SNAPSHOT_ID\`$CONTAINER_NOTE"
echo "=== Backup complete: $SERVICE ($DURATION_FMT) ==="
