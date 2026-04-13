# Centralized volume definitions — single source of truth.
# Both podman.nix (volume provisioning) and backup.nix (snapshot + offsite)
# consume this registry.
#
# Fields:
#   device:        "hdd" | "nvme" — which btrfs filesystem (null for plain volumes)
#   type:          "db" | "data" | "plain" — TODO: use for pg_dump pre-hooks, compression
#   backupService: name of the backup.services.<name> this volume belongs to (null = no backup)

let
  constants = import ./constants.nix;
  inherit (constants) hddUUID nvmeUUID;

  devices = {
    hdd = hddUUID;
    nvme = nvmeUUID;
  };
in
{
  inherit devices;

  # ── Btrfs-backed volumes (persistent data) ──────────────────────────
  btrfs = {
    # Immich
    immich-upload = {
      device = "hdd";
      type = "data";
      backupService = "immich";
    };
    immich-pgdata = {
      device = "nvme";
      type = "db";
      backupService = "immich";
    };

    # Authelia
    authelia-data = {
      device = "hdd";
      type = "db";
      backupService = "authelia";
    };

    # Apprise
    apprise-config = {
      device = "hdd";
      type = "data";
      backupService = null;
    };

    # SilverBullet
    silverbullet-space = {
      device = "hdd";
      type = "data";
      backupService = "silverbullet";
    };
  };

  # ── Plain volumes (disposable / regenerable) ────────────────────────
  plain = [
    "traefik-certs"
    "homepage-config-public"
    "homepage-config-private"
    "immich-model-cache"
  ];
}
