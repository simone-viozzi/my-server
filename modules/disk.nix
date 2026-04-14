_:

let
  constants = import ../lib/constants.nix;
in
{
  # ── HDD (WD Red 4TB, btrfs) ──────────────────────────────────────────
  # Bulk storage disk with btrfs subvolumes for container data.
  # @data subvolume used as staging/scratch area.
  fileSystems."/home/simone/data" = {
    device = "/dev/disk/by-uuid/${constants.storageDevices."btrfs-hdd".uuid}";
    fsType = "btrfs";
    options = [
      "subvol=@data"
      "noatime"
      "compress=zstd"
      "nofail"
    ];
  };

  # ── Old SSD (Kingston SA400 240GB, btrfs) ─────────────────────────────
  # Former Arch Linux OS disk — kept intact as rollback safety net.
  # Mounted read-only until migration is fully validated.
  #
  # TODO (post-migration, once rollback is no longer needed):
  #   1. Repartition: ~40GB swap + rest for /var/lib/containers
  #   2. Replace this mount with swap + containers storage
  #   3. This offloads image layers from NVMe (disposable, churn-heavy)
  fileSystems."/mnt/old-ssd" = {
    device = "/dev/disk/by-uuid/3d2df933-a2fb-4042-8cf3-b61e157dddb0";
    fsType = "btrfs";
    options = [
      "subvol=@"
      "ro"
      "nofail"
    ];
  };
}
