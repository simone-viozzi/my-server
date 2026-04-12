{ config, ... }:

{
  # ── Sops secrets ──────────────────────────────────────────────────────

  # Full config files (encrypted as binary blobs in sops)
  sops.secrets.authelia_configuration = {
    sopsFile = ../../secrets/authelia-config.bin.yaml;
    format = "binary";
    # Owned by simone (UID 1000) so the container (user = "1000:1000") can read them
    # sops decrypts to /run/secrets/ with mode 0400 — only this user can access
    owner = "simone";
    group = "users";
  };
  sops.secrets.authelia_users_database = {
    sopsFile = ../../secrets/authelia-users.bin.yaml;
    format = "binary";
    owner = "simone";
    group = "users";
  };

  sops.secrets.base_domain = { };

  # ── Traefik routing (file provider, domain from sops) ─────────────────

  sops.templates."authelia-routing.yaml".content = ''
    http:
      routers:
        authelia:
          rule: "Host(`auth.${config.sops.placeholder.base_domain}`)"
          entryPoints:
            - websecure
          tls:
            certResolver: leresolver
          middlewares:
            - secure-headers
          service: authelia
      services:
        authelia:
          loadBalancer:
            servers:
              - url: "http://authelia:9091"
  '';

  # Mount authelia's routing config into Traefik's dynamic config directory
  virtualisation.oci-containers.containers.traefik.volumes = [
    "${config.sops.templates."authelia-routing.yaml".path}:/etc/traefik/dynamic/authelia.yaml:ro"
  ];

  # ── Container ─────────────────────────────────────────────────────────

  virtualisation.oci-containers.containers.authelia = {
    image = "authelia/authelia:4.39.16@sha256:edbce01c5125249e4f4faea01e0f76f0031d64b4a1d0c2514a0ca69cb126d05f";

    user = "1000:1000";

    volumes = [
      "${config.sops.secrets.authelia_configuration.path}:/config/configuration.yml:ro"
      "${config.sops.secrets.authelia_users_database.path}:/config/users_database.yml:ro"
      # Stores SQLite DB (user sessions, 2FA registrations) — NOT disposable
      "authelia-data:/var/lib/authelia"
    ];

    environment = {
      TZ = "Europe/Rome";
    };

    log-driver = "journald";

    extraOptions = [
      "--network=podman"
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges:true"
      "--tmpfs=/tmp"
    ];
  };

  # ── Systemd ordering ─────────────────────────────────────────────────

  systemd.services.podman-authelia = {
    after = [
      "podman-volume-authelia-data.service"
    ];
    requires = [
      "podman-volume-authelia-data.service"
    ];
  };

  # ── Homepage entry ──────────────────────────────────────────────────

  services.homepage.entries = [
    {
      group = "Network";
      name = "Authelia";
      icon = "authelia.svg";
      href = "https://authelia.${config.sops.placeholder.base_domain}";
      container = "authelia";
    }
  ];
}
