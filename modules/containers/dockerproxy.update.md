---
anchor: dockerproxy
repo: Tecnativa/docker-socket-proxy
---

# dockerproxy

Read-only proxy in front of the docker socket — used by Homepage so it can list containers without raw socket access. Single-image deploy.

## Update notes

- Releases on GitHub with semver tags (`vX.Y.Z`). Slow-moving project; bumps are usually trivial.
- The container is a security boundary — re-read the release notes for any change to the default allow-list before bumping.
