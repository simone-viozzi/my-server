---
anchor: apprise
repo: caronc/apprise-api
---

# apprise

Notification gateway. Single-image deploy — no upstream compose to track, no supporting images.

## Update notes

- Releases live on `caronc/apprise-api` (the API/container project). The library `caronc/apprise` is a separate repo with its own version stream — don't follow it.
- Docker image is published as `caronc/apprise` even though the source repo is `caronc/apprise-api`; tag matches the apprise-api release tag.
