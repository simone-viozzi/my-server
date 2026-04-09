{ pkgs, ... }:

let
  notifyFailure = ../scripts/notify-failure.sh;
  appriseUrl = "http://localhost:8000/notify/apprise";
in
{
  systemd.services = {
    # ── Failure notification template ─────────────────────────────────
    # Any unit can use: onFailure = [ "notify-failure@%n.service" ];
    "notify-failure@" = {
      description = "Failure notification for %i";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash ${notifyFailure} %i";
      };
      path = [
        pkgs.curl
        pkgs.systemd
        pkgs.util-linux
        pkgs.hostname
      ];
    };

    # ── Boot notification ─────────────────────────────────────────────
    boot-notify = {
      description = "Send boot notification via Apprise";
      after = [
        "network-online.target"
        "podman-apprise.service"
      ];
      wants = [
        "network-online.target"
        "podman-apprise.service"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        # Give apprise a moment to start accepting requests
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
        ExecStart = pkgs.writeShellScript "boot-notify" ''
          ${pkgs.curl}/bin/curl -sf -X POST "${appriseUrl}" \
            -H "Content-Type: application/json" \
            -d '{"body": "simoserver is online!"}' \
            --connect-timeout 5 \
            --max-time 10 || true
        '';
      };
    };

    # ── Safe poweroff ─────────────────────────────────────────────────
    safe-poweroff = {
      description = "Graceful shutdown: notify, wait for locks, poweroff";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "safe-poweroff" ''
          # Notify: shutting down
          ${pkgs.curl}/bin/curl -sf -X POST "${appriseUrl}" \
            -H "Content-Type: application/json" \
            -d '{"body": "simoserver shutting down in 10 minutes"}' \
            --connect-timeout 5 \
            --max-time 10 || true

          # Wait 10 minutes
          sleep 600

          # Wait for btrfs2cloud backup lock (if running)
          LOCK_FILE="/var/lock/btrfs2cloud.lock"
          if [ -f "$LOCK_FILE" ]; then
            echo "Waiting for backup lock to release..."
            ${pkgs.util-linux}/bin/flock "$LOCK_FILE" true
          fi

          # Final notification
          ${pkgs.curl}/bin/curl -sf -X POST "${appriseUrl}" \
            -H "Content-Type: application/json" \
            -d '{"body": "simoserver powering off now"}' \
            --connect-timeout 5 \
            --max-time 10 || true

          ${pkgs.systemd}/bin/systemctl poweroff
        '';
      };
      path = [
        pkgs.curl
        pkgs.coreutils
        pkgs.util-linux
        pkgs.systemd
      ];
    };
  };
}
