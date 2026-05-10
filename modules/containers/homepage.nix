{
  config,
  lib,
  pkgs,
  ...
}:

let
  images = import ../images.nix;

  cfg = config.services.homepage;

  # ── Services YAML generator ──────────────────────────────────────────
  # Builds Homepage's services.yaml from entry options.
  # JSON is valid YAML — Homepage's js-yaml parser accepts it.

  # instance: "private" includes docker container status; "public" strips it (links only).
  mkServicesYaml =
    instance: entries:
    let
      grouped = builtins.groupBy (e: e.group) entries;
      mkEntry = e: {
        ${e.name} = {
          inherit (e) icon href;
        }
        // lib.optionalAttrs (instance == "private" && e.container != "") {
          server = "docker";
          inherit (e) container;
        }
        // lib.optionalAttrs (e.description != "") { inherit (e) description; }
        // lib.optionalAttrs (instance == "private" && e.privateWidget != { }) {
          widget = e.privateWidget;
        };
      };
    in
    builtins.toJSON (lib.mapAttrsToList (name: es: { ${name} = map mkEntry es; }) grouped);

  # ── Config files ────────────────────────────────────────────────────

  dockerYaml = pkgs.writeText "docker.yaml" ''
    docker:
      host: dockerproxy
      port: 2375
  '';

  settingsPrivate = pkgs.writeText "settings-private.yaml" ''
    instanceName: private
    # providers:
    #   openweathermap: <from sops>
    #   weatherapi: <from sops>
  '';

  settingsPublic = pkgs.writeText "settings-public.yaml" ''
    instanceName: public
    # providers:
    #   openweathermap: <from sops>
    #   weatherapi: <from sops>
  '';

  bookmarksYaml = pkgs.writeText "bookmarks.yaml" "---\n";

  widgetsPrivate = pkgs.writeText "widgets-private.yaml" ''
    - resources:
        cpu: true
        memory: true
        disk: /
  '';

  widgetsPublic = pkgs.writeText "widgets-public.yaml" "---\n";
in
{
  # ── Option: homepage entries ──────────────────────────────────────────
  # Each container module adds its entry here.

  options.services.homepage.entries = lib.mkOption {
    type = lib.types.listOf (
      lib.types.submodule {
        options = {
          group = lib.mkOption { type = lib.types.str; };
          name = lib.mkOption { type = lib.types.str; };
          icon = lib.mkOption {
            type = lib.types.str;
            default = "";
          };
          href = lib.mkOption {
            type = lib.types.str;
            description = "URL — use config.sops.placeholder.base_domain for the domain";
          };
          description = lib.mkOption {
            type = lib.types.str;
            default = "";
          };
          container = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Podman container name for status monitoring";
          };
          public = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Also show on the public homepage";
          };
          private = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Show on the private homepage (set false for self-referencing entries)";
          };
          privateWidget = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = ''
              Homepage service widget config — emitted on the private instance only.
              Reference secrets via Homepage env-var interpolation, e.g. "{{HOMEPAGE_VAR_FOO}}".
            '';
          };
        };
      }
    );
    default = [ ];
  };

  # ── Config ────────────────────────────────────────────────────────────

  config = {
    # ── Volumes ─────────────────────────────────────────────────────────

    podman.volumes.homepage-config-public = {
      storage = "plain";
    };
    podman.volumes.homepage-config-private = {
      storage = "plain";
    };

    sops.secrets.base_domain = { };

    # Widget API keys — interpolated into services.yaml as {{HOMEPAGE_VAR_*}}
    sops.secrets.homepage_widget_immich_key = { };
    sops.secrets.homepage_widget_paperless_key = { };
    sops.secrets.homepage_widget_karakeep_key = { };

    sops.templates."homepage-private-widgets.env".content = ''
      HOMEPAGE_VAR_WIDGET_IMMICH_KEY=${config.sops.placeholder.homepage_widget_immich_key}
      HOMEPAGE_VAR_WIDGET_PAPERLESS_KEY=${config.sops.placeholder.homepage_widget_paperless_key}
      HOMEPAGE_VAR_WIDGET_KARAKEEP_KEY=${config.sops.placeholder.homepage_widget_karakeep_key}
    '';

    # ── Services YAML (assembled from all module entries via sops) ─────

    sops.templates."homepage-services-private.yaml".content = mkServicesYaml "private" (
      builtins.filter (e: e.private) cfg.entries
    );

    sops.templates."homepage-services-public.yaml".content = mkServicesYaml "public" (
      builtins.filter (e: e.public) cfg.entries
    );

    # ── Traefik routing ─────────────────────────────────────────────────

    sops.templates."homepage-public-routing.yaml".content = ''
      http:
        routers:
          homepage-public:
            rule: "Host(`${config.sops.placeholder.base_domain}`)"
            entryPoints:
              - websecure
            tls:
              certResolver: leresolver
            middlewares:
              - secure-headers
            service: homepage-public
        services:
          homepage-public:
            loadBalancer:
              servers:
                - url: "http://homepage-public:3000"
    '';

    sops.templates."homepage-private-routing.yaml".content = ''
      http:
        routers:
          homepage-private:
            rule: "Host(`homepage-private.${config.sops.placeholder.base_domain}`)"
            entryPoints:
              - websecure
            tls:
              certResolver: leresolver
            middlewares:
              - authelia
              - secure-headers
            service: homepage-private
        services:
          homepage-private:
            loadBalancer:
              servers:
                - url: "http://homepage-private:3000"
    '';

    sops.templates."homepage-public.env".content = ''
      HOMEPAGE_ALLOWED_HOSTS=${config.sops.placeholder.base_domain}
    '';

    sops.templates."homepage-private.env".content = ''
      HOMEPAGE_ALLOWED_HOSTS=homepage-private.${config.sops.placeholder.base_domain}
    '';

    # Mount routing configs into Traefik
    virtualisation.oci-containers.containers.traefik.volumes = [
      "${
        config.sops.templates."homepage-public-routing.yaml".path
      }:/etc/traefik/dynamic/homepage-public.yaml:ro"
      "${
        config.sops.templates."homepage-private-routing.yaml".path
      }:/etc/traefik/dynamic/homepage-private.yaml:ro"
    ];

    # ── Public Homepage ─────────────────────────────────────────────────

    virtualisation.oci-containers.containers.homepage-public = {
      image = images.homepage;

      update = {
        primary = true;
        repo = "gethomepage/homepage";
      };

      volumes = [
        "homepage-config-public:/app/config"
        "${settingsPublic}:/app/config/settings.yaml:ro"
        "${config.sops.templates."homepage-services-public.yaml".path}:/app/config/services.yaml:ro"
        "${bookmarksYaml}:/app/config/bookmarks.yaml:ro"
        "${widgetsPublic}:/app/config/widgets.yaml:ro"
      ];

      environmentFiles = [
        config.sops.templates."homepage-public.env".path
      ];

      environment = {
        TZ = "Europe/Rome";
      };

      log-driver = "journald";

      extraOptions = [
        "--network=homepage-net"
        "--network=proxy"
        "--stop-timeout=30"
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges:true"
        "--tmpfs=/tmp"
      ];
    };

    # ── Private Homepage ────────────────────────────────────────────────

    virtualisation.oci-containers.containers.homepage-private = {
      image = images.homepage;

      volumes = [
        "homepage-config-private:/app/config"
        "${dockerYaml}:/app/config/docker.yaml:ro"
        "${settingsPrivate}:/app/config/settings.yaml:ro"
        "${config.sops.templates."homepage-services-private.yaml".path}:/app/config/services.yaml:ro"
        "${bookmarksYaml}:/app/config/bookmarks.yaml:ro"
        "${widgetsPrivate}:/app/config/widgets.yaml:ro"
      ];

      environmentFiles = [
        config.sops.templates."homepage-private.env".path
        config.sops.templates."homepage-private-widgets.env".path
      ];

      environment = {
        TZ = "Europe/Rome";
      };

      log-driver = "journald";

      extraOptions = [
        "--network=homepage-net"
        "--network=proxy"
        "--stop-timeout=30"
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges:true"
        "--tmpfs=/tmp"
      ];
    };

    # ── Systemd ordering ───────────────────────────────────────────────

    systemd.services.podman-homepage-public = {
      after = [
        "podman-network-homepage-net.service"
        "podman-network-proxy.service"
        "podman-volume-homepage-config-public.service"
      ];
      requires = [
        "podman-network-homepage-net.service"
        "podman-network-proxy.service"
        "podman-volume-homepage-config-public.service"
      ];
      restartTriggers = [
        config.sops.templates."homepage-services-public.yaml".content
        config.sops.templates."homepage-public.env".content
      ];
    };

    systemd.services.podman-homepage-private = {
      after = [
        "podman-network-homepage-net.service"
        "podman-network-proxy.service"
        "podman-volume-homepage-config-private.service"
        "podman-dockerproxy.service"
      ];
      requires = [
        "podman-network-homepage-net.service"
        "podman-network-proxy.service"
        "podman-volume-homepage-config-private.service"
        "podman-dockerproxy.service"
      ];
      restartTriggers = [
        config.sops.templates."homepage-services-private.yaml".content
        config.sops.templates."homepage-private.env".content
        config.sops.templates."homepage-private-widgets.env".content
      ];
    };

    # ── Homepage entry ───────────────────────────────────────────────
    # Show homepage-private on the public dashboard (not on private — that's self-referencing)
    services.homepage.entries = [
      {
        group = "Network";
        name = "Homepage (internal)";
        icon = "homepage.svg";
        href = "https://homepage-private.${config.sops.placeholder.base_domain}";
        container = "homepage-private";
        public = true;
        private = false;
      }
    ];
  };
}
