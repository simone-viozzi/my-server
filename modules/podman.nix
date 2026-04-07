{ pkgs, ... }:

let
  helpers = import ../lib/podman-helpers.nix { inherit pkgs; };
  inherit (helpers) mkNetworkService mkVolumeService mkBtrfsVolumeService;

  # External Podman networks that must exist before containers start
  externalNetworks = [
    "proxy"
    "homepage-net"
    "dockerproxy"
  ];
in
{
  # ── Podman daemon ─────────────────────────────────────────────────────
  virtualisation.podman = {
    enable = true;
    # Docker-compatible socket so Homepage can auto-discover containers via labels
    dockerSocket.enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
      # --all: prunes all unused images (not just dangling/untagged)
      # --volumes: prunes unused volumes
      # Note: stopped containers are NOT removed by system prune
      flags = [
        "--all"
        "--volumes"
      ];
    };
  };

  virtualisation.oci-containers.backend = "podman";

  # ── External networks and volumes ─────────────────────────────────────
  systemd.services =
    builtins.listToAttrs (
      map (name: {
        name = "podman-network-${name}";
        value = mkNetworkService name;
      }) externalNetworks
    )
    // {
      # Plain volumes (disposable/regenerable data)
      podman-volume-traefik-certs = mkVolumeService "traefik-certs";
      # Btrfs-backed volumes (persistent data on HDD)
      podman-volume-authelia-data = mkBtrfsVolumeService "authelia-data" "authelia-data";
    };
}
