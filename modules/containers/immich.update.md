---
anchor: immichServer
repo: immich-app/immich
compose_path: docker/docker-compose.yml
supporting:
  immichMl:
    role: ml
    pinned_by: compose
    notes: always same version as immichServer (released together)
  immichValkey:
    role: valkey
    pinned_by: compose
  immichPostgres:
    role: postgres
    pinned_by: compose
    notes: custom image with vectorchord + pgvectors extensions, version string is "14-vectorchord<x>-pgvectors<y>"
---

# immich

Self-hosted photo/video library.

## Update notes

- Server and ML are released together — same tag always.
- Postgres image is immich's fork (`ghcr.io/immich-app/postgres`), version embeds the extension versions. Read `docker-compose.yml` at the new server tag to get the recommended postgres tag.
- Major bumps historically ship a database migration; expect category `b`.
