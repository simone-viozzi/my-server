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
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOaHjCI2Ci+mljau38v8rfbHH8QskCjbdcPy3YYstzNupKScjQSHmKS5JAwIq7QPyEZgUpdACOM+44ilGU8X/aY= u0_a421@localhost"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMSF/rBHsPSuKaeFgHKZSbg0XWWwl9ANuhDm+jQ9Fevr claudia.ramundi@LAPTOP-284NO12M"
    ];
  };

  # TODO mhh to be removed... you can't run stuff with sudo
  # Passwordless sudo for single-user homelab
  security.sudo.wheelNeedsPassword = false;
}
