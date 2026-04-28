---
anchor: resume
repo: AmruthPillai/Reactive-Resume
compose_path: compose.yml
supporting:
  postgres18:
    role: postgres
    pinned_by: compose
    notes: shared with paperless stack — both consume the same `postgres18` key in images.nix.
  resumeBrowser:
    role: browser
    pinned_by: compose
    notes: browserless/chromium — used as the PDF print backend.
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
- v5 line introduced the seaweedfs+browserless split; major bumps historically rework env vars (`PRINTER_*`, `S3_*`).
