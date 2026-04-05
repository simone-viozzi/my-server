{ config, pkgs, ... }:

{
  imports = [
    ./modules/base.nix
    ./modules/nh.nix
  ];

  networking.hostName = "simoserver";
  networking.networkmanager.enable = true;

  # User account
  users.users.simone = {
    isNormalUser = true;
    description = "simone viozzi";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  # Set to the NixOS version at install time, never change afterward
  system.stateVersion = "25.11";
}
