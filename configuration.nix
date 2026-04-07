{ pkgs, ... }:

{
  imports = [
    ./modules/base.nix
    ./modules/networking.nix
    ./modules/nh.nix
  ];

  networking = {
    hostName = "simoserver";
    networkmanager.enable = true;
  };

  # Enable zsh system-wide (required when it's a user's login shell)
  programs.zsh.enable = true;

  # User account
  users.users.simone = {
    isNormalUser = true;
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

  # Set to the NixOS version at install time, never change afterward
  system.stateVersion = "25.11";
}
