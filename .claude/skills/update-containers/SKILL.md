---
name: update-containers
description: Update one container stack (modules/containers/<stack>.nix) to its latest upstream version — fetch release notes, classify whether infra changes are needed, edit images.nix, build, and commit after the user confirms `nh os switch` worked.
---

# update-containers

Updates **one stack** at a time. A stack = one file in `modules/containers/<name>.nix` (the docker-compose-equivalent for one app). Invocation: `update-containers <stack>` (e.g. `update-containers immich`).

## Hard preconditions

Before doing any work, verify all of these. If any fails, stop and tell the user.

1. **Working-tree state for `modules/images.nix`, `modules/containers/<stack>.nix`, and `_plans/update-containers/<stack>.md`**:
   - Clean → proceed.
   - Uncommitted changes → **do not refuse yet**. Jump to "Mid-flow session recovery" below. Only refuse if recovery determines the diff doesn't match an in-flight plan (i.e. it's unrelated work). Never `git restore` to "clean up" — that's destructive.
2. **Metadata file exists** at `modules/containers/<stack>.update.md`. If missing, refuse and point the user at `reference_metadata_schema` (in memory) — do not auto-bootstrap, the user wants to write these by hand the first time.
3. **All images consumed by the stack are pinned to a real semver tag** in `modules/images.nix`. If you find `:latest`, `:release`, or major-only tags (`:8`, `:124`), refuse and reference `project_todo_pin_image_tags`. Floating tags break version diffing — there is nothing to compare against.

## The anchor model

Each stack has **one anchor image** — the primary application (declared in the metadata file as `anchor:`). Supporting images (databases, caches, sidecars, browser/headless engines, web extensions) are **not** updated independently. Their versions are whatever the upstream's example/recommended compose pins them to **at the anchor's new version**.

- Same major across stacks → keep the image shared in `images.nix` (e.g. `postgres18` used by both paperless and reactive-resume, both on PG 18).
- Different major required by upstream → split the entry into `<stack>Postgres = ...` per stack. **The split itself counts as an infra change** and goes in the plan.
- oCIS web extensions are part of the `ocis` stack — when bumping oCIS, read the oCIS deploy guide at the new version to determine which extension versions to pin.

## State machine

Drive the user through these stages explicitly. Announce which stage you're entering before doing the work.

### Stage 1 — Discover

1. Read `modules/containers/<stack>.update.md` to get `anchor`, `repo`, `compose_path`, and the supporting-image map.
2. Read `modules/images.nix`; record current tag + digest for the anchor and every supporting image listed.
3. Find latest version:
   - Primary: `gh release list --repo <repo> --limit 5` (filter out pre-releases unless metadata says `prereleases: true`).
   - Fallback: `skopeo list-tags docker://<image>` and pick the newest semver-shaped tag.
4. If current == latest → tell the user, stop. (No-op is a valid outcome.)

### Stage 2 — Fetch release notes

For every release **strictly after** current up to and including latest:

1. `gh release view <tag> --repo <repo> --json tagName,body,publishedAt`.
2. If `body` is empty (some projects don't write release notes): fall back to `gh api repos/<repo>/compare/<prev>...<tag> --jq '.commits[] | "\(.sha[0:7]) \(.commit.message | split("\n")[0])"'`. Truncate to first 80 entries; that's enough signal.
3. Concatenate notes in chronological order, prefixed by `## <tag>` headers.

### Stage 3 — Classify (LLM-as-judge)

You are the judge. Read the concatenated notes and decide which of these categories appear. Output a structured verdict the user can audit.

**Categories that force infra review (any one = infra-change update):**
- `a` — Breaking config/env changes (renamed/removed env vars, flag changes, syntax changes in mounted config files).
- `b` — Database schema migration that requires manual steps (vacuum, reindex, lock window, downtime, "you must run X before Y").
- `c` — Volume/data layout change (path moved, format changed, conversion script).
- `d` — New required service/sidecar OR removal of one currently in our compose.
- `e` — Network/port changes (new exposed port, internal port renumbered, new required network).
- `f` — Required external resource (S3 bucket, secret, OIDC client) that wasn't needed before.
- `g` — Permissions/uid/gid change.
- `h` — Backwards-incompatible API change that something we run depends on.
- `i` — Default behavior change with security implications.
- `j` — Image distribution change (registry moved, image renamed, tag scheme changed).

**Skepticism rules — apply BEFORE issuing the verdict:**

The principle: skepticism scales with the size of the jump and the number of releases between current and latest. A patch bump on a calm project gets the benefit of the doubt; a multi-major jump on an active project does not. A user claim that a big jump is drop-in is a hypothesis you have to check against evidence, not a directive to obey.

- **Any major-version jump on the anchor** → start from `force_infra_review = true`. Drop back to `clean` only if you can quote release-note text that affirmatively says nothing breaks (and supporting images don't trip categories either). Absence of bad news is not good news — empty/sparse release notes for a major bump means *more* skepticism, not less.
- **Large jumps** (multiple majors, or many releases skipped on an active project) → plan, full stop. If upstream insists it's drop-in and the user agrees, you still plan — the plan can be short, but the review step exists precisely so a wrong "drop-in" claim gets caught before `nh os switch`.
- **Category triggered, user pushes back** → don't fold to social pressure; fold only to evidence. Re-read the specific release entry, quote it back, and ask the user to point at counter-evidence in the notes. If they can't, the category stands.
- **Override path:** the user can always overrule the recommendation, but you must record their override (and your disagreement, if any) in the verdict and in the commit body. The point is auditability — if it breaks, the trail shows who decided what.

**Verdict output (show to user):**
```
Stack: <stack>
Anchor: <repo> <current> → <latest>  (<N> major / <M> minor)
Supporting images: <list with current → new>
Categories triggered: <a, c> (or "none")
Recommendation: clean | infra-change
Reasoning: <1-3 sentences, citing tags/lines from notes>
```

### Stage 4 — Branch on verdict

#### Clean path

1. Update `modules/images.nix` — bump the anchor's tag + digest, and every supporting image to whatever the upstream compose at the new anchor version pins them at. Use `skopeo inspect --raw docker://<image>:<tag>` and pick the linux/amd64 entry from inside the manifest list (per `feedback_image_digests`).
   - **Supporting-image short-circuit:** read upstream's compose at the new anchor version, extract each `image:tag@sha256:digest`, and compare the digest against the current `images.nix` pin. If digests match → no change for that image, move on. Do NOT probe tags or "look for a cleaner semver" — upstream's pin defines correctness, not our curation. Only when digests differ do you bump tag and digest to upstream's exact values.
2. Run `nh os build .` (NOT `nix build` — `nh os build` invokes nvd and shows a package-level diff, which is what we want for review).
3. If build fails, surface the error, ask the user how to proceed (often it's a config schema change you missed in classification → restart at Stage 3 with `force_infra_review = true`).
4. Show the user the `nh os build` diff plus the `images.nix` diff. Tell them: "Run `nh os switch .` when ready, then tell me whether it worked."
5. **Wait for user confirmation.** Don't commit yet. If they report errors, help debug; the fix may require reverting `images.nix` and going to the infra-change path.
6. On confirmed-working, commit with the message format below. Stage `modules/images.nix` only (and any module file you modified, if applicable). Do not auto-`git add -A`.

#### Infra-change path

1. Write `_plans/update-containers/<stack>.md` (create the directory if needed). Structure:
   ```
   # <stack>: <current> → <latest>

   ## Diff summary
   - Anchor: <repo> <current> → <latest>
   - Supporting: <list of image bumps>
   - Categories triggered: <list>

   ## Required changes
   1. <numbered, concrete edits — file path + what changes>
   2. ...

   ## Open questions
   - <thing you weren't sure about, with a proposed resolution>

   ## Execution order
   1. <ordered steps; build between risky ones>
   ```
2. Show the plan to the user. Iterate interactively — the user can ask for research, request changes, or approve.
3. **Apply changes one at a time.** Edit one file, build, show diff, move on. Do NOT batch. The user wants to see each step.
4. If `images.nix` is part of the changes, do that edit first so the build catches obvious mistakes early.
5. After all edits, run `nh os build .` and present the diff.
6. Tell the user: "Run `nh os switch .` when ready."
7. **Wait for user confirmation.** Iterate on errors.
8. On confirmed-working, commit. Include all modified files.

## Commit format

Searchable, single line subject:
```
<stack>: bump <anchor> to <version>
```

Body (include if any of these apply; otherwise skip for clean updates):
- Supporting-image bumps (one line each).
- Infra changes applied (mirroring the plan's "Required changes").
- Categories triggered (e.g. `Categories: a, c`).
- **Any self-correction performed** (e.g. `compose_path` rewritten) — always log, even on an otherwise trivial clean update. An unaudited metadata rewrite is the failure mode self-correction is supposed to prevent.

Example:
```
immich: bump immich-server to v2.7.0

- immichValkey: 9 → 9.0.2
- immichPostgres: 14-vc0.4.3-pgv0.2.0 → 14-vc0.5.0-pgv0.2.0
- ocr-extraction env var renamed: IMMICH_OCR_LANG → IMMICH_OCR_LANGUAGES
- Categories: a
```

## Self-correction (metadata drift)

Upstream repos move. The metadata file may go stale. Apply these rules narrowly — over-eager rewriting destroys the user's intent.

**`compose_path` 404s:**
1. Search the repo for `docker-compose*.y*ml` (`gh api repos/<repo>/git/trees/HEAD?recursive=1 --jq '.tree[].path | select(test("docker-compose.*ya?ml$"))'`).
2. **If exactly one candidate** → update the metadata file in this commit and log: "self-corrected `compose_path`: <old> → <new>".
3. **If multiple candidates** → list them, ask the user which one is canonical, do NOT guess.
4. **Never touch `repo`.** A wrong `repo` is the user's mistake to fix; auto-rewriting it would silently switch which project we track.

**Release notes path is wrong / repo moved organizations:**
- Confirm via `gh api repos/<old-repo>` (404) and search GitHub. Surface to the user; do not rewrite.

Always log self-corrections in the commit body so the change is auditable.

## Mid-flow session recovery

If preconditions detect uncommitted changes in `modules/images.nix` AND a plan file exists at `_plans/update-containers/<stack>.md`:

1. Read both. Diff `images.nix` against HEAD.
2. If the diff matches what the plan describes → tell the user: "Looks like a previous session was interrupted. Pick up from <stage>?" and offer to continue.
3. If the diff doesn't match the plan → don't assume. Ask the user what state they're in.

Never `git restore` or `git checkout --` to "clean up" — that's destructive.

## Anti-patterns (don't)

- Don't update images one at a time within a stack. Bump anchor + all supporting images together, in one commit.
- Don't probe tags for a supporting image whose upstream-compose digest is unchanged. Same digest = no work.
- Don't `git add -A`. Stage only what you edited.
- Don't run `nh os switch .` yourself. The user runs it.
- Don't skip release notes for "obvious" patch bumps. A patch can ship a breaking config default; classify every time.
- Don't write to memory mid-flow. Plan files are the right place for stack-specific WIP state.
- Don't bootstrap missing metadata files yourself. Refuse and point at the schema HOW-TO.
