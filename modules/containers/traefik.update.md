---
anchor: traefik
repo: traefik/traefik
---

# traefik

Reverse proxy / TLS terminator. Single-image deploy. Acts as the entry point for every other web-facing stack.

## Update notes

- Track stable `vX.Y.Z` only; upstream also publishes `-rc` tags (`prereleases: false`).
- Traefik is the ingress for everything — a broken bump takes the whole homelab offline. After `nh os switch`, verify at least one TLS-routed app loads (e.g. homepage, authelia) before walking away.
- File-provider dynamic configs (`*-routing.yaml` mounted into `/etc/traefik/dynamic/` from each stack module) occasionally break across major bumps; check release notes for breaking changes to router/middleware schemas.
