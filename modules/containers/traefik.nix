{ config, ... }:

let
  images = import ../images.nix;
in
{
  # ── Volumes ───────────────────────────────────────────────────────────

  podman.volumes.traefik-certs = {
    storage = "plain";
  };

  # ── Sops secrets (needed for placeholder access in templates) ─────────
  sops.secrets.base_domain = { };
  sops.secrets.acme_email = { };

  # ── Sops templates ────────────────────────────────────────────────────

  # ACME email via env var (Traefik reads TRAEFIK_* env vars for static config)
  sops.templates."traefik.env" = {
    content = ''
      TRAEFIK_CERTIFICATESRESOLVERS_LERESOLVER_ACME_EMAIL=${config.sops.placeholder.acme_email}
    '';
  };

  # Dynamic config: non-secret middleware/TLS (no placeholders, but co-located
  # with routing files so Traefik reads one directory)
  sops.templates."traefik-headers.yaml".content =
    builtins.readFile ../../files/traefik-dynamic/headers.yaml;
  sops.templates."traefik-tls.yaml".content = builtins.readFile ../../files/traefik-dynamic/tls.yaml;
  sops.templates."traefik-authelia-mw.yaml".content =
    builtins.readFile ../../files/traefik-dynamic/authelia.yaml;

  # Dynamic config: traefik dashboard routing (domain from sops)
  sops.templates."traefik-routing.yaml".content = ''
    http:
      routers:
        traefik:
          rule: "Host(`traefik.${config.sops.placeholder.base_domain}`)"
          entryPoints:
            - websecure
          tls:
            certResolver: leresolver
          middlewares:
            - authelia
            - secure-headers
          service: api@internal
  '';

  # ── Container ─────────────────────────────────────────────────────────

  virtualisation.oci-containers.containers.traefik = {
    image = images.traefik;

    update = {
      primary = true;
      repo = "traefik/traefik";
    };

    environmentFiles = [
      config.sops.templates."traefik.env".path
    ];

    cmd = [
      "--api=true"
      "--global.sendAnonymousUsage=false"
      "--global.checkNewVersion=false"
      "--log=true"
      "--log.level=INFO"
      "--certificatesresolvers.leresolver.acme.storage=/certs/acme.json"
      "--certificatesresolvers.leresolver.acme.httpchallenge.entrypoint=web"
      "--certificatesresolvers.leresolver.acme.tlschallenge=false"
      "--certificatesresolvers.leresolver.acme.httpchallenge=true"
      "--accesslog=true"
      "--entryPoints.web=true"
      "--entryPoints.web.address=:80"
      "--entryPoints.web.http.redirections.entryPoint.to=websecure"
      "--entryPoints.web.http.redirections.entryPoint.scheme=https"
      "--entryPoints.websecure=true"
      "--entryPoints.websecure.address=:443"
      "--providers.file.directory=/etc/traefik/dynamic"
      "--ocsp=true"
    ];

    ports = [
      "80:80"
      "443:443"
    ];

    volumes = [
      "traefik-certs:/certs"
      "${config.sops.templates."traefik-headers.yaml".path}:/etc/traefik/dynamic/headers.yaml:ro"
      "${config.sops.templates."traefik-tls.yaml".path}:/etc/traefik/dynamic/tls.yaml:ro"
      "${config.sops.templates."traefik-authelia-mw.yaml".path}:/etc/traefik/dynamic/authelia-mw.yaml:ro"
      "${config.sops.templates."traefik-routing.yaml".path}:/etc/traefik/dynamic/traefik.yaml:ro"
    ];

    log-driver = "journald";

    extraOptions = [
      "--network=podman"
      "--stop-timeout=30"
      "--cap-drop=ALL"
      "--cap-add=NET_BIND_SERVICE"
      "--security-opt=no-new-privileges:true"
      "--read-only"
    ];
  };

  # ── Systemd ordering ─────────────────────────────────────────────────

  systemd.services.podman-traefik = {
    after = [
      "podman-volume-traefik-certs.service"
    ];
    requires = [
      "podman-volume-traefik-certs.service"
    ];
    restartTriggers = [
      config.sops.templates."traefik.env".content
    ];
  };

  # Podman doesn't bypass iptables like Docker — open HTTP/HTTPS ports
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  # ── Homepage entry ──────────────────────────────────────────────────

  services.homepage.entries = [
    {
      group = "Network";
      name = "Traefik";
      icon = "traefik.svg";
      href = "https://traefik.${config.sops.placeholder.base_domain}";
      container = "traefik";
    }
  ];
}
