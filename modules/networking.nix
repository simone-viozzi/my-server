_:

{
  # Loopback overrides — mirrors TRAEFIK_PROXY_ALIASES in traefik.nix so
  # host-side traffic to Traefik-proxied services skips the WAN hairpin.
  # Traefik binds 0.0.0.0:443 on the host, so 127.0.0.1 reaches it directly.
  networking.hosts."127.0.0.1" = [
    "simoserver.top"
    "apprise.simoserver.top"
    "auth.simoserver.top"
    "collabora.simoserver.top"
    "collaboration.simoserver.top"
    "homepage-private.simoserver.top"
    "immich.simoserver.top"
    "karakeep.simoserver.top"
    "ocis.simoserver.top"
    "paperless.simoserver.top"
    "pdf.simoserver.top"
    "resume.simoserver.top"
    "silverbullet.simoserver.top"
    "traefik.simoserver.top"
  ];

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
