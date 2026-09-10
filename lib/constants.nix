{
  # Public domain, needed at *evaluation* time — `networking.hosts` compiles
  # into /etc/hosts as a build-time store path, so it cannot read the sops
  # `base_domain` secret (a sops placeholder is only substituted at activation,
  # when templates are rendered). Container modules that build their config at
  # activation time keep using `config.sops.placeholder.base_domain` instead.
  #
  # To stop publishing the domain later, move this value into a gitignored
  # file and import it here — every consumer follows automatically.
  domain = "simoserver.top";

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
    "btrfs-scratch-ssd" = {
      uuid = "3d2df933-a2fb-4042-8cf3-b61e157dddb0"; # Kingston SA400 240GB
      name = "scratch-ssd";
    };
  };
}
