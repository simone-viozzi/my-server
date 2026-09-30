---
anchor: resume
repo: reactive-resume/reactive-resume
compose_path: compose.yml
supporting:
  postgres18:
    role: postgres
    pinned_by: compose
    notes: shared with paperless stack — both consume the same `postgres18` key in images.nix.
  resumeStorage:
    role: s3
    pinned_by: compose
    notes: seaweedfs S3 gateway, used for resume asset storage.
  resumeAwsCli:
    role: cli
    pinned_by: ours
    notes: >
      aws-cli, runs as a one-shot init container to create the resume bucket.
      Replaced minio `mc` in 2026-09, when MinIO withdrew their images from every
      public registry (quay.io and Docker Hub both return unauthorized). Upstream
      compose pins `:latest`, so we pin the newest 2.x ourselves.
---

# reactive-resume

Self-hosted resume builder.

## Update notes

- Upstream compose lives at `compose.yml` at the repo root.
- The `resume-seaweedfs-init` service uses `amazon/aws-cli` and mirrors upstream's
  guarded `head-bucket || mb`. It must talk to the **S3 endpoint (:8333)**, never the
  master's gRPC (:9333): seaweedfs runs `-ip=0.0.0.0`, so the master advertises an
  address sibling containers cannot dial. `weed shell` from another container does not
  work for this reason.
- Upstream added an optional `redis` service in v5.3.2. `REDIS_URL` is `.optional()` in
  `packages/env/src/server.ts` — it gates only the AI agent workspace and cross-instance
  rate limits, so it is deliberately not deployed here.
- Browserless/chromium was removed in v5.1.0 — PDF generation is now client-side
  (`@react-pdf/renderer`); the `PRINTER_*`/`BROWSERLESS_*` env vars are gone.
- Upstream `compose.yml` pins supporting images as `:latest` (demo compose), so it
  gives no version signal — hold seaweedfs/mc/postgres unless release notes require a bump.
