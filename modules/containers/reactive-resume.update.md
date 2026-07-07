---
anchor: resume
repo: AmruthPillai/Reactive-Resume
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
  resumeMc:
    role: cli
    pinned_by: compose
    notes: minio `mc` client, runs as a one-shot init container to create the resume bucket. Image tag uses `RELEASE.<timestamp>Z` format, not semver.
---

# reactive-resume

Self-hosted resume builder.

## Update notes

- Upstream compose lives at `compose.yml` at the repo root.
- The `resume-seaweedfs-init` service uses minio's `mc` image with a `RELEASE.<date>Z` tag — there are no semver tags. Track latest stable RELEASE; bumps are essentially "rolling".
- Browserless/chromium was removed in v5.1.0 — PDF generation is now client-side
  (`@react-pdf/renderer`); the `PRINTER_*`/`BROWSERLESS_*` env vars are gone.
- Upstream `compose.yml` pins supporting images as `:latest` (demo compose), so it
  gives no version signal — hold seaweedfs/mc/postgres unless release notes require a bump.
