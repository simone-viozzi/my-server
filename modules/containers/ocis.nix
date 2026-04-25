{ config, ... }:

# Integration nuances (Android app token_endpoint_auth_method, etc.):
# see docs/nuances.md.

let
  images = import ../images.nix;
in
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
  sops.secrets.ocis_oidc_client_id = { };
  sops.secrets.ocis_admin_user_id = { };
  sops.secrets.collabora_admin_password = { };

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
    MICRO_REGISTRY_ADDRESS=127.0.0.1:9233
    NATS_NATS_HOST=0.0.0.0
    NATS_NATS_PORT=9233
    PROXY_CSP_CONFIG_FILE_LOCATION=/etc/ocis/csp.yaml
    OCIS_PASSWORD_POLICY_BANNED_PASSWORDS_LIST=banned-password-list.txt

    # ── External OIDC (Authelia) ──
    OCIS_EXCLUDE_RUN_SERVICES=idp
    OCIS_OIDC_ISSUER=https://auth.${config.sops.placeholder.base_domain}
    OCIS_OIDC_CLIENT_ID=${config.sops.placeholder.ocis_oidc_client_id}
    PROXY_OIDC_REWRITE_WELLKNOWN=true
    PROXY_OIDC_ACCESS_TOKEN_VERIFY_METHOD=none
    PROXY_OIDC_SKIP_USER_INFO=false
    PROXY_AUTOPROVISION_ACCOUNTS=true
    PROXY_AUTOPROVISION_CLAIM_USERNAME=preferred_username
    PROXY_AUTOPROVISION_CLAIM_EMAIL=email
    PROXY_AUTOPROVISION_CLAIM_DISPLAYNAME=name
    PROXY_AUTOPROVISION_CLAIM_GROUPS=groups
    WEB_OIDC_CLIENT_ID=${config.sops.placeholder.ocis_oidc_client_id}
    WEB_OIDC_SCOPE=openid profile email groups offline_access
    GRAPH_USERNAME_MATCH=none
    GRAPH_LDAP_SERVER_WRITE_ENABLED=true
    OCIS_ADMIN_USER_ID=${config.sops.placeholder.ocis_admin_user_id}

    # ── Collaboration (WOPI) secure-view app ──
    FRONTEND_APP_HANDLER_SECURE_VIEW_APP_ADDR=com.owncloud.api.collaboration.CollaboraOnline
    GRAPH_AVAILABLE_ROLES=b1e2218d-eef8-4d4c-b82d-0f1a1b48f3b5,a8d5fe5e-96e3-418d-825b-534dbdf22b99,fb6c3e19-e378-47e5-b277-9732f9de6e21,58c63c02-1d89-4572-916a-870abc5a1b7d,2d00ce52-1fc2-4dbc-8b95-a73b73395f5a,1c996275-f1c9-4e71-abdf-a42f6495e960,312c0871-5ef7-4b3a-85b6-0e4074c64049,aa97fe03-7980-45ac-9e50-b325749fd7e6

    # ── Full-text search via Apache Tika ──
    SEARCH_EXTRACTOR_TYPE=tika
    SEARCH_EXTRACTOR_TIKA_TIKA_URL=http://ocis-tika:9998
    SEARCH_EXTRACTOR_CS3SOURCE_INSECURE=true
  '';

  sops.templates."ocis-collaboration.env".content = ''
    OCIS_URL=https://ocis.${config.sops.placeholder.base_domain}
    OCIS_LOG_LEVEL=info
    OCIS_LOG_COLOR=false
    OCIS_LOG_PRETTY=false
    MICRO_REGISTRY=nats-js-kv
    MICRO_REGISTRY_ADDRESS=ocis:9233
    COLLABORATION_GRPC_ADDR=0.0.0.0:9301
    COLLABORATION_HTTP_ADDR=0.0.0.0:9300
    COLLABORATION_WOPI_SRC=https://collaboration.${config.sops.placeholder.base_domain}
    COLLABORATION_APP_NAME=CollaboraOnline
    COLLABORATION_APP_PRODUCT=Collabora
    COLLABORATION_APP_ADDR=https://collabora.${config.sops.placeholder.base_domain}
    COLLABORATION_APP_ICON=https://collabora.${config.sops.placeholder.base_domain}/favicon.ico
    COLLABORATION_APP_INSECURE=false
    COLLABORATION_CS3API_DATAGATEWAY_INSECURE=true
  '';

  sops.templates."collabora.env".content = ''
    DONT_GEN_SSL_CERT=YES
    username=admin
    password=${config.sops.placeholder.collabora_admin_password}
    extra_params=--o:ssl.enable=false --o:ssl.termination=true --o:welcome.enable=false --o:net.frame_ancestors=ocis.${config.sops.placeholder.base_domain}
    aliasgroup1=https://collaboration.${config.sops.placeholder.base_domain}:443
  '';

  sops.templates."ocis-csp.yaml".mode = "0444";
  sops.templates."ocis-csp.yaml".content = ''
    directives:
      child-src:
        - "'self'"
      connect-src:
        - "'self'"
        - 'blob:'
        - 'https://auth.${config.sops.placeholder.base_domain}/'
        - 'https://collabora.${config.sops.placeholder.base_domain}/'
        - 'https://collaboration.${config.sops.placeholder.base_domain}/'
      default-src:
        - "'none'"
      font-src:
        - "'self'"
        - 'data:'
      frame-ancestors:
        - "'self'"
      frame-src:
        - "'self'"
        - 'blob:'
        - 'https://auth.${config.sops.placeholder.base_domain}/'
        - 'https://collabora.${config.sops.placeholder.base_domain}/'
      img-src:
        - "'self'"
        - 'data:'
        - 'blob:'
      manifest-src:
        - "'self'"
      media-src:
        - "'self'"
      object-src:
        - "'self'"
        - 'blob:'
      script-src:
        - "'self'"
        - "'unsafe-inline'"
        - "'unsafe-eval'"
      style-src:
        - "'self'"
        - "'unsafe-inline'"
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
        collabora:
          rule: "Host(`collabora.${config.sops.placeholder.base_domain}`)"
          entryPoints:
            - websecure
          tls:
            certResolver: leresolver
          service: collabora
        collaboration:
          rule: "Host(`collaboration.${config.sops.placeholder.base_domain}`)"
          entryPoints:
            - websecure
          tls:
            certResolver: leresolver
          middlewares:
            - secure-headers
          service: collaboration
      services:
        ocis:
          loadBalancer:
            servers:
              - url: "http://ocis:9200"
        collabora:
          loadBalancer:
            servers:
              - url: "http://collabora:9980"
        collaboration:
          loadBalancer:
            servers:
              - url: "http://collaboration:9300"
  '';

  virtualisation.oci-containers.containers.traefik.volumes = [
    "${config.sops.templates."ocis-routing.yaml".path}:/etc/traefik/dynamic/ocis.yaml:ro"
  ];

  systemd.services.podman-traefik.restartTriggers = [
    config.sops.templates."ocis-routing.yaml".content
  ];

  # ── Containers ────────────────────────────────────────────────────────

  virtualisation.oci-containers.containers.ocis = {
    image = images.ocis;

    entrypoint = "/bin/sh";
    cmd = [
      "-c"
      "ocis init || true; exec ocis server"
    ];

    volumes = [
      "ocis-config:/etc/ocis"
      "ocis-data:/var/lib/ocis"
      "${./ocis/app-registry.yaml}:/etc/ocis/app-registry.yaml:ro"
      "${config.sops.templates."ocis-csp.yaml".path}:/etc/ocis/csp.yaml:ro"
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

  virtualisation.oci-containers.containers.collabora = {
    image = images.collabora;

    entrypoint = "/bin/bash";
    cmd = [
      "-c"
      "coolconfig generate-proof-key && /start-collabora-online.sh"
    ];

    environmentFiles = [
      config.sops.templates."collabora.env".path
    ];

    log-driver = "journald";

    extraOptions = [
      "--network=podman"
      "--stop-timeout=30"
      "--cap-add=MKNOD"
      "--security-opt=no-new-privileges:true"
    ];
  };

  virtualisation.oci-containers.containers.ocis-tika = {
    image = images.tika;

    log-driver = "journald";

    extraOptions = [
      "--network=isolated"
      "--stop-timeout=30"
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges:true"
    ];
  };

  virtualisation.oci-containers.containers.collaboration = {
    image = images.ocis;

    cmd = [
      "collaboration"
      "server"
    ];

    volumes = [
      "ocis-config:/etc/ocis"
    ];

    environmentFiles = [
      config.sops.templates."ocis-collaboration.env".path
    ];

    log-driver = "journald";

    extraOptions = [
      "--network=podman"
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
      "podman-ocis-tika.service"
    ];
    requires = [
      "podman-network-isolated.service"
      "podman-volume-ocis-config.service"
      "podman-volume-ocis-data.service"
      "podman-ocis-tika.service"
    ];
    restartTriggers = [
      config.sops.templates."ocis.env".content
      config.sops.templates."ocis-routing.yaml".content
      config.sops.templates."ocis-csp.yaml".content
    ];
  };

  systemd.services.podman-ocis-tika = {
    after = [ "podman-network-isolated.service" ];
    requires = [ "podman-network-isolated.service" ];
  };

  systemd.services.podman-collabora = {
    restartTriggers = [
      config.sops.templates."collabora.env".content
    ];
  };

  systemd.services.podman-collaboration = {
    after = [
      "podman-ocis.service"
      "podman-collabora.service"
      "podman-volume-ocis-config.service"
    ];
    requires = [
      "podman-volume-ocis-config.service"
    ];
    restartTriggers = [
      config.sops.templates."ocis-collaboration.env".content
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
