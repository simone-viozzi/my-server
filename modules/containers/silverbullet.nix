{ config, ... }:

{
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
    image = "docker.io/zefhemel/silverbullet:latest@sha256:6c36ff15f2230dbe3bca7e5d0c85a59c7dc831ce694517850ed5797775824d71";

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

  # ── Homepage entry ──────────────────────────────────────────────────

  services.homepage.entries = [
    {
      group = "Other";
      name = "SilverBullet";
      icon = "silverbullet.png";
      href = "https://silverbullet.${config.sops.placeholder.base_domain}";
      container = "silverbullet";
    }
  ];
}
