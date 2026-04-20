_:

{
  # ── zram ─────────────────────────────────────────────────────────────
  # In-memory compressed swap. First line of defense — fast and effective
  # for anonymous pages. Default priority is 5.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  # ── Disk swap ────────────────────────────────────────────────────────
  # 32 GiB swap file on scratch SSD @swap subvolume, created manually via
  # `btrfs filesystem mkswapfile` so nodatacow is set correctly for btrfs.
  # Low priority so zram is used first; disk swap is overflow only.
  swapDevices = [
    {
      device = "/mnt/scratch-ssd/swap/swapfile";
      priority = -2;
    }
  ];
}
