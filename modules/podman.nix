{ pkgs, ... }:

let
  helpers = import ../lib/podman-helpers.nix { inherit pkgs; };
  inherit (helpers) mkVolumeService mkBtrfsVolumeService;

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

  # ── Volumes ───────────────────────────────────────────────────────────
  # All containers use the default "podman" network (no custom networks needed).
  # If we later need isolation for sensitive containers, add an internal network:
  #   podman-network-isolated = mkNetworkService "isolated" { internal = true; };
  systemd.services = {
    # Plain volumes (disposable/regenerable data)
    podman-volume-traefik-certs = mkVolumeService "traefik-certs";
    # Btrfs-backed volumes (persistent data on HDD)
    podman-volume-authelia-data = mkBtrfsVolumeService "authelia-data" "authelia-data";
  };
}
