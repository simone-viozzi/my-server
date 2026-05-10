{
  config,
  pkgs,
  lib,
  ...
}:

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

  # Network aliases on `proxy` so backends that talk to siblings via public
  # hostnames resolve them to Traefik (no WAN hairpin). Consumed via systemd
  # EnvironmentFile + bash ''${VAR}'' substitution in the custom ExecStart below.
  sops.templates."traefik-aliases.env".content =
    let
      d = config.sops.placeholder.base_domain;
      hosts = [
        d
        "apprise.${d}"
        "auth.${d}"
        "collabora.${d}"
        "collaboration.${d}"
        "homepage-private.${d}"
        "immich.${d}"
        "karakeep.${d}"
        "ocis.${d}"
        "paperless.${d}"
        "pdf.${d}"
        "resume.${d}"
        "silverbullet.${d}"
        "traefik.${d}"
      ];
      aliases = builtins.concatStringsSep "," (map (h: "alias=${h}") hosts);
    in
    "TRAEFIK_PROXY_ALIASES=${aliases}\n";

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
      # Network is set by the custom ExecStart override below (sops-substituted aliases).
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
      "podman-network-proxy.service"
    ];
    requires = [
      "podman-volume-traefik-certs.service"
      "podman-network-proxy.service"
    ];
    serviceConfig = {
      EnvironmentFile = config.sops.templates."traefik-aliases.env".path;
      # TODO: this ExecStart override bypasses the auto-generated oci-containers
      # wrapper so we can use bash ''${VAR}'' substitution for the proxy alias
      # list. The auto-generated wrapper escapeShellArg's every option, which is
      # a defense-in-depth against shell injection from extraOptions but also
      # blocks env-var substitution. We accept that trade-off because:
      #   1. The only substituted value (TRAEFIK_PROXY_ALIASES) comes from
      #      a sops-rendered file at /run/secrets/rendered/, root-owned 0400.
      #      Writing to it requires root, at which point the system is already
      #      compromised.
      #   2. Podman/netavark CLI flags don't accept env vars or files for
      #      --network=name:alias=..., so this is the only path to keep the
      #      base_domain out of /nix/store.
      # If a future change in oci-containers (or a switch to quadlet-nix) lets
      # us inject sops values into the network arg without overriding ExecStart,
      # revert this and delete the script. See memory:
      # project_todo_traefik_exec_override.
      ExecStart = lib.mkForce (
        let
          t = config.virtualisation.oci-containers.containers.traefik;
          mkArgs = lib.concatMapStringsSep " " lib.escapeShellArg;
          envFileFlags = mkArgs (
            lib.concatMap (f: [
              "--env-file"
              f
            ]) t.environmentFiles
          );
          portFlags = mkArgs (
            lib.concatMap (p: [
              "-p"
              p
            ]) t.ports
          );
          volFlags = mkArgs (
            lib.concatMap (v: [
              "-v"
              v
            ]) t.volumes
          );
          extraOpts = mkArgs t.extraOptions;
          cmdArgs = mkArgs t.cmd;
        in
        toString (
          pkgs.writeShellScript "podman-traefik-start" ''
            set -e
            # shellcheck source=/dev/null
            source /run/secrets/rendered/traefik-aliases.env
            exec ${pkgs.podman}/bin/podman run \
              --name=traefik \
              --log-driver=${t.log-driver} \
              --cidfile=/run/traefik/ctr-id \
              --cgroups=enabled \
              --sdnotify=conmon \
              -d --replace \
              ${envFileFlags} \
              ${portFlags} \
              ${volFlags} \
              --rm --pull missing \
              "--network=proxy:''${TRAEFIK_PROXY_ALIASES}" \
              ${extraOpts} \
              ${t.image} \
              ${cmdArgs}
          ''
        )
      );
    };
    restartTriggers = [
      config.sops.templates."traefik.env".content
      config.sops.templates."traefik-aliases.env".content
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
