{ pkgs }:

let
  appriseUrl = "http://localhost:8000/notify/apprise";
in
{
  # Send a notification via Apprise. Best-effort: never fails the caller.
  # Usage in a writeShellScript: ${notify} "my message"
  notify = pkgs.writeShellScript "system-notify" ''
    ${pkgs.curl}/bin/curl -sf -X POST "${appriseUrl}" \
      -H "Content-Type: application/json" \
      -d "{\"body\": \"$1\", \"tag\": \"admin\"}" \
      --connect-timeout 3 \
      --max-time 5 \
      2>/dev/null || true
  '';
}
