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

  # ── Scratch SSD (Kingston SA400 240GB, btrfs) ─────────────────────────
  # Holds swap file + podman graphroot (container images/layers) — all
  # re-creatable workloads offloaded from NVMe.
  fileSystems."/mnt/scratch-ssd/swap" = {
    device = "/dev/disk/by-uuid/${constants.storageDevices."btrfs-scratch-ssd".uuid}";
    fsType = "btrfs";
    options = [
      "subvol=@swap"
      "noatime"
      "nofail"
    ];
  };

  fileSystems."/mnt/scratch-ssd/containers" = {
    device = "/dev/disk/by-uuid/${constants.storageDevices."btrfs-scratch-ssd".uuid}";
    fsType = "btrfs";
    options = [
      "subvol=@container-storage"
      "noatime"
      "compress=zstd"
      "nofail"
    ];
  };
}
