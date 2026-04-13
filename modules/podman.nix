{
  pkgs,
  lib,
  config,
  ...
}:

let
  helpers = import ../lib/podman-helpers.nix { inherit pkgs; };
  inherit (helpers) mkNetworkService mkVolumeService mkBtrfsVolumeService;
  volumes = import ../lib/volumes.nix;

  # Generate podman-volume-* services from centralized volume definitions
  btrfsVolumeServices = lib.mapAttrs' (
    name: vol:
    lib.nameValuePair "podman-volume-${name}" (
      mkBtrfsVolumeService name name volumes.devices.${vol.device}
    )
  ) volumes.btrfs;

  plainVolumeServices = builtins.listToAttrs (
    map (name: {
      name = "podman-volume-${name}";
      value = mkVolumeService name;
    }) volumes.plain
  );

in
{
  # ── Podman daemon ─────────────────────────────────────────────────────
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

  # ── Auto-apply onFailure to all containers ────────────────────────────
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
    // {
      # ── Networks ──────────────────────────────────────────────────────
      podman-network-isolated = mkNetworkService "isolated" { internal = true; };
    }
    // btrfsVolumeServices
    // plainVolumeServices;
}
