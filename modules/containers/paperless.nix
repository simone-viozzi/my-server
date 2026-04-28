{ config, ... }:

let
  images = import ../images.nix;
in
{
  # ── Volumes ───────────────────────────────────────────────────────────

  podman.volumes.paperless-pgdata = {
    storage = "btrfs-nvme";
  };
  podman.volumes.paperless-data = {
    storage = "btrfs-hdd";
  };
  podman.volumes.paperless-media = {
    storage = "btrfs-hdd";
  };
  podman.volumes.paperless-redisdata = {
    storage = "plain";
  };

  # ── Sops secrets ──────────────────────────────────────────────────────

  sops.secrets.base_domain = { };
  sops.secrets.paperless_secret_key = { };
  sops.secrets.paperless_postgres_password = { };

  # ── Sops templates ────────────────────────────────────────────────────

  sops.templates."paperless-db.env".content = ''
    POSTGRES_DB=paperless
    POSTGRES_USER=paperless
    POSTGRES_PASSWORD=${config.sops.placeholder.paperless_postgres_password}
  '';

  sops.templates."paperless-app.env".content = ''
    PAPERLESS_SECRET_KEY=${config.sops.placeholder.paperless_secret_key}
    PAPERLESS_DBHOST=paperless-postgres
    PAPERLESS_DBPASS=${config.sops.placeholder.paperless_postgres_password}
    PAPERLESS_DBUSER=paperless
    PAPERLESS_DBNAME=paperless
    PAPERLESS_REDIS=redis://paperless-redis:6379
    PAPERLESS_TIKA_ENABLED=1
    PAPERLESS_TIKA_GOTENBERG_ENDPOINT=http://paperless-gotenberg:3000
    PAPERLESS_TIKA_ENDPOINT=http://paperless-tika:9998
    PAPERLESS_URL=https://paperless.${config.sops.placeholder.base_domain}
    PAPERLESS_ENABLE_HTTP_REMOTE_USER=true
    PAPERLESS_HTTP_REMOTE_USER_HEADER_NAME=HTTP_REMOTE_USER
    PAPERLESS_LOGOUT_REDIRECT_URL=https://auth.${config.sops.placeholder.base_domain}/logout
    PAPERLESS_OCR_LANGUAGE=eng+ita
    PAPERLESS_OCR_PAGES=10
    PAPERLESS_TASK_WORKERS=2
    PAPERLESS_THREADS_PER_WORKER=2
    PAPERLESS_TIME_ZONE=Europe/Rome
  '';

  # ── Traefik routing ───────────────────────────────────────────────────

  sops.templates."paperless-routing.yaml".content = ''
    http:
      routers:
        paperless:
          rule: "Host(`paperless.${config.sops.placeholder.base_domain}`)"
          entryPoints:
            - websecure
          tls:
            certResolver: leresolver
          middlewares:
            - authelia
            - secure-headers
          service: paperless
      services:
        paperless:
          loadBalancer:
            servers:
              - url: "http://paperless:8000"
  '';

  virtualisation.oci-containers.containers.traefik.volumes = [
    "${config.sops.templates."paperless-routing.yaml".path}:/etc/traefik/dynamic/paperless.yaml:ro"
  ];

  # ── Containers ────────────────────────────────────────────────────────

  virtualisation.oci-containers.containers.paperless = {
    image = images.paperless;

    update = {
      primary = true;
      repo = "paperless-ngx/paperless-ngx";
    };

    user = "1000:1000";

    volumes = [
      "paperless-data:/usr/src/paperless/data"
      "paperless-media:/usr/src/paperless/media"
    ];

    environmentFiles = [
      config.sops.templates."paperless-app.env".path
    ];

    log-driver = "journald";

    extraOptions = [
      "--network=podman"
      "--network=isolated"
      "--stop-timeout=30"
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges:true"
      # s6-overlay needs /run owned by the container user
      "--mount=type=tmpfs,destination=/run,chown"
    ];
  };

  virtualisation.oci-containers.containers.paperless-postgres = {
    image = images.postgres18;

    volumes = [
      "paperless-pgdata:/var/lib/postgresql"
    ];

    environmentFiles = [
      config.sops.templates."paperless-db.env".path
    ];

    environment = {
      TZ = "Europe/Rome";
    };

    log-driver = "journald";

    extraOptions = [
      "--network=isolated"
      "--stop-timeout=30"
      "--cap-drop=ALL"
      "--cap-add=SETUID"
      "--cap-add=SETGID"
      "--cap-add=CHOWN"
      "--cap-add=FOWNER"
      "--cap-add=DAC_OVERRIDE"
      "--security-opt=no-new-privileges:true"
      "--shm-size=128m"
      "--health-cmd=pg_isready -d paperless -U paperless || exit 1"
      "--health-interval=10s"
      "--health-start-period=30s"
    ];
  };

  virtualisation.oci-containers.containers.paperless-redis = {
    image = images.paperlessRedis;

    volumes = [
      "paperless-redisdata:/data"
    ];

    log-driver = "journald";

    extraOptions = [
      "--network=isolated"
      "--stop-timeout=30"
      "--cap-drop=ALL"
      "--cap-add=SETUID"
      "--cap-add=SETGID"
      "--cap-add=SETPCAP"
      "--security-opt=no-new-privileges:true"
      "--health-cmd=redis-cli ping || exit 1"
      "--health-interval=10s"
      "--health-start-period=10s"
    ];
  };

  virtualisation.oci-containers.containers.paperless-gotenberg = {
    image = images.paperlessGotenberg;

    cmd = [
      "gotenberg"
      "--chromium-disable-javascript=true"
      "--chromium-allow-list=file:///tmp/.*"
    ];

    log-driver = "journald";

    extraOptions = [
      "--network=isolated"
      "--stop-timeout=30"
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges:true"
    ];
  };

  virtualisation.oci-containers.containers.paperless-tika = {
    image = images.tika;

    log-driver = "journald";

    extraOptions = [
      "--network=isolated"
      "--stop-timeout=30"
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges:true"
    ];
  };

  # ── Systemd ordering ─────────────────────────────────────────────────

  systemd.services.podman-paperless = {
    after = [
      "podman-network-isolated.service"
      "podman-volume-paperless-data.service"
      "podman-volume-paperless-media.service"
      "podman-paperless-postgres.service"
      "podman-paperless-redis.service"
      "podman-paperless-gotenberg.service"
      "podman-paperless-tika.service"
    ];
    requires = [
      "podman-network-isolated.service"
      "podman-volume-paperless-data.service"
      "podman-volume-paperless-media.service"
      "podman-paperless-postgres.service"
      "podman-paperless-redis.service"
      "podman-paperless-gotenberg.service"
      "podman-paperless-tika.service"
    ];
    restartTriggers = [
      config.sops.templates."paperless-app.env".content
      config.sops.templates."paperless-routing.yaml".content
    ];
  };

  systemd.services.podman-paperless-postgres = {
    after = [
      "podman-network-isolated.service"
      "podman-volume-paperless-pgdata.service"
    ];
    requires = [
      "podman-network-isolated.service"
      "podman-volume-paperless-pgdata.service"
    ];
    restartTriggers = [
      config.sops.templates."paperless-db.env".content
    ];
  };

  systemd.services.podman-paperless-redis = {
    after = [
      "podman-network-isolated.service"
      "podman-volume-paperless-redisdata.service"
    ];
    requires = [
      "podman-network-isolated.service"
      "podman-volume-paperless-redisdata.service"
    ];
  };

  systemd.services.podman-paperless-gotenberg = {
    after = [
      "podman-network-isolated.service"
    ];
    requires = [
      "podman-network-isolated.service"
    ];
  };

  systemd.services.podman-paperless-tika = {
    after = [
      "podman-network-isolated.service"
    ];
    requires = [
      "podman-network-isolated.service"
    ];
  };

  # ── Backup ────────────────────────────────────────────────────────────

  backup.services.paperless = {
    enable = true;
    schedule = "04:00";
    timeout = "1h";
    volumes = [
      "paperless-pgdata"
      "paperless-data"
      "paperless-media"
    ];
  };

  # ── Homepage entry ──────────────────────────────────────────────────

  services.homepage.entries = [
    {
      group = "Media";
      name = "Paperless-ngx";
      icon = "paperless-ngx.svg";
      href = "https://paperless.${config.sops.placeholder.base_domain}";
      container = "paperless";
      public = true;
      privateWidget = {
        type = "paperlessngx";
        url = "http://paperless:8000";
        key = "{{HOMEPAGE_VAR_WIDGET_PAPERLESS_KEY}}";
      };
    }
  ];
}
