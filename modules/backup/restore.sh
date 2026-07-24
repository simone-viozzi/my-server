#!/usr/bin/env bash
# backup-restore — read data back out of the per-service restic repos.
#
# Counterpart to backup.sh. Every command here is read-only with respect to
# live data: nothing writes outside $STAGING_ROOT, and no code path touches
# /mnt/btrbk/**. In-place restore ("swap") is deliberately not implemented yet.
#
# Env (injected by the Nix wrapper in backup.nix):
#   RESTORE_CONFIG   path to the JSON manifest generated from backup.services
#   RESTIC_ENV_FILE  sops-rendered env: AWS keys + RESTIC_REPO_BASE

STAGING_ROOT="/var/lib/backup-restore"
SIZE_GUARD=$((5 * 1024 * 1024 * 1024)) # refuse a restore above this without --yes

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}
info() { printf '%s\n' "$*" >&2; }
human() { numfmt --to=iec --suffix=B "$1" 2>/dev/null || printf '%sB' "$1"; }

usage() {
  cat >&2 <<'EOF'
Usage: backup-restore <command> <service> [options]

Commands:
  list    list snapshots                              (metadata only, free)
  ls      browse a snapshot's contents                (metadata only, free)
  fetch   restore into staging, never touching live data
  verify  restore to a temp dir, verify content, discard

Options:
  --snapshot ID   snapshot to use (default: latest)
  --volume NAME   restrict to a single volume of the service
  --include PATH  restore only this path
  --target DIR    fetch only; default <staging>/<service>/<short-id>-<ts>
  --yes, -y       proceed when the restore exceeds the 5GiB guard

Live volumes are never modified. In-place restore is not implemented.
EOF
  exit 2
}

# ── Arguments ─────────────────────────────────────────────────────────────
[ $# -ge 1 ] || usage
CMD=$1
shift
case "$CMD" in
  list | ls | fetch | verify) ;;
  -h | --help) usage ;;
  *) die "unknown command: $CMD (expected list, ls, fetch or verify)" ;;
esac

[ $# -ge 1 ] || die "missing <service>"
SERVICE=$1
shift

SNAPSHOT="latest"
VOLUME=""
INCLUDE=""
TARGET=""
LSPATH=""
ASSUME_YES=0

while [ $# -gt 0 ]; do
  case "$1" in
    --snapshot)
      SNAPSHOT=${2:?--snapshot needs a value}
      shift 2
      ;;
    --volume)
      VOLUME=${2:?--volume needs a value}
      shift 2
      ;;
    --include)
      INCLUDE=${2:?--include needs a value}
      shift 2
      ;;
    --target)
      TARGET=${2:?--target needs a value}
      shift 2
      ;;
    --yes | -y)
      ASSUME_YES=1
      shift
      ;;
    -*) die "unknown option: $1" ;;
    *)
      # `ls` takes an optional bare PATH argument; nothing else does.
      if [ "$CMD" = "ls" ] && [ -z "$LSPATH" ]; then
        LSPATH=$1
        shift
      else
        die "unexpected argument: $1"
      fi
      ;;
  esac
done

# ── Environment ───────────────────────────────────────────────────────────
[ "$(id -u)" -eq 0 ] || die "must run as root — sops secrets are root-only (try: sudo backup-restore ...)"

[ -r "${RESTIC_ENV_FILE:?}" ] || die "cannot read $RESTIC_ENV_FILE"
set -a
# shellcheck disable=SC1090  # sops-rendered at runtime, not knowable at build time
. "$RESTIC_ENV_FILE"
set +a
: "${RESTIC_REPO_BASE:?not provided by $RESTIC_ENV_FILE}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/var/cache/restic}"

[ -r "${RESTORE_CONFIG:?}" ] || die "cannot read $RESTORE_CONFIG"
if ! jq -e --arg s "$SERVICE" '.services | has($s)' "$RESTORE_CONFIG" >/dev/null; then
  die "unknown service '$SERVICE' (known: $(jq -r '.services | keys | join(", ")' "$RESTORE_CONFIG"))"
fi
PASSWORD_FILE=$(jq -r --arg s "$SERVICE" '.services[$s].passwordFile' "$RESTORE_CONFIG")
[ -r "$PASSWORD_FILE" ] || die "cannot read restic password file $PASSWORD_FILE"

restic_cmd() {
  restic -r "${RESTIC_REPO_BASE}/${SERVICE}" --password-file "$PASSWORD_FILE" "$@"
}

# ── Helpers ───────────────────────────────────────────────────────────────

# Resolve a volume name to its absolute path inside a snapshot.
#
# Paths are read from the snapshot itself rather than assumed. Current
# snapshots hold <currentDir>/@<vol>, but ones predating that migration hold
# <snapshotDir>/@<vol>.<timestamp> — assuming either layout would silently
# restore nothing from the other. Matching on the basename handles both.
resolve_volume_path() {
  local snap=$1 vol=$2 path base
  local -a paths=()
  mapfile -t paths < <(restic_cmd snapshots "$snap" --json | jq -r '.[0].paths[]')
  [ "${#paths[@]}" -gt 0 ] || die "snapshot $snap contains no paths"

  for path in "${paths[@]}"; do
    base=${path##*/}
    if [ "$base" = "@$vol" ] || [ "${base#"@$vol."}" != "$base" ]; then
      printf '%s\n' "$path"
      return 0
    fi
  done

  die "volume '$vol' is not in snapshot $snap, which contains:
$(printf '  %s\n' "${paths[@]}")"
}

check_space() {
  local need=$1 dir=$2 avail
  avail=$(df -B1 --output=avail "$dir" | tail -1 | tr -d ' ')
  [ "$avail" -ge "$need" ] || die "not enough space in $dir: need $(human "$need"), have $(human "$avail")"
}

# ── Commands ──────────────────────────────────────────────────────────────
case "$CMD" in
  list)
    restic_cmd snapshots
    ;;

  ls)
    if [ -n "$LSPATH" ]; then
      restic_cmd ls "$SNAPSHOT" "$LSPATH"
    else
      restic_cmd ls "$SNAPSHOT"
    fi
    ;;

  fetch | verify)
    RESTORE_ARGS=()
    if [ -n "$VOLUME" ]; then
      VOLPATH=$(resolve_volume_path "$SNAPSHOT" "$VOLUME")
      info "volume '$VOLUME' resolves to $VOLPATH"
      RESTORE_ARGS+=(--include "$VOLPATH")
    fi
    [ -n "$INCLUDE" ] && RESTORE_ARGS+=(--include "$INCLUDE")

    # Size comes from snapshot metadata (free). With --include this is an
    # upper bound on the whole snapshot, not the selection — fine for a guard.
    SIZE=$(restic_cmd stats "$SNAPSHOT" --mode restore-size --json | jq -r '.total_size')
    info "snapshot $SNAPSHOT restore size: $(human "$SIZE")"
    if [ "$SIZE" -gt "$SIZE_GUARD" ] && [ "$ASSUME_YES" -eq 0 ]; then
      die "refusing: $(human "$SIZE") exceeds the $(human "$SIZE_GUARD") guard — re-run with --yes"
    fi

    mkdir -p "$STAGING_ROOT"

    if [ "$CMD" = "fetch" ]; then
      if [ -z "$TARGET" ]; then
        SHORT_ID=$(restic_cmd snapshots "$SNAPSHOT" --json | jq -r '.[0].short_id')
        TARGET="$STAGING_ROOT/$SERVICE/$SHORT_ID-$(date +%Y%m%dT%H%M%S)"
      fi
      mkdir -p "$TARGET"
      check_space "$SIZE" "$TARGET"

      restic_cmd restore "$SNAPSHOT" --target "$TARGET" --sparse --verify "${RESTORE_ARGS[@]}"

      info ""
      info "restored to: $TARGET"
      info "live volumes were not modified."
    else
      TMPDIR_VERIFY=$(mktemp -d "$STAGING_ROOT/.verify-$SERVICE-XXXXXX")
      trap 'rm -rf "$TMPDIR_VERIFY"' EXIT
      check_space "$SIZE" "$TMPDIR_VERIFY"

      START=$(date +%s)
      restic_cmd restore "$SNAPSHOT" --target "$TMPDIR_VERIFY" --sparse --verify "${RESTORE_ARGS[@]}"
      DURATION=$(($(date +%s) - START))
      FILES=$(find "$TMPDIR_VERIFY" -type f | wc -l)

      info ""
      info "verify OK: $SERVICE snapshot $SNAPSHOT"
      info "  files restored : $FILES"
      info "  size           : $(human "$SIZE")"
      info "  duration       : ${DURATION}s"
      info "  (staging discarded; live volumes were not modified)"
    fi
    ;;
esac
