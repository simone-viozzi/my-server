{
  config,
  lib,
  pkgs,
  ...
}:

let
  volumes = import ../lib/volumes.nix;
  inherit (import ../lib/notify.nix { inherit pkgs; }) notify;

  cfg = config.backup;

  # Collect btrfs volumes that belong to each backup service
  volumesForService =
    serviceName: lib.filterAttrs (_: vol: vol.backupService == serviceName) volumes.btrfs;

  # Determine which btrfs devices a service's volumes span
  devicesForService =
    serviceName: lib.unique (lib.mapAttrsToList (_: vol: vol.device) (volumesForService serviceName));

  # All devices used by any backup service (for top-level mounts)
  allBackupDevices = lib.unique (lib.concatMap devicesForService (builtins.attrNames cfg.services));

  # Mount point for a device's top-level btrfs
  btrbkMountPoint = device: "/mnt/btrbk/${device}";

  # Path to a subvolume on a device

  # Path to snapshot directory on a device
  snapshotDir = device: "${btrbkMountPoint device}/docker-volumes/.snapshots";

  lockFile = "/var/lock/backup.lock";

  # Build the backup script for a given service
  mkBackupScript =
    serviceName: serviceCfg:
    let
      svcVolumes = volumesForService serviceName;

      # Find containers matching the service name prefix
      containerNames = builtins.filter (
        name: lib.hasPrefix "${serviceName}-" name || name == serviceName
      ) (builtins.attrNames config.virtualisation.oci-containers.containers);

      stopCmds = lib.concatMapStringsSep "\n" (
        c: "  echo \"Stopping ${c}...\"; systemctl stop podman-${c}.service || true"
      ) containerNames;

      startCmds = lib.concatMapStringsSep "\n" (
        c: "  echo \"Starting ${c}...\"; systemctl start podman-${c}.service || true"
      ) containerNames;

      # btrbk snapshot commands per volume
      snapshotCmds = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          volName: _vol:
          "  echo \"Snapshotting ${volName}...\"; btrbk -c /etc/btrbk/${serviceName}.conf snapshot docker-volumes/@${volName}"
        ) svcVolumes
      );

      # Collect latest snapshot paths for restic
      # btrbk names snapshots: <subvol>.<timestamp>
      collectSnapshotPaths = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          volName: vol:
          let
            sdir = snapshotDir vol.device;
          in
          "  SNAP_${
              lib.replaceStrings [ "-" ] [ "_" ] volName
            }=$(ls -1d ${sdir}/@${volName}.* 2>/dev/null | sort | tail -1)"
        ) svcVolumes
      );

      resticPaths = lib.concatStringsSep " " (
        lib.mapAttrsToList (
          volName: _: "\"$SNAP_${lib.replaceStrings [ "-" ] [ "_" ] volName}\""
        ) svcVolumes
      );

      retainDaily = toString serviceCfg.retention.daily;
      retainWeekly = toString serviceCfg.retention.weekly;
      retainMonthly = toString serviceCfg.retention.monthly;

      restic = "${pkgs.restic}/bin/restic -r \${RESTIC_REPO_BASE}/${serviceName} --password-file ${
        config.sops.secrets."restic_password_${serviceName}".path
      }";

    in
    pkgs.writeShellScript "backup-${serviceName}" ''
      set -euo pipefail

      SERVICE="${serviceName}"
      START_TIME=$(date +%s)

      # Acquire global backup lock (blocking wait)
      exec 9>"${lockFile}"
      echo "Waiting for backup lock..."
      flock 9
      echo "Lock acquired for $SERVICE"

      cleanup() {
        local exit_code=$?
        # Always try to restart containers on failure
        if [ $exit_code -ne 0 ]; then
          echo "Backup failed (exit $exit_code), ensuring containers are running..."
      ${startCmds}
          ${notify} "BACKUP FAILED: $SERVICE on $(hostname) (exit $exit_code)"
        fi
        exec 9>&-
      }
      trap cleanup EXIT

      echo "=== Backup starting: $SERVICE ==="

      # 1. Stop containers for consistency
      echo "--- Stopping containers ---"
      ${stopCmds}

      # 2. Take btrfs snapshots
      echo "--- Creating snapshots ---"
      ${snapshotCmds}

      # 3. Restart containers (snapshots are immutable, safe to resume)
      echo "--- Starting containers ---"
      ${startCmds}

      # 4. Find latest snapshot paths
      ${collectSnapshotPaths}

      # 5. Initialize restic repo if needed, then backup
      echo "--- Restic backup to B2 ---"
      ${restic} cat config >/dev/null 2>&1 || ${restic} init
      ${restic} backup ${resticPaths}

      # 6. Prune old restic snapshots
      echo "--- Restic prune ---"
      ${restic} forget \
        --prune \
        --keep-daily ${retainDaily} \
        --keep-weekly ${retainWeekly} \
        --keep-monthly ${retainMonthly}

      # 7. Success notification
      END_TIME=$(date +%s)
      DURATION=$(( END_TIME - START_TIME ))
      DURATION_FMT="$(( DURATION / 60 ))m$(( DURATION % 60 ))s"

      # Override trap for success
      trap - EXIT
      exec 9>&-

      ${notify} "Backup OK: $SERVICE ($DURATION_FMT)"
      echo "=== Backup complete: $SERVICE ($DURATION_FMT) ==="
    '';

  # Build the restic check script for a given service
  mkCheckScript =
    serviceName:
    let
      restic = "${pkgs.restic}/bin/restic -r \${RESTIC_REPO_BASE}/${serviceName} --password-file ${
        config.sops.secrets."restic_password_${serviceName}".path
      }";
    in
    pkgs.writeShellScript "restic-check-${serviceName}" ''
      set -euo pipefail
      echo "=== Restic integrity check: ${serviceName} ==="
      ${restic} check
      echo "=== Check OK: ${serviceName} ==="
    '';

  # Generate the backup-config diagnostic script
  mkDiagnosticScript =
    let
      mkServiceBlock =
        serviceName: serviceCfg:
        let
          svcVolumes = volumesForService serviceName;
          containerNames = builtins.filter (
            name: lib.hasPrefix "${serviceName}-" name || name == serviceName
          ) (builtins.attrNames config.virtualisation.oci-containers.containers);
          volumeLines = lib.concatStringsSep "\n" (
            lib.mapAttrsToList (
              volName: vol: "echo '    ${volName} (${vol.device}, type: ${vol.type})'"
            ) svcVolumes
          );
        in
        ''
          echo "Service: ${serviceName}"
          echo "  Schedule: ${serviceCfg.schedule}"
          echo "  Timeout: ${serviceCfg.timeout}"
          echo "  Containers: ${lib.concatStringsSep ", " containerNames}"
          echo "  Volumes:"
          ${volumeLines}
          echo "  Retention (offsite): ${toString serviceCfg.retention.daily}d / ${toString serviceCfg.retention.weekly}w / ${toString serviceCfg.retention.monthly}m"
          echo "  Restic repo: \''${RESTIC_REPO_BASE}/${serviceName} (from sops)"
          echo ""
        '';
      serviceBlocks = lib.concatStringsSep "\n" (lib.mapAttrsToList mkServiceBlock cfg.services);
    in
    pkgs.writeShellScriptBin "backup-config" ''
      echo "=== Backup Configuration ==="
      echo ""
      echo "Defaults:"
      echo "  Timeout: ${cfg.defaults.timeout}"
      echo "  Local snapshots: ${toString cfg.defaults.btrbk.snapshotRetain.daily}d / ${toString cfg.defaults.btrbk.snapshotRetain.weekly}w"
      echo "  Offsite retention: ${toString cfg.defaults.retention.daily}d / ${toString cfg.defaults.retention.weekly}w / ${toString cfg.defaults.retention.monthly}m"
      echo ""
      ${serviceBlocks}
    '';

in
{
  # ── Options ─────────────────────────────────────────────────────────
  options.backup = {
    defaults = {
      retention = {
        daily = lib.mkOption {
          type = lib.types.int;
          default = 4;
          description = "Default restic keep-daily";
        };
        weekly = lib.mkOption {
          type = lib.types.int;
          default = 2;
          description = "Default restic keep-weekly";
        };
        monthly = lib.mkOption {
          type = lib.types.int;
          default = 2;
          description = "Default restic keep-monthly";
        };
      };
      btrbk.snapshotRetain = {
        daily = lib.mkOption {
          type = lib.types.int;
          default = 2;
          description = "Default btrbk local snapshot retention (daily)";
        };
        weekly = lib.mkOption {
          type = lib.types.int;
          default = 1;
          description = "Default btrbk local snapshot retention (weekly)";
        };
      };
      timeout = lib.mkOption {
        type = lib.types.str;
        default = "6h";
        description = "Default systemd timeout for backup units";
      };
    };

    services = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (_: {
          options = {
            enable = lib.mkEnableOption "backup for this service";
            schedule = lib.mkOption {
              type = lib.types.str;
              default = "daily";
              description = "systemd OnCalendar schedule";
            };
            timeout = lib.mkOption {
              type = lib.types.str;
              default = cfg.defaults.timeout;
              description = "Systemd timeout for this backup";
            };
            retention = {
              daily = lib.mkOption {
                type = lib.types.int;
                default = cfg.defaults.retention.daily;
              };
              weekly = lib.mkOption {
                type = lib.types.int;
                default = cfg.defaults.retention.weekly;
              };
              monthly = lib.mkOption {
                type = lib.types.int;
                default = cfg.defaults.retention.monthly;
              };
            };
          };
        })
      );
      default = { };
      description = "Backup service definitions. Volumes are auto-discovered from lib/volumes.nix.";
    };
  };

  # ── Implementation ──────────────────────────────────────────────────
  config = lib.mkIf (cfg.services != { }) {

    # ── Top-level btrfs mounts for btrbk ──────────────────────────────
    fileSystems = builtins.listToAttrs (
      map (device: {
        name = btrbkMountPoint device;
        value = {
          device = "/dev/disk/by-uuid/${volumes.devices.${device}}";
          fsType = "btrfs";
          options = [
            "subvolid=5"
            "noatime"
            "nofail"
          ];
        };
      }) allBackupDevices
    );

    # ── Ensure snapshot directories exist ─────────────────────────────
    systemd.tmpfiles.rules = map (device: "d ${snapshotDir device} 0755 root root -") allBackupDevices;

    # ── Sops secrets for B2 + per-service restic passwords ──────────────
    sops.secrets = {
      b2_key_id = { };
      b2_application_key = { };
      restic_repo_base = { };
    }
    // builtins.listToAttrs (
      lib.mapAttrsToList (serviceName: _: {
        name = "restic_password_${serviceName}";
        value = { };
      }) cfg.services
    );

    sops.templates."restic-b2.env".content = ''
      AWS_ACCESS_KEY_ID=${config.sops.placeholder.b2_key_id}
      AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.b2_application_key}
      RESTIC_REPO_BASE=${config.sops.placeholder.restic_repo_base}
    '';

    # ── btrbk instances (one per service, no timer — triggered by our script) ─
    services.btrbk.instances = builtins.listToAttrs (
      lib.mapAttrsToList (
        serviceName: _:
        let
          svcVolumes = volumesForService serviceName;
          svcDevices = devicesForService serviceName;

          dailyRetain = toString cfg.defaults.btrbk.snapshotRetain.daily;
          weeklyRetain = toString cfg.defaults.btrbk.snapshotRetain.weekly;

          # Group volumes by device, then list subvolumes under each
          volumeSettings = builtins.listToAttrs (
            map (
              device:
              let
                volsOnDevice = builtins.attrNames (lib.filterAttrs (_: vol: vol.device == device) svcVolumes);
              in
              {
                name = btrbkMountPoint device;
                value = {
                  snapshot_dir = "docker-volumes/.snapshots";
                  subvolume = builtins.listToAttrs (
                    map (volName: {
                      name = "docker-volumes/@${volName}";
                      value = { };
                    }) volsOnDevice
                  );
                };
              }
            ) svcDevices
          );
        in
        {
          name = serviceName;
          value = {
            onCalendar = null; # No auto-timer — our systemd unit triggers snapshots
            settings = {
              backend = "btrfs-progs";
              snapshot_preserve_min = "${dailyRetain}d";
              snapshot_preserve = "${dailyRetain}d ${weeklyRetain}w";
              timestamp_format = "long";
              volume = volumeSettings;
            };
          };
        }
      ) cfg.services
    );

    # ── Per-service backup systemd units ──────────────────────────────
    systemd.services =
      builtins.listToAttrs (
        lib.mapAttrsToList (serviceName: serviceCfg: {
          name = "backup-${serviceName}";
          value = {
            description = "Backup: ${serviceName}";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            path = [
              pkgs.btrbk
              pkgs.btrfs-progs
              pkgs.restic
              pkgs.util-linux
              pkgs.coreutils
              pkgs.hostname
              pkgs.systemd
            ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${mkBackupScript serviceName serviceCfg}";
              TimeoutStartSec = serviceCfg.timeout;
              # Inherit restic env from sops
              EnvironmentFile = config.sops.templates."restic-b2.env".path;
            };
            onFailure = [ "notify-failure@%n.service" ];
          };
        }) cfg.services
      )
      # ── Per-service restic check units ──────────────────────────────
      // builtins.listToAttrs (
        lib.mapAttrsToList (serviceName: _: {
          name = "restic-check-${serviceName}";
          value = {
            description = "Restic integrity check: ${serviceName}";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${mkCheckScript serviceName}";
              TimeoutStartSec = "1h";
              EnvironmentFile = config.sops.templates."restic-b2.env".path;
            };
            onFailure = [ "notify-failure@%n.service" ];
          };
        }) cfg.services
      );

    # ── Per-service backup timers ─────────────────────────────────────
    systemd.timers =
      builtins.listToAttrs (
        lib.mapAttrsToList (serviceName: serviceCfg: {
          name = "backup-${serviceName}";
          value = {
            description = "Timer: backup ${serviceName}";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = serviceCfg.schedule;
              Persistent = true;
              RandomizedDelaySec = "15m";
            };
          };
        }) cfg.services
      )
      // builtins.listToAttrs (
        lib.mapAttrsToList (serviceName: _: {
          name = "restic-check-${serviceName}";
          value = {
            description = "Timer: restic integrity check ${serviceName}";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "weekly";
              Persistent = true;
              RandomizedDelaySec = "1h";
            };
          };
        }) cfg.services
      );

    # ── Diagnostic script ─────────────────────────────────────────────
    environment.systemPackages = [ mkDiagnosticScript ];
  };
}
