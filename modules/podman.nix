{
  pkgs,
  lib,
  config,
  ...
}:

let
  helpers = import ../lib/podman-helpers.nix { inherit pkgs; };
  inherit (helpers) mkNetworkService mkVolumeService mkBtrfsVolumeService;
  constants = import ../lib/constants.nix;
  inherit (constants) storageDevices;

  cfg = config.podman;

  btrfsVolumes = lib.filterAttrs (_: vol: vol.storage != "plain") cfg.volumes;
  plainVolumes = lib.filterAttrs (_: vol: vol.storage == "plain") cfg.volumes;

  btrfsVolumeServices = lib.mapAttrs' (
    name: vol:
    lib.nameValuePair "podman-volume-${name}" (
      mkBtrfsVolumeService name name storageDevices.${vol.storage}.uuid
    )
  ) btrfsVolumes;

  plainVolumeServices = lib.mapAttrs' (
    name: _: lib.nameValuePair "podman-volume-${name}" (mkVolumeService name)
  ) plainVolumes;

in
{
  # ── Options ──────────────────────────────────────────────────────────
  options.podman.volumes = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          storage = lib.mkOption {
            type = lib.types.enum [
              "plain"
              "btrfs-hdd"
              "btrfs-nvme"
            ];
            default = "plain";
            description = "Storage backend: plain (default podman), btrfs-hdd, or btrfs-nvme";
          };
          # TODO: contentType ("data" | "db") — for pg_dump pre-hooks, compression hints
        };
      }
    );
    default = { };
    description = "Podman volume definitions. Each container module declares its own volumes here.";
  };

  options.podman.networks = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = ''
      Bridge networks contributed by individual stack modules. Declaring a
      network here (rather than in the central list below) means it disappears
      along with the stack when the stack is disabled.
    '';
  };

  # ── Config ───────────────────────────────────────────────────────────
  config = {
    # ── Podman daemon ──────────────────────────────────────────────────
    virtualisation.podman = {
      enable = true;
      # Docker-compatible socket so Homepage can auto-discover containers via labels
      dockerSocket.enable = true;
      # Enable DNS on the default "podman" network so containers resolve each other by name
      defaultNetwork.settings.dns_enabled = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
        # --all: prunes all unused images (not just dangling/untagged)
        # --volumes: prunes unused volumes
        # Note: stopped containers are NOT removed by system prune
        flags = [
          "--all"
        ];
      };
    };

    virtualisation.oci-containers.backend = "podman";

    # Don't seed container /etc/hosts from the host's file. networking.nix maps
    # the *.simoserver.top names to 127.0.0.1 as a host-side loopback shortcut to
    # Traefik; leaking those into containers makes them resolve sibling services
    # to their own loopback (e.g. collaboration → collabora → 127.0.0.1:443,
    # connection refused). Containers must resolve those names via real DNS.
    virtualisation.containers.containersConf.settings.containers.base_hosts_file = "none";

    # Image layers and metadata live on the scratch SSD (offloaded from NVMe).
    # The /mnt/scratch-ssd/containers subvol is mounted via modules/disk.nix.
    virtualisation.containers.storage.settings.storage = {
      driver = "overlay";
      graphroot = "/mnt/scratch-ssd/containers";
      runroot = "/run/containers/storage";
    };

    # ── Auto-apply onFailure to all containers ─────────────────────────
    # NixOS's immutable /etc prevents global systemd drop-ins, so we apply
    # onFailure per-container here instead.
    systemd.services =
      (lib.mapAttrs' (
        name: _:
        lib.nameValuePair "podman-${name}" {
          onFailure = [ "notify-failure@%n.service" ];
          # SIGTERM (143) is normal for container stops — don't treat as failure
          serviceConfig.SuccessExitStatus = "143";
        }
      ) config.virtualisation.oci-containers.containers)
      # ── Networks ─────────────────────────────────────────────────────
      # TODO: distribute these per-stack into each module instead of a
      # central list (see memory: project_todo_per_stack_network_decl).
      // (
        let
          bridgeNets = cfg.networks ++ [
            "proxy"
            "apprise-net"
            "authelia-net"
            "bentopdf-net"
            "karakeep-net"
            "reactive-resume-net"
            "paperless-net"
            "immich-net"
            "homepage-net"
            "ocis-net"
          ];
        in
        lib.listToAttrs (
          map (n: lib.nameValuePair "podman-network-${n}" (mkNetworkService n { })) bridgeNets
        )
      )
      // btrfsVolumeServices
      // plainVolumeServices
      // {
        # Keep the Docker-API translator resident; default 5s idle timeout
        # caused podman.service to cycle on every Homepage/dockerproxy poll.
        podman.serviceConfig.ExecStart = [
          ""
          "${pkgs.podman}/bin/podman $LOGGING system service --time=0"
        ];
      };
  };
}
