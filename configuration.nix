{ ... }:

{
  imports = [
    ./modules/base.nix
    ./modules/networking.nix
    ./modules/users.nix
    ./modules/nh.nix
  ];

  networking = {
    hostName = "simoserver";
    networkmanager.enable = true;
  };

  # Set to the NixOS version at install time, never change afterward
  system.stateVersion = "25.11";
}
