_:

{
  # Firewall — only non-Docker ports need opening here.
  # Docker publishes container ports by modifying iptables directly.
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      29902 # SSH
    ];
  };

  # SSH — key-only, non-standard port, hardened
  services.openssh = {
    enable = true;
    ports = [ 29902 ];
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      X11Forwarding = false;
      ClientAliveInterval = 60;
      # Only strong key exchange, ciphers, and MACs
      KexAlgorithms = [
        "mlkem768x25519-sha256"
        "sntrup761x25519-sha512@openssh.com"
        "curve25519-sha256"
        "curve25519-sha256@libssh.org"
      ];
      Ciphers = [
        "chacha20-poly1305@openssh.com"
        "aes256-gcm@openssh.com"
        "aes128-gcm@openssh.com"
      ];
      Macs = [
        "hmac-sha2-512-etm@openssh.com"
        "hmac-sha2-256-etm@openssh.com"
      ];
    };
    extraConfig = ''
      HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
    '';
    # Only Ed25519 and RSA host keys (no DSA/ECDSA)
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
      {
        path = "/etc/ssh/ssh_host_rsa_key";
        type = "rsa";
        bits = 4096;
      }
    ];
  };
}
