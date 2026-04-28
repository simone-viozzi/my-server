---
anchor: paperless
repo: paperless-ngx/paperless-ngx
compose_path: docker/compose/docker-compose.postgres-tika.yml
supporting:
  postgres18:
    role: postgres
    pinned_by: compose
    notes: shared with reactive-resume stack — both consume the same `postgres18` key in images.nix.
  paperlessRedis:
    role: redis
    pinned_by: fixed-major
    notes: track the latest `redis:8.x` patch. Don't downgrade — the on-disk RDB format is forward-only within a major; downgrading from a higher 8.x to a lower 8.x can break with "Can't handle RDB format version".
  paperlessGotenberg:
    role: gotenberg
    pinned_by: compose
  tika:
    role: tika
    pinned_by: compose
    notes: shared with ocis stack — both consume the same `tika` key in images.nix.
---

# paperless

Paperless-ngx document management.

## Update notes

- Use `docker/compose/docker-compose.postgres-tika.yml` (postgres + redis + gotenberg + tika variant). The repo also publishes sqlite-only and other variants — don't auto-correct to those.
- Postgres image is the generic `postgres:18` (shared with reactive-resume), not a paperless-specific fork.
- Redis is on a fixed major (`redis:8`); `paperlessRedis` does not appear in upstream compose with a digest pin we mirror, so we curate the patch level. Always pick the latest 8.x — never downgrade.
- Major paperless bumps occasionally ship DB migrations and OCR pipeline changes; expect category `b`.
