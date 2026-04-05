{ config, pkgs, ... }:

{
  imports = [
    ./modules/base.nix
    ./modules/nh.nix
  ];

  networking.hostName = "simoserver";
  networking.networkmanager.enable = true;

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
  };

  # Set to the NixOS version at install time, never change afterward
  system.stateVersion = "25.11";
}
