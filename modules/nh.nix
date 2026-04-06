_:

{
  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.extraArgs = "--keep-since 15d --keep 4";
    flake = "/home/simone/nixos";
  };
}
