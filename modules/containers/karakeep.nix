{ config, ... }:

let
  images = import ../images.nix;
in
{
  # ── Volumes ───────────────────────────────────────────────────────────

  podman.volumes.karakeep-data = {
    storage = "btrfs-hdd";
  };
  podman.volumes.karakeep-meilisearch = {
    storage = "plain";
  };

  # ── Sops secrets ──────────────────────────────────────────────────────

  sops.secrets.base_domain = { };
  sops.secrets.karakeep_nextauth_secret = { };
  sops.secrets.karakeep_meili_master_key = { };
  sops.secrets.karakeep_oauth_client_id = { };
  sops.secrets.karakeep_oauth_client_secret = { };

  # ── Sops templates ────────────────────────────────────────────────────

  sops.templates."karakeep-web.env".content = ''
    NEXTAUTH_SECRET=${config.sops.placeholder.karakeep_nextauth_secret}
    NEXTAUTH_URL=https://karakeep.${config.sops.placeholder.base_domain}
    MEILI_ADDR=http://karakeep-meilisearch:7700
    MEILI_MASTER_KEY=${config.sops.placeholder.karakeep_meili_master_key}
    BROWSER_WEB_URL=http://karakeep-chrome:9222
    DATA_DIR=/data
    OAUTH_WELLKNOWN_URL=https://auth.${config.sops.placeholder.base_domain}/.well-known/openid-configuration
    OAUTH_CLIENT_ID=${config.sops.placeholder.karakeep_oauth_client_id}
    OAUTH_CLIENT_SECRET=${config.sops.placeholder.karakeep_oauth_client_secret}
    OAUTH_ALLOW_DANGEROUS_EMAIL_ACCOUNT_LINKING=true
    DISABLE_SIGNUPS=true
    DISABLE_PASSWORD_AUTH=true
  '';

  sops.templates."karakeep-meilisearch.env".content = ''
    MEILI_MASTER_KEY=${config.sops.placeholder.karakeep_meili_master_key}
    MEILI_NO_ANALYTICS=true
  '';

  # ── Traefik routing ───────────────────────────────────────────────────

  sops.templates."karakeep-routing.yaml".content = ''
    http:
      routers:
        karakeep:
          rule: "Host(`karakeep.${config.sops.placeholder.base_domain}`)"
          entryPoints:
            - websecure
          tls:
            certResolver: leresolver
          middlewares:
            - secure-headers
          service: karakeep
      services:
        karakeep:
          loadBalancer:
            servers:
              - url: "http://karakeep:3000"
  '';

  virtualisation.oci-containers.containers.traefik.volumes = [
    "${config.sops.templates."karakeep-routing.yaml".path}:/etc/traefik/dynamic/karakeep.yaml:ro"
  ];

  # ── Containers ────────────────────────────────────────────────────────

  virtualisation.oci-containers.containers.karakeep = {
    image = images.karakeep;

    update = {
      primary = true;
      repo = "karakeep-app/karakeep";
    };

    volumes = [
      "karakeep-data:/data"
    ];

    environmentFiles = [
      config.sops.templates."karakeep-web.env".path
    ];

    environment = {
      PUID = "1000";
      PGID = "1000";
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

  virtualisation.oci-containers.containers.karakeep-chrome = {
    image = images.karakeepBrowser;

    cmd = [
      "--no-sandbox"
      "--disable-gpu"
      "--disable-dev-shm-usage"
      "--remote-debugging-address=0.0.0.0"
      "--remote-debugging-port=9222"
      "--hide-scrollbars"
    ];

    log-driver = "journald";

    extraOptions = [
      "--network=podman"
      "--stop-timeout=30"
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges:true"
    ];
  };

  virtualisation.oci-containers.containers.karakeep-meilisearch = {
    image = images.karakeepMeili;

    volumes = [
      "karakeep-meilisearch:/meili_data"
    ];

    environmentFiles = [
      config.sops.templates."karakeep-meilisearch.env".path
    ];

    log-driver = "journald";

    extraOptions = [
      "--network=isolated"
      "--stop-timeout=30"
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges:true"
      "--health-cmd=curl -sf http://localhost:7700/health || exit 1"
      "--health-interval=30s"
      "--health-start-period=15s"
    ];
  };

  # ── Systemd ordering ─────────────────────────────────────────────────

  systemd.services.podman-karakeep = {
    after = [
      "podman-network-isolated.service"
      "podman-volume-karakeep-data.service"
      "podman-karakeep-chrome.service"
      "podman-karakeep-meilisearch.service"
    ];
    requires = [
      "podman-network-isolated.service"
      "podman-volume-karakeep-data.service"
      "podman-karakeep-chrome.service"
      "podman-karakeep-meilisearch.service"
    ];
    restartTriggers = [
      config.sops.templates."karakeep-web.env".content
      config.sops.templates."karakeep-routing.yaml".content
    ];
  };

  systemd.services.podman-karakeep-meilisearch = {
    after = [
      "podman-network-isolated.service"
      "podman-volume-karakeep-meilisearch.service"
    ];
    requires = [
      "podman-network-isolated.service"
      "podman-volume-karakeep-meilisearch.service"
    ];
    restartTriggers = [
      config.sops.templates."karakeep-meilisearch.env".content
    ];
  };

  # ── Backup ────────────────────────────────────────────────────────────

  backup.services.karakeep = {
    enable = true;
    schedule = "04:00";
    timeout = "1h";
    volumes = [ "karakeep-data" ];
  };

  # ── Homepage entry ──────────────────────────────────────────────────

  services.homepage.entries = [
    {
      group = "Other";
      name = "Karakeep";
      icon = "hoarder.png";
      href = "https://karakeep.${config.sops.placeholder.base_domain}";
      container = "karakeep";
      public = true;
      privateWidget = {
        type = "karakeep";
        url = "http://karakeep:3000";
        key = "{{HOMEPAGE_VAR_WIDGET_KARAKEEP_KEY}}";
      };
    }
  ];
}
