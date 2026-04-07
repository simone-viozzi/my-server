{ pkgs, ... }:

{
  users.users.simone = {
    isNormalUser = true;
    uid = 1000;
    description = "simone viozzi";
    shell = pkgs.zsh;
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJu0KWT56ZtuFnWuQvGnuNZo/36n4XJ4d6cyxfgTFMBH simone@simoserver"
    ];
  };

  # Passwordless sudo for single-user homelab
  security.sudo.wheelNeedsPassword = false;
}
