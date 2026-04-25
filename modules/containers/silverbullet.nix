{ config, ... }:

let
  images = import ../images.nix;
in
{
  # ── Volumes ───────────────────────────────────────────────────────────

  podman.volumes.silverbullet-space = {
    storage = "btrfs-hdd";
  };

  # ── Sops secrets ──────────────────────────────────────────────────────

  sops.secrets.base_domain = { };

  # ── Traefik routing ───────────────────────────────────────────────────

  sops.templates."silverbullet-routing.yaml".content = ''
    http:
      routers:
        silverbullet:
          rule: "Host(`silverbullet.${config.sops.placeholder.base_domain}`)"
          entryPoints:
            - websecure
          tls:
            certResolver: leresolver
          middlewares:
            - authelia
            - secure-headers
          service: silverbullet
      services:
        silverbullet:
          loadBalancer:
            servers:
              - url: "http://silverbullet:3000"
  '';

  virtualisation.oci-containers.containers.traefik.volumes = [
    "${
      config.sops.templates."silverbullet-routing.yaml".path
    }:/etc/traefik/dynamic/silverbullet.yaml:ro"
  ];

  # ── Container ─────────────────────────────────────────────────────────

  virtualisation.oci-containers.containers.silverbullet = {
    image = images.silverbullet;

    volumes = [
      "silverbullet-space:/space"
    ];

    environment = {
      PUID = "1000";
      GUID = "1000";
      TZ = "Europe/Rome";
    };

    log-driver = "journald";

    extraOptions = [
      "--network=podman"
      "--stop-timeout=30"
      "--cap-drop=ALL"
      "--cap-add=SETUID"
      "--cap-add=SETGID"
      "--security-opt=no-new-privileges:true"
    ];
  };

  # ── Systemd ordering ─────────────────────────────────────────────────

  systemd.services.podman-silverbullet = {
    after = [
      "podman-volume-silverbullet-space.service"
    ];
    requires = [
      "podman-volume-silverbullet-space.service"
    ];
    restartTriggers = [
      config.sops.templates."silverbullet-routing.yaml".content
    ];
  };

  # ── Backup ────────────────────────────────────────────────────────────

  backup.services.silverbullet = {
    enable = true;
    schedule = "03:00";
    timeout = "30m";
    volumes = [ "silverbullet-space" ];
  };

  # ── Homepage entry ──────────────────────────────────────────────────

  services.homepage.entries = [
    {
      group = "Other";
      name = "SilverBullet";
      icon = "silverbullet.png";
      href = "https://silverbullet.${config.sops.placeholder.base_domain}";
      container = "silverbullet";
      public = true;
    }
  ];
}
