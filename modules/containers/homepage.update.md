---
anchor: homepage
repo: gethomepage/homepage
---

# homepage

Self-hosted dashboard. Single-image deploy — no upstream compose to track, no supporting images.

## Update notes

- Semver tags `v1.x.y`. Releases on GitHub with changelog in release body.
- Widget configs (declared in each container module via `services.homepage.entries`) sometimes break across minor bumps; check release notes for `widgets:` schema changes before bumping.
