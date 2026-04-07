{ pkgs }:

let
  constants = import ./constants.nix;
  inherit (constants) hddUUID;
  ensureBtrfsVolume = ../scripts/ensure-btrfs-volume.sh;
in
{
  # Create a systemd oneshot that ensures a Podman network exists
  # Lifecycle: unused networks/volumes get cleaned up by Podman's weekly autoPrune
  mkNetworkService = name: {
    description = "Ensure Podman network: ${name}";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "podman-network-${name}" ''
        ${pkgs.podman}/bin/podman network inspect ${name} >/dev/null 2>&1 || \
          ${pkgs.podman}/bin/podman network create ${name}
      '';
    };
  };

  # Create a systemd oneshot that ensures a plain Podman volume exists
  # (for disposable/regenerable data like certs, caches)
  mkVolumeService = name: {
    description = "Ensure Podman volume: ${name}";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "podman-volume-${name}" ''
        ${pkgs.podman}/bin/podman volume inspect ${name} >/dev/null 2>&1 || \
          ${pkgs.podman}/bin/podman volume create ${name}
      '';
    };
  };

  # Create a systemd oneshot that ensures a Podman volume backed by
  # a btrfs subvolume on the HDD exists.
  # Usage: mkBtrfsVolumeService "immich-upload" "immich-upload"
  #   -> podman volume "immich-upload" backed by subvol docker-volumes/@immich-upload
  mkBtrfsVolumeService = volumeName: subvolName: {
    description = "Ensure Podman btrfs volume: ${volumeName}";
    wantedBy = [ "multi-user.target" ];
    path = [
      pkgs.podman
      pkgs.btrfs-progs
      pkgs.util-linux
      pkgs.coreutils
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash ${ensureBtrfsVolume} ${volumeName} ${subvolName} ${hddUUID}";
    };
  };
}
