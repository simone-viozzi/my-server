{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (import ../lib/notify.nix { inherit pkgs; }) notifyMd;
  constants = import ../lib/constants.nix;
  inherit (constants) storageDevices;

  cfg = config.backup;
  allVolumes = config.podman.volumes;

  deviceName = storage: storageDevices.${storage}.name;

  deviceToUUID = builtins.listToAttrs (
    lib.mapAttrsToList (_: sd: {
      inherit (sd) name;
      value = sd.uuid;
    }) storageDevices
  );

  volumesForService =
    serviceName:
    let
      svcCfg = cfg.services.${serviceName};
    in
    lib.listToAttrs (
      map (volName: {
        name = volName;
        value = allVolumes.${volName};
      }) svcCfg.volumes
    );

  devicesForService =
    serviceName:
    lib.unique (lib.mapAttrsToList (_: vol: deviceName vol.storage) (volumesForService serviceName));

  allBackupDevices = lib.unique (lib.concatMap devicesForService (builtins.attrNames cfg.services));

  btrbkMountPoint = device: "/mnt/btrbk/${device}";
  snapshotDir = device: "${btrbkMountPoint device}/docker-volumes/.snapshots";
  # Stable path dir: one `@<vol>` CoW snapshot per volume, replaced each run.
  # Restic sees an identical source path across runs → parent lookup + per-file
  # reuse work. Independent of btrbk retention.
  currentDir = device: "${btrbkMountPoint device}/docker-volumes/.current";

  lockFile = "/var/lock/backup.lock";

  containersForService =
    serviceName:
    builtins.filter (name: lib.hasPrefix "${serviceName}-" name || name == serviceName) (
      builtins.attrNames config.virtualisation.oci-containers.containers
    );

  # Per-service JSON config consumed by backup.sh
  mkBackupConfig =
    serviceName: serviceCfg:
    pkgs.writeText "backup-${serviceName}.json" (
      builtins.toJSON {
        service = serviceName;
        containers = containersForService serviceName;
        inherit lockFile;
        btrbkConfig = "/etc/btrbk/${serviceName}.conf";
        retention = {
          inherit (serviceCfg.retention) daily weekly monthly;
        };
        volumes = lib.mapAttrsToList (volName: vol: {
          name = volName;
          snapshotDir = snapshotDir (deviceName vol.storage);
          currentDir = currentDir (deviceName vol.storage);
        }) (volumesForService serviceName);
      }
    );

  # Shared static runner. Shellcheck runs at build time.
  backupRunner = pkgs.writeShellApplication {
    name = "backup-runner";
    runtimeInputs = with pkgs; [
      btrbk
      btrfs-progs
      restic
      util-linux
      coreutils
      hostname
      systemd
      jq
      gnugrep
    ];
    text = builtins.readFile ./backup/backup.sh;
  };

  # Manifest consumed by restore.sh. Carries `livePath` and `containers` even
  # though the current commands never write to live data — the deferred
  # in-place `swap` needs them, and baking them in now keeps that additive.
  mkRestoreConfig = pkgs.writeText "backup-restore.json" (
    builtins.toJSON {
      inherit lockFile;
      services = lib.mapAttrs (serviceName: _: {
        passwordFile = config.sops.secrets."restic_password_${serviceName}".path;
        containers = containersForService serviceName;
        volumes = lib.mapAttrsToList (volName: vol: {
          name = volName;
          device = deviceName vol.storage;
          livePath = "${btrbkMountPoint (deviceName vol.storage)}/docker-volumes/@${volName}";
        }) (volumesForService serviceName);
      }) cfg.services;
    }
  );

  restoreRunner = pkgs.writeShellApplication {
    name = "backup-restore";
    runtimeInputs = with pkgs; [
      restic
      jq
      coreutils
      findutils
    ];
    text = ''
      export RESTORE_CONFIG="${mkRestoreConfig}"
      export RESTIC_ENV_FILE="${config.sops.templates."restic-b2.env".path}"
    ''
    + builtins.readFile ./backup/restore.sh;
  };

  mkCheckScript =
    serviceName:
    pkgs.writeShellScript "restic-check-${serviceName}" ''
      set -euo pipefail
      # Bare `check` only validates repository structure and metadata — it never
      # downloads a data blob, so it cannot tell us the backups are actually
      # retrievable. --read-data-subset fetches and hashes real data each run.
      echo "=== Restic integrity check: ${serviceName} (data subset ${
        cfg.services.${serviceName}.checkSubset
      }) ==="
      ${pkgs.restic}/bin/restic \
        -r "''${RESTIC_REPO_BASE}/${serviceName}" \
        --password-file ${config.sops.secrets."restic_password_${serviceName}".path} \
        check --read-data-subset=${cfg.services.${serviceName}.checkSubset}
      echo "=== Check OK: ${serviceName} ==="
    '';

  mkDiagnosticScript =
    let
      mkServiceBlock =
        serviceName: serviceCfg:
        let
          svcVolumes = volumesForService serviceName;
          containers = containersForService serviceName;
          volumeLines = lib.concatStringsSep "\n" (
            lib.mapAttrsToList (volName: vol: "echo '    ${volName} (${vol.storage})'") svcVolumes
          );
        in
        ''
          echo "Service: ${serviceName}"
          echo "  Schedule: ${serviceCfg.schedule}"
          echo "  Timeout: ${serviceCfg.timeout}"
          echo "  Containers: ${lib.concatStringsSep ", " containers}"
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
      checkSubset = lib.mkOption {
        type = lib.types.str;
        default = "2G";
        description = ''
          How much real data each weekly `restic check` downloads and hashes,
          as a restic --read-data-subset value (a size, 'x%', or 'n/t').

          A size is used rather than 'n/t' because repo sizes here span four
          orders of magnitude: an 'n/53' split leaves small repos (authelia is
          8 packs) with mostly empty groups that verify nothing. With a size,
          repos smaller than this are read in full every week, and large ones
          are randomly sampled at a bounded, predictable egress cost.
        '';
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
            checkSubset = lib.mkOption {
              type = lib.types.str;
              default = cfg.defaults.checkSubset;
              description = "restic --read-data-subset value for this service's weekly check";
            };
            volumes = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "List of podman.volumes names to back up for this service";
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
      description = "Backup service definitions. Volumes reference names from podman.volumes.";
    };
  };

  # ── Implementation ──────────────────────────────────────────────────
  config = lib.mkIf (cfg.services != { }) {

    # ── Top-level btrfs mounts for btrbk ──────────────────────────────
    fileSystems = builtins.listToAttrs (
      map (device: {
        name = btrbkMountPoint device;
        value = {
          device = "/dev/disk/by-uuid/${deviceToUUID.${device}}";
          fsType = "btrfs";
          options = [
            "subvolid=5"
            "noatime"
            "nofail"
          ];
        };
      }) allBackupDevices
    );

    # ── Ensure snapshot directories + restic cache exist ──────────────
    systemd.tmpfiles.rules =
      map (device: "d ${snapshotDir device} 0755 root root -") allBackupDevices
      ++ map (device: "d ${currentDir device} 0755 root root -") allBackupDevices
      ++ [
        "d /var/cache/restic 0700 root root -"
        "d /var/lib/backup-restore 0700 root root -"
      ];

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

          volumeSettings = builtins.listToAttrs (
            map (
              device:
              let
                volsOnDevice = builtins.attrNames (
                  lib.filterAttrs (_: vol: deviceName vol.storage == device) svcVolumes
                );
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
            onCalendar = null;
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
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${backupRunner}/bin/backup-runner";
              TimeoutStartSec = serviceCfg.timeout;
              EnvironmentFile = config.sops.templates."restic-b2.env".path;
              Environment = [
                "XDG_CACHE_HOME=/var/cache/restic"
                "SERVICE=${serviceName}"
                "BACKUP_CONFIG=${mkBackupConfig serviceName serviceCfg}"
                "RESTIC_PASSWORD_FILE=${config.sops.secrets."restic_password_${serviceName}".path}"
                "NOTIFY_BIN=${notifyMd}"
              ];
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
              # The check now downloads a slice of real data, not just metadata.
              # ocis is ~125G at 5%, so one weekly slice is ~6.3G over the wire —
              # 1h was sized for a metadata-only check and would time out.
              TimeoutStartSec = "3h";
              EnvironmentFile = config.sops.templates."restic-b2.env".path;
              Environment = "XDG_CACHE_HOME=/var/cache/restic";
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
    environment.systemPackages = [
      mkDiagnosticScript
      restoreRunner
    ];
  };
}
