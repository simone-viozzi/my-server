{ config, ... }:

let
  images = import ../images.nix;
in
{
  # ── Sops secrets ──────────────────────────────────────────────────────

  sops.secrets.base_domain = { };

  # ── Traefik routing ───────────────────────────────────────────────────

  sops.templates."bentopdf-routing.yaml".content = ''
    http:
      routers:
        bentopdf:
          rule: "Host(`pdf.${config.sops.placeholder.base_domain}`)"
          entryPoints:
            - websecure
          tls:
            certResolver: leresolver
          middlewares:
            - authelia
            - secure-headers
          service: bentopdf
      services:
        bentopdf:
          loadBalancer:
            servers:
              - url: "http://bentopdf:8080"
  '';

  virtualisation.oci-containers.containers.traefik.volumes = [
    "${config.sops.templates."bentopdf-routing.yaml".path}:/etc/traefik/dynamic/bentopdf.yaml:ro"
  ];

  # ── Container ─────────────────────────────────────────────────────────

  virtualisation.oci-containers.containers.bentopdf = {
    image = images.bentopdf;

    update = {
      primary = true;
      repo = "alam00000/bentopdf";
    };

    environment = {
      TZ = "Europe/Rome";
    };

    log-driver = "journald";

    extraOptions = [
      "--network=bentopdf-net"
      "--network=proxy"
      "--stop-timeout=30"
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges:true"
    ];
  };

  # ── Systemd ordering ─────────────────────────────────────────────────

  systemd.services.podman-bentopdf = {
    after = [
      "podman-network-bentopdf-net.service"
      "podman-network-proxy.service"
    ];
    requires = [
      "podman-network-bentopdf-net.service"
      "podman-network-proxy.service"
    ];
    restartTriggers = [
      config.sops.templates."bentopdf-routing.yaml".content
    ];
  };

  # ── Homepage entry ──────────────────────────────────────────────────

  services.homepage.entries = [
    {
      group = "Other";
      name = "BentoPDF";
      icon = "bentopdf.svg";
      href = "https://pdf.${config.sops.placeholder.base_domain}";
      container = "bentopdf";
      public = true;
    }
  ];
}
