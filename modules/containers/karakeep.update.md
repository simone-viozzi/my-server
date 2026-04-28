---
anchor: karakeep
repo: karakeep-app/karakeep
compose_path: docker/docker-compose.yml
supporting:
  karakeepBrowser:
    role: browser
    pinned_by: fixed-major
    notes: alpine-chrome's most specific tag is the chrome major (`:124`); upstream does not publish patch tags. Bump only when chrome major rolls forward.
  karakeepMeili:
    role: meilisearch
    pinned_by: compose
---

# karakeep

Self-hosted bookmark/read-it-later manager (formerly hoarder). Three containers: web app, headless chrome (alpine-chrome), meilisearch.

## Update notes

- Compose pins `meilisearch` and a chrome image; we use Zenika's `alpine-chrome` for `karakeepBrowser` instead of upstream's `gcr.io/zenika-hub/alpine-chrome:latest`. Tag `:124` is the most specific upstream publishes — don't try to find a patch version.
- Major bumps historically include a meilisearch index migration; expect data-rebuild on startup.
