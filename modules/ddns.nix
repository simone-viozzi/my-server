{ config, ... }:

{
  # ── Dynamic DNS (Namecheap) ───────────────────────────────────────────
  # The apex record `@` is an "A + Dynamic DNS Record" at Namecheap and the
  # wildcard `*` is a CNAME onto it, so updating the apex moves every
  # subdomain with it — only one host needs to be pushed.

  sops.secrets.base_domain = { };
  sops.secrets.namecheap_ddns_password = { };

  # The whole ddclient.conf is rendered by sops: it carries both the domain
  # (login=) and the DDNS password, neither of which should reach the store.
  sops.templates."ddclient.conf".content = ''
    cache=/var/lib/ddclient/ddclient.cache
    foreground=YES
    usev4=webv4, webv4=ipify-ipv4
    protocol=namecheap
    server=dynamicdns.park-your-domain.com
    login=${config.sops.placeholder.base_domain}
    password=${config.sops.placeholder.namecheap_ddns_password}
    quiet=yes
    @
  '';

  services.ddclient = {
    enable = true;
    # Overrides the module-generated config entirely; see the template above.
    configFile = config.sops.templates."ddclient.conf".path;
    # Namecheap enforces a 5 minute minimum between updates.
    interval = "10min";
  };

  systemd.services.ddclient = {
    # ipify has to be reachable, otherwise the first run after boot fails
    # and fires a notification for nothing.
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    restartTriggers = [ config.sops.templates."ddclient.conf".content ];
    onFailure = [ "notify-failure@%n.service" ];
  };
}
