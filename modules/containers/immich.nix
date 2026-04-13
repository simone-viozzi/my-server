{ config, ... }:

let
  immichVersion = "v2.6.3";
in
{
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
    image = "ghcr.io/immich-app/immich-server:${immichVersion}@sha256:0cc1f82953d9598eb9e9dd11cbde1f50fe54f9c46c4506b089e8ad7bfc9d1f0c";

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
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges:true"
    ];
  };

  virtualisation.oci-containers.containers.immich-machine-learning = {
    image = "ghcr.io/immich-app/immich-machine-learning:${immichVersion}@sha256:33b17015c3d14f2565e9b8cd36b48a70027b14b5cd20da7fbfff21a370b0309c";

    volumes = [
      "immich-model-cache:/cache"
    ];

    environmentFiles = [
      config.sops.templates."immich.env".path
    ];

    log-driver = "journald";

    extraOptions = [
      "--network=isolated"
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges:true"
    ];
  };

  virtualisation.oci-containers.containers.immich-redis = {
    image = "docker.io/valkey/valkey:9@sha256:3b55fbaa0cd93cf0d9d961f405e4dfcc70efe325e2d84da207a0a8e6d8fde4f9";

    log-driver = "journald";

    extraOptions = [
      "--network=isolated"
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
    image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23";

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
      "--cap-drop=ALL"
      "--cap-add=SETUID"
      "--cap-add=SETGID"
      "--cap-add=CHOWN"
      "--cap-add=FOWNER"
      "--cap-add=DAC_OVERRIDE"
      "--security-opt=no-new-privileges:true"
      "--shm-size=128m"
      "--health-cmd=pg_isready -d $${POSTGRES_DB} -U $${POSTGRES_USER} || exit 1"
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
  };

  # ── Homepage entry ──────────────────────────────────────────────────

  services.homepage.entries = [
    {
      group = "Media";
      name = "Immich";
      icon = "immich.svg";
      href = "https://immich.${config.sops.placeholder.base_domain}";
      container = "immich-server";
    }
  ];
}
