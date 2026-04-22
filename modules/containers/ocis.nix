{ config, ... }:

{
  # ── Volumes ───────────────────────────────────────────────────────────

  podman.volumes.ocis-config = {
    storage = "btrfs-nvme";
  };
  podman.volumes.ocis-data = {
    storage = "btrfs-hdd";
  };

  # ── Sops secrets ──────────────────────────────────────────────────────

  sops.secrets.base_domain = { };
  sops.secrets.ocis_admin_password = { };

  # ── Sops templates ────────────────────────────────────────────────────

  sops.templates."ocis.env".content = ''
    OCIS_URL=https://ocis.${config.sops.placeholder.base_domain}
    OCIS_LOG_LEVEL=info
    OCIS_LOG_COLOR=false
    OCIS_LOG_PRETTY=false
    PROXY_TLS=false
    OCIS_INSECURE=false
    PROXY_ENABLE_BASIC_AUTH=false
    GATEWAY_GRPC_ADDR=0.0.0.0:9142
    IDM_ADMIN_PASSWORD=${config.sops.placeholder.ocis_admin_password}
    IDM_CREATE_DEMO_USERS=false
    MICRO_REGISTRY_ADDRESS=127.0.0.1:9233
    NATS_NATS_HOST=0.0.0.0
    NATS_NATS_PORT=9233
    PROXY_CSP_CONFIG_FILE_LOCATION=/etc/ocis/csp.yaml
    OCIS_PASSWORD_POLICY_BANNED_PASSWORDS_LIST=banned-password-list.txt
  '';

  # ── Traefik routing ───────────────────────────────────────────────────

  sops.templates."ocis-routing.yaml".content = ''
    http:
      routers:
        ocis:
          rule: "Host(`ocis.${config.sops.placeholder.base_domain}`)"
          entryPoints:
            - websecure
          tls:
            certResolver: leresolver
          middlewares:
            - secure-headers
          service: ocis
      services:
        ocis:
          loadBalancer:
            servers:
              - url: "http://ocis:9200"
  '';

  virtualisation.oci-containers.containers.traefik.volumes = [
    "${config.sops.templates."ocis-routing.yaml".path}:/etc/traefik/dynamic/ocis.yaml:ro"
  ];

  # ── Containers ────────────────────────────────────────────────────────

  virtualisation.oci-containers.containers.ocis = {
    image = "docker.io/owncloud/ocis:8.0.1@sha256:b35c557ff56bbddc1dd74d4142d81a8a2cac9ff7e5e774516281a691e42bb153";

    entrypoint = "/bin/sh";
    cmd = [
      "-c"
      "ocis init || true; exec ocis server"
    ];

    volumes = [
      "ocis-config:/etc/ocis"
      "ocis-data:/var/lib/ocis"
      "${./ocis/app-registry.yaml}:/etc/ocis/app-registry.yaml:ro"
      "${./ocis/csp.yaml}:/etc/ocis/csp.yaml:ro"
      "${./ocis/banned-password-list.txt}:/etc/ocis/banned-password-list.txt:ro"
    ];

    environmentFiles = [
      config.sops.templates."ocis.env".path
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

  # ── Systemd ordering ─────────────────────────────────────────────────

  systemd.services.podman-ocis = {
    after = [
      "podman-network-isolated.service"
      "podman-volume-ocis-config.service"
      "podman-volume-ocis-data.service"
    ];
    requires = [
      "podman-network-isolated.service"
      "podman-volume-ocis-config.service"
      "podman-volume-ocis-data.service"
    ];
    restartTriggers = [
      config.sops.templates."ocis.env".content
      config.sops.templates."ocis-routing.yaml".content
    ];
  };

  # ── Backup ────────────────────────────────────────────────────────────

  backup.services.ocis = {
    enable = true;
    schedule = "02:00";
    timeout = "2h";
    volumes = [
      "ocis-config"
      "ocis-data"
    ];
  };

  # ── Homepage entry ──────────────────────────────────────────────────

  services.homepage.entries = [
    {
      group = "Files";
      name = "ownCloud";
      icon = "owncloud.svg";
      href = "https://ocis.${config.sops.placeholder.base_domain}";
      container = "ocis";
      public = true;
    }
  ];
}
