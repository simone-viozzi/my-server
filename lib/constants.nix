{
  # Map podman.volumes storage types to device UUIDs and names
  storageDevices = {
    "btrfs-hdd" = {
      uuid = "f0a2893d-bb2f-4b41-ba46-2089fc40266a"; # WD Red 4TB HDD
      name = "hdd";
    };
    "btrfs-nvme" = {
      uuid = "9b18d2f7-f6ab-4a38-ab23-8953e2814bd5"; # WD Red SN700 1TB NVMe
      name = "nvme";
    };
  };
}
