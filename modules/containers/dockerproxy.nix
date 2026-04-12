_:

{
  # ── Container ─────────────────────────────────────────────────────────
  # Read-only Docker/Podman socket proxy for Homepage container discovery.
  # Only accessible from the isolated internal network.

  virtualisation.oci-containers.containers.dockerproxy = {
    image = "ghcr.io/tecnativa/docker-socket-proxy:v0.4.2@sha256:1f3a6f303320723d199d2316a3e82b2e2685d86c275d5e3deeaf182573b47476";

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
    onFailure = [ "notify-failure@%n.service" ];
  };
}
