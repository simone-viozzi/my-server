---
anchor: authelia
repo: authelia/authelia
---

# authelia

SSO/2FA portal. Single-image deploy here — no postgres/redis sidecars (uses bundled SQLite + in-memory session store).

## Update notes

- Semver tags `v4.x.y`. Patch bumps are safe; minors occasionally change config schema — read release notes for `configuration:` keys before bumping.
- Configuration lives in sops (`secrets/authelia-config.bin.yaml`). Schema breakage shows up at container start; check `journalctl -u podman-authelia` after `nh os switch`.
