{ config, ... }:

let
  images = import ../images.nix;
in
{
  # ── Volumes ───────────────────────────────────────────────────────────

  podman.volumes.authelia-data = {
    storage = "btrfs-hdd";
  };

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
    image = images.authelia;

    update = {
      primary = true;
      repo = "authelia/authelia";
    };

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
      "--stop-timeout=30"
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
    restartTriggers = [
      config.sops.secrets.authelia_configuration.sopsFile
      config.sops.secrets.authelia_users_database.sopsFile
    ];
  };

  # ── Backup ────────────────────────────────────────────────────────────

  backup.services.authelia = {
    enable = true;
    schedule = "02:30";
    timeout = "30m";
    volumes = [ "authelia-data" ];
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
