---
anchor: ocis
repo: owncloud/ocis
compose_path: deployments/examples/ocis_full/docker-compose.yml
supporting:
  collabora:
    role: collabora
    pinned_by: compose
    notes: Collabora Online (CODE) — used as the WOPI-backed editor. Pinned per upstream's full-stack compose example.
  tika:
    role: tika
    pinned_by: compose
    notes: shared with paperless stack — both modules consume the same `tika` key in images.nix. Whichever stack is updated last wins.
  ocisExtDrawio:
    role: web-extension
    pinned_by: deploy-guide
  ocisExtJsonViewer:
    role: web-extension
    pinned_by: deploy-guide
  ocisExtUnzip:
    role: web-extension
    pinned_by: deploy-guide
  ocisExtProgressBars:
    role: web-extension
    pinned_by: deploy-guide
---

# ocis

ownCloud Infinite Scale.

## Update notes

- The `ocis` image is also used as the WOPI sidecar (`collaboration` container in ocis.nix); both bump together off the same `images.nix` key.
- Web extensions are NOT in oCIS's main compose. Their pinned versions come from the deploy guide:
  https://owncloud.dev/ocis/deployment/web_extensions/web_extensions/
  Read the guide at the new oCIS version to determine which extension versions to pin.
- Collabora and Tika are read from the `ocis_full` compose at the new oCIS version.
- Major bumps historically ship metadata migrations; expect category `b`-`d` and read the upgrade guide before bumping.
