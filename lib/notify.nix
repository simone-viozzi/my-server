{ pkgs }:

let
  appriseUrl = "http://localhost:8000/notify/apprise";
in
{
  # Send a plain-text notification via Apprise. Best-effort: never fails the caller.
  # Usage in a writeShellScript: ${notify} "my message"
  notify = pkgs.writeShellScript "system-notify" ''
    ${pkgs.curl}/bin/curl -sf -X POST "${appriseUrl}" \
      -H "Content-Type: application/json" \
      -d "{\"body\": \"$1\", \"tag\": \"admin\"}" \
      --connect-timeout 3 \
      --max-time 5 \
      2>/dev/null || true
  '';

  # Send a Markdown-formatted notification with a title. Best-effort.
  # Usage: ${notifyMd} "Title" "**body** with _markdown_"
  # Requires apprise target URL to pass format=markdown (Telegram supports this).
  notifyMd = pkgs.writeShellScript "system-notify-md" ''
    title=$1
    body=$2
    ${pkgs.jq}/bin/jq -n --arg t "$title" --arg b "$body" \
      '{title: $t, body: $b, format: "markdown", tag: "admin"}' \
      | ${pkgs.curl}/bin/curl -sf -X POST "${appriseUrl}" \
          -H "Content-Type: application/json" \
          --data-binary @- \
          --connect-timeout 3 \
          --max-time 5 \
          2>/dev/null || true
  '';
}
