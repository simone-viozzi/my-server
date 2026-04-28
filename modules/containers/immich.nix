{ config, ... }:

let
  images = import ../images.nix;
in
{
  # ── Volumes ───────────────────────────────────────────────────────────

  podman.volumes.immich-upload = {
    storage = "btrfs-hdd";
  };
  podman.volumes.immich-pgdata = {
    storage = "btrfs-nvme";
  };
  podman.volumes.immich-model-cache = {
    storage = "plain";
  };

  # ── Sops secrets ──────────────────────────────────────────────────────

  sops.secrets.base_domain = { };
  sops.secrets.immich_db_password = { };
  sops.secrets.immich_db_username = { };
  sops.secrets.immich_db_database_name = { };

  # ── Sops templates ────────────────────────────────────────────────────

  sops.templates."immich.env".content = ''
    DB_PASSWORD=${config.sops.placeholder.immich_db_password}
    DB_USERNAME=${config.sops.placeholder.immich_db_username}
    DB_DATABASE_NAME=${config.sops.placeholder.immich_db_database_name}
    DB_HOSTNAME=immich-postgres
    REDIS_HOSTNAME=immich-redis
    IMMICH_MACHINE_LEARNING_URL=http://immich-machine-learning:3003
  '';

  sops.templates."immich-db.env".content = ''
    POSTGRES_PASSWORD=${config.sops.placeholder.immich_db_password}
    POSTGRES_USER=${config.sops.placeholder.immich_db_username}
    POSTGRES_DB=${config.sops.placeholder.immich_db_database_name}
    POSTGRES_INITDB_ARGS=--data-checksums
  '';

  # ── Traefik routing ───────────────────────────────────────────────────

  sops.templates."immich-routing.yaml".content = ''
    http:
      routers:
        immich:
          rule: "Host(`immich.${config.sops.placeholder.base_domain}`)"
          entryPoints:
            - websecure
          tls:
            certResolver: leresolver
          middlewares:
            - secure-headers
          service: immich
      services:
        immich:
          loadBalancer:
            servers:
              - url: "http://immich-server:2283"
  '';

  virtualisation.oci-containers.containers.traefik.volumes = [
    "${config.sops.templates."immich-routing.yaml".path}:/etc/traefik/dynamic/immich.yaml:ro"
  ];

  # ── Containers ────────────────────────────────────────────────────────

  virtualisation.oci-containers.containers.immich-server = {
    image = images.immichServer;

    update = {
      primary = true;
      repo = "immich-app/immich";
    };

    volumes = [
      "immich-upload:/usr/src/app/upload"
      "/etc/localtime:/etc/localtime:ro"
    ];

    environmentFiles = [
      config.sops.templates."immich.env".path
    ];

    environment = {
      TZ = "Europe/Rome";
    };

    log-driver = "journald";

    extraOptions = [
      "--network=podman"
      "--network=isolated"
      "--stop-timeout=30"
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges:true"
    ];
  };

  virtualisation.oci-containers.containers.immich-machine-learning = {
    image = images.immichMl;

    volumes = [
      "immich-model-cache:/cache"
    ];

    environmentFiles = [
      config.sops.templates."immich.env".path
    ];

    log-driver = "journald";

    extraOptions = [
      "--network=podman"
      "--network=isolated"
      "--stop-timeout=30"
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges:true"
    ];
  };

  virtualisation.oci-containers.containers.immich-redis = {
    image = images.immichValkey;

    log-driver = "journald";

    extraOptions = [
      "--network=isolated"
      "--stop-timeout=30"
      "--cap-drop=ALL"
      "--cap-add=SETUID"
      "--cap-add=SETGID"
      "--security-opt=no-new-privileges:true"
      "--health-cmd=valkey-cli ping || exit 1"
      "--health-interval=10s"
      "--health-start-period=10s"
    ];
  };

  virtualisation.oci-containers.containers.immich-postgres = {
    image = images.immichPostgres;

    volumes = [
      "immich-pgdata:/var/lib/postgresql/data"
    ];

    environmentFiles = [
      config.sops.templates."immich-db.env".path
    ];

    environment = {
      DB_STORAGE_TYPE = "HDD";
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
      "--health-cmd=pg_isready -d \${POSTGRES_DB} -U \${POSTGRES_USER} || exit 1"
      "--health-interval=10s"
      "--health-start-period=30s"
    ];
  };

  # ── Systemd ordering ─────────────────────────────────────────────────

  systemd.services.podman-immich-server = {
    after = [
      "podman-network-isolated.service"
      "podman-volume-immich-upload.service"
      "podman-immich-postgres.service"
      "podman-immich-redis.service"
    ];
    requires = [
      "podman-network-isolated.service"
      "podman-volume-immich-upload.service"
      "podman-immich-postgres.service"
      "podman-immich-redis.service"
    ];
    restartTriggers = [
      config.sops.templates."immich.env".content
    ];
  };

  systemd.services.podman-immich-machine-learning = {
    after = [
      "podman-network-isolated.service"
      "podman-volume-immich-model-cache.service"
    ];
    requires = [
      "podman-network-isolated.service"
      "podman-volume-immich-model-cache.service"
    ];
    restartTriggers = [
      config.sops.templates."immich.env".content
    ];
  };

  systemd.services.podman-immich-redis = {
    after = [
      "podman-network-isolated.service"
    ];
    requires = [
      "podman-network-isolated.service"
    ];
  };

  systemd.services.podman-immich-postgres = {
    after = [
      "podman-network-isolated.service"
      "podman-volume-immich-pgdata.service"
    ];
    requires = [
      "podman-network-isolated.service"
      "podman-volume-immich-pgdata.service"
    ];
    restartTriggers = [
      config.sops.templates."immich-db.env".content
    ];
  };

  # ── Backup ────────────────────────────────────────────────────────────

  backup.services.immich = {
    enable = true;
    schedule = "02:00";
    timeout = "6h";
    volumes = [
      "immich-upload"
      "immich-pgdata"
    ];
  };

  # ── Homepage entry ──────────────────────────────────────────────────

  services.homepage.entries = [
    {
      group = "Media";
      name = "Immich";
      icon = "immich.svg";
      href = "https://immich.${config.sops.placeholder.base_domain}";
      container = "immich-server";
      public = true;
      privateWidget = {
        type = "immich";
        url = "http://immich-server:2283";
        key = "{{HOMEPAGE_VAR_WIDGET_IMMICH_KEY}}";
        version = "2";
      };
    }
  ];
}
