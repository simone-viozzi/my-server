{ lib, ... }:

let
  # ── Stack switchboard ─────────────────────────────────────────────────
  # One toggle per container stack. Setting a stack to false means its module
  # is never imported, so the whole stack disappears from the system:
  # container, bridge network, volume units, host mounts, backup and restic
  # timers, Traefik routing and homepage entry. Data subvolumes on disk are
  # left untouched — flipping back to true brings the stack up as it was.
  stacks = {
    traefik = true;
    authelia = true;
    apprise = true;
    dockerproxy = true;
    homepage = true;
    immich = true;
    silverbullet = false;
    reactive-resume = true;
    paperless = true;
    karakeep = true;
    bentopdf = true;
    ocis = true;
  };

  enabledStacks = lib.mapAttrsToList (name: _: ./modules/containers + "/${name}.nix") (
    lib.filterAttrs (_: enabled: enabled) stacks
  );
in
{
  imports = [
    ./modules/base.nix
    ./modules/disk.nix
    ./modules/swap.nix
    ./modules/networking.nix
    ./modules/users.nix
    ./modules/nh.nix
    ./modules/podman.nix
    ./modules/container-updates.nix
    ./modules/backup.nix
    ./modules/notifications.nix
    ./modules/version-check.nix
  ]
  ++ enabledStacks;

  networking = {
    hostName = "simoserver";
    networkmanager.enable = true;
  };

  # ── Secrets (sops-nix) ────────────────────────────────────────────────
  sops = {
    defaultSopsFile = ./secrets/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  # Set to the NixOS version at install time, never change afterward
  system.stateVersion = "25.11";
}
