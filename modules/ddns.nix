{ config, ... }:

let
  inherit (import ../lib/constants.nix) domain;
in
{
  # ── Dynamic DNS (Namecheap) ───────────────────────────────────────────
  # The apex record `@` is an "A + Dynamic DNS Record" at Namecheap and the
  # wildcard `*` is a CNAME onto it, so updating the apex moves every
  # subdomain with it — only one host needs to be pushed.

  sops.secrets.namecheap_ddns_password = { };

  services.ddclient = {
    enable = true;
    protocol = "namecheap";
    server = "dynamicdns.park-your-domain.com";

    # For this protocol ddclient sends `login` as the domain and each entry in
    # `domains` as the host, so `@` is the apex record.
    username = domain;
    domains = [ "@" ];
    passwordFile = config.sops.secrets.namecheap_ddns_password.path;

    # Namecheap's endpoint only accepts A records; the default would have
    # ddclient chase an IPv6 address it can never push.
    usev6 = "";

    # Namecheap enforces a 5 minute minimum between updates.
    interval = "10min";
    quiet = true;
  };

  systemd.services.ddclient = {
    # ipify has to be reachable, otherwise the first run after boot fails
    # and fires a notification for nothing.
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    onFailure = [ "notify-failure@%n.service" ];
  };
}
