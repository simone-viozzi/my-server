{ ... }:

{
  imports = [
    ./modules/base.nix
    ./modules/disk.nix
    ./modules/networking.nix
    ./modules/users.nix
    ./modules/nh.nix
    ./modules/podman.nix
    ./modules/containers/traefik.nix
    ./modules/containers/authelia.nix
  ];

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
