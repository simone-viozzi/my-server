---
anchor: silverbullet
repo: silverbulletmd/silverbullet
---

# silverbullet

Self-hosted markdown notes / personal wiki. Single-image deploy.

## Update notes

- Tags use bare semver (`X.Y.Z`), no `v` prefix. Don't auto-prepend `v`.
- The `space` is mounted from a btrfs subvolume on the host (`silverbullet-space`); plugin/space-script breakage shows up at runtime, not at container start. After a bump, open the UI and exercise plugins before declaring success.
