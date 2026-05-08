{
  config,
  pkgs,
  lib,
  ...
}:

# Daily watcher: pings GitHub `releases/latest` for every anchor container
# (one declaring `update.primary = true`) and posts a single bundled markdown
# notification via apprise listing whichever stacks are behind upstream.
#
# Reminder mode (no state file): re-notifies every run until the stack is bumped.
# Anonymous API — 12 stacks/day stays well inside the 60 req/hr unauthenticated
# limit. Add a token via sops if rate-limited; the script accepts GH_TOKEN.

let
  inherit (import ../lib/notify.nix { inherit pkgs; }) notifyMd;

  # "registry/path:tag@sha256:digest" → "tag"
  extractTag =
    imageStr:
    let
      beforeDigest = lib.head (lib.splitString "@" imageStr);
    in
    lib.last (lib.splitString ":" beforeDigest);

  anchors =
    lib.mapAttrsToList
      (name: c: {
        stack = name;
        inherit (c.update) repo;
        tag = extractTag c.image;
      })
      (
        lib.filterAttrs (
          _: c: c.update != null && c.update.primary
        ) config.virtualisation.oci-containers.containers
      );

  stacksJson = pkgs.writeText "version-check-stacks.json" (builtins.toJSON anchors);

  versionCheckScript = pkgs.writeShellScript "version-check" ''
    set -uo pipefail

    stale=()

    while IFS=$'\t' read -r stack repo tag; do
      [ -z "$stack" ] && continue

      auth=()
      [ -n "''${GH_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GH_TOKEN")

      resp=$(${pkgs.curl}/bin/curl -sf \
        --connect-timeout 5 --max-time 10 \
        -H "Accept: application/vnd.github+json" \
        "''${auth[@]}" \
        "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null) || {
        echo "warning: $repo: fetch failed" >&2
        continue
      }

      latest_tag=$(printf '%s' "$resp" | ${pkgs.jq}/bin/jq -r '.tag_name // empty')
      latest_url=$(printf '%s' "$resp" | ${pkgs.jq}/bin/jq -r '.html_url // empty')

      if [ -z "$latest_tag" ]; then
        echo "warning: $repo: no tag_name in response" >&2
        continue
      fi

      # Strip leading 'v' on both sides — repos and our pins disagree on the
      # prefix (authelia/karakeep/ocis/paperless drop it, others keep it).
      if [ "''${tag#v}" != "''${latest_tag#v}" ]; then
        stale+=("- **$stack**: \`$tag\` → \`$latest_tag\` ([notes]($latest_url))")
      fi
    done < <(${pkgs.jq}/bin/jq -r '.[] | "\(.stack)\t\(.repo)\t\(.tag)"' ${stacksJson})

    if [ "''${#stale[@]}" -gt 0 ]; then
      body=$(printf '%s\n' "''${stale[@]}")
      ${notifyMd} "Containers behind upstream" "$body"
    fi
  '';
in
{
  systemd.services.version-check = {
    description = "Check upstream GitHub releases for container drift";
    after = [
      "network-online.target"
      "podman-apprise.service"
    ];
    wants = [
      "network-online.target"
      "podman-apprise.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${versionCheckScript}";
    };
  };

  systemd.timers.version-check = {
    description = "Daily container version-drift check";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 09:00:00";
      Persistent = true;
    };
  };
}
