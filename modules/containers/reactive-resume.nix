{ config, ... }:

{
  # ── Volumes ───────────────────────────────────────────────────────────

  podman.volumes.resume-pgdata = {
    storage = "btrfs-nvme";
  };
  podman.volumes.resume-seaweedfs = {
    storage = "btrfs-hdd";
  };
  podman.volumes.resume-data = {
    storage = "btrfs-hdd";
  };

  # ── Sops secrets ──────────────────────────────────────────────────────

  sops.secrets.base_domain = { };
  sops.secrets.resume_postgres_password = { };
  sops.secrets.resume_auth_secret = { };
  sops.secrets.resume_s3_access_key = { };
  sops.secrets.resume_s3_secret_key = { };
  sops.secrets.resume_browserless_token = { };
  sops.secrets.resume_oauth_client_id = { };
  sops.secrets.resume_oauth_client_secret = { };

  # ── Sops templates ────────────────────────────────────────────────────

  sops.templates."resume-db.env".content = ''
    POSTGRES_DB=postgres
    POSTGRES_USER=postgres
    POSTGRES_PASSWORD=${config.sops.placeholder.resume_postgres_password}
  '';

  sops.templates."resume-app.env".content = ''
    NODE_ENV=production
    APP_URL=https://resume.${config.sops.placeholder.base_domain}
    PRINTER_APP_URL=http://resume:3000
    PRINTER_ENDPOINT=ws://resume-browserless:3000?token=${config.sops.placeholder.resume_browserless_token}
    DATABASE_URL=postgresql://postgres:${config.sops.placeholder.resume_postgres_password}@resume-postgres:5432/postgres
    AUTH_SECRET=${config.sops.placeholder.resume_auth_secret}
    S3_ACCESS_KEY_ID=${config.sops.placeholder.resume_s3_access_key}
    S3_SECRET_ACCESS_KEY=${config.sops.placeholder.resume_s3_secret_key}
    S3_ENDPOINT=http://resume-seaweedfs:8333
    S3_BUCKET=reactive-resume
    S3_FORCE_PATH_STYLE=true
    OAUTH_PROVIDER_NAME=Authelia
    OAUTH_CLIENT_ID=${config.sops.placeholder.resume_oauth_client_id}
    OAUTH_CLIENT_SECRET=${config.sops.placeholder.resume_oauth_client_secret}
    OAUTH_DISCOVERY_URL=https://auth.${config.sops.placeholder.base_domain}/.well-known/openid-configuration
    FLAG_DISABLE_EMAIL_AUTH=true
    FLAG_DISABLE_SIGNUPS=false
  '';

  sops.templates."resume-s3.env".content = ''
    AWS_ACCESS_KEY_ID=${config.sops.placeholder.resume_s3_access_key}
    AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.resume_s3_secret_key}
  '';

  sops.templates."resume-browserless.env".content = ''
    TOKEN=${config.sops.placeholder.resume_browserless_token}
  '';

  # ── Traefik routing ───────────────────────────────────────────────────

  sops.templates."resume-routing.yaml".content = ''
    http:
      routers:
        resume:
          rule: "Host(`resume.${config.sops.placeholder.base_domain}`)"
          entryPoints:
            - websecure
          tls:
            certResolver: leresolver
          middlewares:
            - resume-landing-redirect
            - secure-headers
          service: resume
      middlewares:
        resume-landing-redirect:
          redirectRegex:
            regex: "^https://resume\\.${config.sops.placeholder.base_domain}/?$"
            replacement: "https://resume.${config.sops.placeholder.base_domain}/auth/login"
            permanent: false
      services:
        resume:
          loadBalancer:
            servers:
              - url: "http://resume:3000"
  '';

  virtualisation.oci-containers.containers.traefik.volumes = [
    "${config.sops.templates."resume-routing.yaml".path}:/etc/traefik/dynamic/resume.yaml:ro"
  ];

  # ── Containers ────────────────────────────────────────────────────────

  virtualisation.oci-containers.containers.resume = {
    image = "docker.io/amruthpillai/reactive-resume:latest@sha256:adaa9e95ea80c91d2a1ddc6cf1d5924268f6f5d610910eae29126b152395aab4";

    volumes = [
      "resume-data:/app/data"
    ];

    environmentFiles = [
      config.sops.templates."resume-app.env".path
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

  virtualisation.oci-containers.containers.resume-postgres = {
    image = "docker.io/postgres:18@sha256:52e6ffd11fddd081ae63880b635b2a61c14008c17fc98cdc7ce5472265516dd0";

    volumes = [
      "resume-pgdata:/var/lib/postgresql"
    ];

    environmentFiles = [
      config.sops.templates."resume-db.env".path
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
      "--health-cmd=pg_isready -d postgres -U postgres || exit 1"
      "--health-interval=10s"
      "--health-start-period=30s"
    ];
  };

  virtualisation.oci-containers.containers.resume-browserless = {
    image = "ghcr.io/browserless/chromium:latest@sha256:35deff208e30b3d8681f21f43f337e475e5bee21ad8b22d41359028e677210b6";

    environmentFiles = [
      config.sops.templates."resume-browserless.env".path
    ];

    environment = {
      CONCURRENT = "5";
      HEALTH = "true";
      QUEUED = "10";
    };

    log-driver = "journald";

    extraOptions = [
      "--network=isolated"
      "--stop-timeout=30"
      "--cap-drop=ALL"
      "--cap-add=SYS_ADMIN"
      "--security-opt=no-new-privileges:true"
    ];
  };

  virtualisation.oci-containers.containers.resume-seaweedfs = {
    image = "docker.io/chrislusf/seaweedfs:latest@sha256:854479eebcbc0060d803edb27b3bd88a0552e23fde08a26a6482e59aff887a77";

    cmd = [
      "server"
      "-s3"
      "-filer"
      "-dir=/data"
      "-ip=0.0.0.0"
    ];

    volumes = [
      "resume-seaweedfs:/data"
    ];

    environmentFiles = [
      config.sops.templates."resume-s3.env".path
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
      "--security-opt=no-new-privileges:true"
      "--health-cmd=wget -q -O /dev/null http://localhost:8888 || exit 1"
      "--health-interval=30s"
      "--health-start-period=10s"
    ];
  };

  virtualisation.oci-containers.containers.resume-seaweedfs-init = {
    image = "quay.io/minio/mc:latest@sha256:a7fe349ef4bd8521fb8497f55c6042871b2ae640607cf99d9bede5e9bdf11727";

    entrypoint = "/bin/sh";
    cmd = [
      "-c"
      "sleep 5; mc alias set seaweedfs http://resume-seaweedfs:8333 $AWS_ACCESS_KEY_ID $AWS_SECRET_ACCESS_KEY; mc mb --ignore-existing seaweedfs/reactive-resume; exit 0"
    ];

    environmentFiles = [
      config.sops.templates."resume-s3.env".path
    ];

    log-driver = "journald";

    extraOptions = [
      "--network=isolated"
      "--stop-timeout=30"
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges:true"
    ];
  };

  # ── Systemd ordering ─────────────────────────────────────────────────

  systemd.services.podman-resume = {
    after = [
      "podman-network-isolated.service"
      "podman-volume-resume-data.service"
      "podman-resume-postgres.service"
      "podman-resume-browserless.service"
      "podman-resume-seaweedfs-init.service"
    ];
    requires = [
      "podman-network-isolated.service"
      "podman-volume-resume-data.service"
      "podman-resume-postgres.service"
      "podman-resume-browserless.service"
      "podman-resume-seaweedfs-init.service"
    ];
    restartTriggers = [
      config.sops.templates."resume-app.env".content
      config.sops.templates."resume-routing.yaml".content
    ];
  };

  systemd.services.podman-resume-postgres = {
    after = [
      "podman-network-isolated.service"
      "podman-volume-resume-pgdata.service"
    ];
    requires = [
      "podman-network-isolated.service"
      "podman-volume-resume-pgdata.service"
    ];
    restartTriggers = [
      config.sops.templates."resume-db.env".content
    ];
  };

  systemd.services.podman-resume-browserless = {
    after = [
      "podman-network-isolated.service"
    ];
    requires = [
      "podman-network-isolated.service"
    ];
    restartTriggers = [
      config.sops.templates."resume-browserless.env".content
    ];
  };

  systemd.services.podman-resume-seaweedfs = {
    after = [
      "podman-network-isolated.service"
      "podman-volume-resume-seaweedfs.service"
    ];
    requires = [
      "podman-network-isolated.service"
      "podman-volume-resume-seaweedfs.service"
    ];
    restartTriggers = [
      config.sops.templates."resume-s3.env".content
    ];
  };

  systemd.services.podman-resume-seaweedfs-init = {
    after = [
      "podman-network-isolated.service"
      "podman-resume-seaweedfs.service"
    ];
    requires = [
      "podman-network-isolated.service"
      "podman-resume-seaweedfs.service"
    ];
    # Run once and don't restart — it's a one-shot init container
    serviceConfig.Restart = "on-failure";
    serviceConfig.RestartSec = "10s";
  };

  # ── Backup ────────────────────────────────────────────────────────────

  backup.services.resume = {
    enable = true;
    schedule = "03:30";
    timeout = "1h";
    volumes = [
      "resume-pgdata"
      "resume-seaweedfs"
      "resume-data"
    ];
  };

  # ── Homepage entry ──────────────────────────────────────────────────

  services.homepage.entries = [
    {
      group = "Other";
      name = "Reactive Resume";
      icon = "reactive-resume.svg";
      href = "https://resume.${config.sops.placeholder.base_domain}";
      container = "resume";
      public = true;
    }
  ];
}
