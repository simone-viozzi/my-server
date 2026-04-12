{ pkgs, ... }:

let
  inherit (import ../lib/notify.nix { inherit pkgs; }) notify;
in
{
  systemd.services = {
    # ── Failure notification template ─────────────────────────────────
    # Any unit can use: onFailure = [ "notify-failure@%n.service" ];
    "notify-failure@" = {
      description = "Failure notification for %i";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "notify-failure" ''
          UNIT="$1"
          JOURNAL=$(${pkgs.systemd}/bin/journalctl -u "''${UNIT}" -n 20 --no-pager 2>/dev/null || echo "(could not read journal)")

          ${notify} "''${UNIT} failed on $(${pkgs.hostname}/bin/hostname). Check: journalctl -u ''${UNIT}"

          ${pkgs.util-linux}/bin/wall <<EOF
          === SYSTEMD UNIT FAILED ===
          Unit: ''${UNIT}
          Time: $(date)

          Check logs:
            journalctl -u ''${UNIT}
            systemctl status ''${UNIT}

          Last journal lines:
          ''${JOURNAL}
          EOF
        '';
      };
      scriptArgs = "%i";
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
        RemainAfterExit = true;
        # Give apprise a moment to start accepting requests
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
        ExecStart = ''${notify} "simoserver is online!"'';
      };
    };

    # ── Safe poweroff ─────────────────────────────────────────────────
    safe-poweroff = {
      description = "Graceful shutdown: notify, wait for locks, poweroff";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "safe-poweroff" ''
          ${notify} "simoserver shutting down in 10 minutes"

          sleep 600

          # Wait for btrfs2cloud backup lock (if running)
          LOCK_FILE="/var/lock/btrfs2cloud.lock"
          if [ -f "$LOCK_FILE" ]; then
            echo "Waiting for backup lock to release..."
            ${pkgs.util-linux}/bin/flock "$LOCK_FILE" true
          fi

          ${notify} "simoserver powering off now"

          ${pkgs.systemd}/bin/systemctl poweroff
        '';
      };
    };
  };
}
