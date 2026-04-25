_:

let
  images = import ../images.nix;
in
{
  # ── Container ─────────────────────────────────────────────────────────
  # Read-only Docker/Podman socket proxy for Homepage container discovery.
  # Only accessible from the isolated internal network.

  virtualisation.oci-containers.containers.dockerproxy = {
    image = images.dockerproxy;

    volumes = [
      "/var/run/docker.sock:/var/run/docker.sock:ro"
    ];

    environment = {
      CONTAINERS = "1";
      SERVICES = "0";
      TASKS = "0";
      POST = "0";
      TZ = "Europe/Rome";
    };

    log-driver = "journald";

    extraOptions = [
      "--network=isolated"
      "--stop-timeout=30"
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges:true"
      "--read-only"
      "--sdnotify=healthy"
      "--health-cmd=wget -qO- http://localhost:2375/version || exit 1"
      "--health-interval=5s"
      "--health-start-period=30s"
    ];
  };

  # ── Systemd ordering ─────────────────────────────────────────────────

  systemd.services.podman-dockerproxy = {
    after = [
      "podman-network-isolated.service"
    ];
    requires = [
      "podman-network-isolated.service"
    ];
    serviceConfig.Type = "notify";
    serviceConfig.NotifyAccess = "all";
  };
}
