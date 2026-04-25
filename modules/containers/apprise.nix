{ config, ... }:

let
  images = import ../images.nix;
in
{
  # ── Volumes ───────────────────────────────────────────────────────────

  podman.volumes.apprise-config = {
    storage = "btrfs-hdd";
  };

  sops.secrets.base_domain = { };

  # ── Traefik routing (domain from sops) ────────────────────────────────

  sops.templates."apprise-routing.yaml".content = ''
    http:
      routers:
        apprise:
          rule: "Host(`apprise.${config.sops.placeholder.base_domain}`)"
          entryPoints:
            - websecure
          tls:
            certResolver: leresolver
          middlewares:
            - authelia
            - secure-headers
          service: apprise
      services:
        apprise:
          loadBalancer:
            servers:
              - url: "http://apprise:8000"
  '';

  # Mount routing config into Traefik's dynamic config directory
  virtualisation.oci-containers.containers.traefik.volumes = [
    "${config.sops.templates."apprise-routing.yaml".path}:/etc/traefik/dynamic/apprise.yaml:ro"
  ];

  # ── Container ─────────────────────────────────────────────────────────

  virtualisation.oci-containers.containers.apprise = {
    image = images.apprise;

    user = "1000:1000";

    volumes = [
      "apprise-config:/config"
    ];

    # Localhost-only for host systemd services (boot-notify, notify-failure)
    # External access goes through Traefik + Authelia
    ports = [
      "127.0.0.1:8000:8000"
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

  systemd.services.podman-apprise = {
    after = [
      "podman-volume-apprise-config.service"
    ];
    requires = [
      "podman-volume-apprise-config.service"
    ];
  };

  # ── Homepage entry ──────────────────────────────────────────────────

  services.homepage.entries = [
    {
      group = "Update & Monitor";
      name = "Apprise";
      icon = "apprise.svg";
      href = "https://apprise.${config.sops.placeholder.base_domain}";
      container = "apprise";
    }
  ];
}
