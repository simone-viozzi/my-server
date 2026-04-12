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
  inherit (constants) hddUUID nvmeUUID;

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
      # Default "podman" network: all containers, DNS-enabled.
      # "isolated" internal network: no external access, for sensitive services
      # (dockerproxy, databases). Containers needing both Traefik routing AND
      # isolated access join both networks (safe — multi-network bug only
      # affects port-publishing containers, i.e. Traefik).
      podman-network-isolated = mkNetworkService "isolated" { internal = true; };

      # ── Volumes ───────────────────────────────────────────────────────
      # Plain volumes (disposable/regenerable data)
      podman-volume-traefik-certs = mkVolumeService "traefik-certs";
      podman-volume-homepage-config-public = mkVolumeService "homepage-config-public";
      podman-volume-homepage-config-private = mkVolumeService "homepage-config-private";

      # Btrfs-backed volumes (persistent data on HDD)
      podman-volume-authelia-data = mkBtrfsVolumeService "authelia-data" "authelia-data" hddUUID;
      podman-volume-apprise-config = mkBtrfsVolumeService "apprise-config" "apprise-config" hddUUID;

      # SilverBullet volumes
      podman-volume-silverbullet-space =
        mkBtrfsVolumeService "silverbullet-space" "silverbullet-space"
          hddUUID;

      # Immich volumes
      podman-volume-immich-upload = mkBtrfsVolumeService "immich-upload" "immich-upload" hddUUID;
      podman-volume-immich-pgdata = mkBtrfsVolumeService "immich-pgdata" "immich-pgdata" nvmeUUID;
      podman-volume-immich-model-cache = mkVolumeService "immich-model-cache";
    };
}
