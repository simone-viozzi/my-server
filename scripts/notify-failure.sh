#!/usr/bin/env bash
# notify-failure.sh — Notify about a failed systemd unit.
#
# Usage: notify-failure.sh <unit-name>
#
# Tries apprise first, falls back to wall if apprise is unavailable.
# Always writes to wall as a last-resort guarantee.

set -uo pipefail

UNIT="$1"
APPRISE_URL="http://localhost:8000/notify/apprise"

# Grab the last 20 lines of the failed unit's journal
JOURNAL=$(journalctl -u "${UNIT}" -n 20 --no-pager 2>/dev/null || echo "(could not read journal)")

# Try apprise (best-effort, don't fail if it's down)
curl -sf -X POST "${APPRISE_URL}" \
    -H "Content-Type: application/json" \
    -d "{\"body\": \"${UNIT} failed on $(hostname). Check: journalctl -u ${UNIT}\"}" \
    --connect-timeout 3 \
    --max-time 5 \
    2>/dev/null || true

# Always wall — guaranteed to work even if everything else is down
wall <<EOF
=== SYSTEMD UNIT FAILED ===
Unit: ${UNIT}
Time: $(date)

Check logs:
  journalctl -u ${UNIT}
  systemctl status ${UNIT}

Last journal lines:
${JOURNAL}
EOF
