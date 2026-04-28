{ lib, ... }:

# Extends `virtualisation.oci-containers.containers.<name>` with an `update`
# submodule used by `modules/version-check.nix` (the daily release watcher).
#
# Only mechanical fields live here — `repo` is what the watcher pings, `primary`
# marks the anchor of a stack. Per-stack quirks, supporting-image maps, and
# upstream compose paths stay in the sibling `<stack>.update.md` for the
# update-containers skill to read.
{
  options.virtualisation.oci-containers.containers = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options.update = lib.mkOption {
          description = ''
            Release-tracking metadata for the watcher. Set on the anchor
            container of each stack; leave null on supporting containers
            (databases, browsers, sidecars).
          '';
          default = null;
          type = lib.types.nullOr (
            lib.types.submodule {
              options = {
                primary = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = "True if this container is the anchor of its stack — the watcher tracks releases off this container's repo only.";
                };
                repo = lib.mkOption {
                  type = lib.types.str;
                  description = "GitHub `<owner>/<name>` for release notes.";
                  example = "immich-app/immich";
                };
              };
            }
          );
        };
      }
    );
  };
}
