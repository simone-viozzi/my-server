# Single source of truth for OCI image references.
#
# Update workflow:
#   1. Look up the new digest:
#        skopeo inspect --raw docker://<image>:<tag> | sha256sum
#      (or use `skopeo inspect docker://<image>:<tag>` and copy `Digest`)
#   2. Bump the tag + digest here.
#   3. `nh os switch` — restartTriggers on each container will recreate it.
#
# Per `feedback_image_digests`: pin the platform-specific digest, not the
# manifest list digest. `skopeo --raw` returns the manifest list; pick the
# linux/amd64 entry from inside it.
{
  # ── Shared (multiple consumers — keep in sync) ──────────────────────
  postgres18 = "docker.io/library/postgres:18.3@sha256:86717e5efb6cbea47812978d06ae953d83acea41f31b796af11087df4b31de52";
  tika = "docker.io/apache/tika:3.3.0.0@sha256:eb02f1c06168de85505a238ca1ad6937e2d0c3805795dc1abb0d1235bbb6e6cd";

  # ── Per-service ─────────────────────────────────────────────────────
  apprise = "caronc/apprise:v1.3.3@sha256:4bfeac268ba87b8e08e308c9aa0182fe99e9501ec464027afc333d1634e65977";
  authelia = "authelia/authelia:4.39.16@sha256:edbce01c5125249e4f4faea01e0f76f0031d64b4a1d0c2514a0ca69cb126d05f";
  bentopdf = "ghcr.io/alam00000/bentopdf-simple:v2.8.3@sha256:02cfa04e24619eff21bf511c4ae1aad172f6a8a50bbb1bca37f77c1887b7a31e";
  collabora = "docker.io/collabora/code:25.04.9.4.1@sha256:8301eadc855c8e9ca90a5540ce30cf179dd248748d61c96ea82e0d28a379b0e4";
  dockerproxy = "ghcr.io/tecnativa/docker-socket-proxy:v0.4.2@sha256:1f3a6f303320723d199d2316a3e82b2e2685d86c275d5e3deeaf182573b47476";
  homepage = "ghcr.io/gethomepage/homepage:v1.12.3@sha256:cc84f2f5eb3c7734353701ccbaa24ed02dacb0d119114e50e4251e2005f3990a";

  immichServer = "ghcr.io/immich-app/immich-server:v2.7.5@sha256:cd4aaf5d917fe19b942bba0df4e50eed8e6766190b381e85687cc7880255674e";
  immichMl = "ghcr.io/immich-app/immich-machine-learning:v2.7.5@sha256:c7a8bd9cc982024a55da94c235122449ff8fa91347b6e99f902f31e0349fc623";
  immichValkey = "docker.io/valkey/valkey:9.0.3@sha256:06eccea34d6e9ff4f7daacd598629fb07bf8ddc5cdbc5717bcc13266abcb70e2";
  immichPostgres = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23";

  karakeep = "ghcr.io/karakeep-app/karakeep:0.31.0@sha256:efd9682b69401288c6caa26d76b1c723e4252fe7a962bb78eb00a6cd5227aaca";
  # alpine-chrome's most specific tag is the chrome major (`:124`); upstream does not publish patch tags.
  karakeepBrowser = "gcr.io/zenika-hub/alpine-chrome:124@sha256:58155bc929e3453820bd54c806c73d3abfc07df6454182d87a44df75ea5a1d3a";
  karakeepMeili = "docker.io/getmeili/meilisearch:v1.13.3@sha256:c4d6ab59c18d7b3636e82af862c31861ccf8afb3e9c14dddf9d3e868840667cd";

  # ocis is reused by both the ocis server and the collaboration WOPI sidecar.
  ocis = "docker.io/owncloud/ocis:8.0.1@sha256:b35c557ff56bbddc1dd74d4142d81a8a2cac9ff7e5e774516281a691e42bb153";

  # oCIS web extensions (single-arch linux/amd64 images — no manifest list).
  # Init-container pattern: each copies its app dir into the shared ocis-apps volume.
  ocisExtDrawio = "docker.io/owncloud/web-extensions:draw-io-0.3.3@sha256:57ef8c26e4e811f92e6e2ac784c42969f50ef0ac9e4384dbbf13b12f2a4c1ae4";
  ocisExtJsonViewer = "docker.io/owncloud/web-extensions:json-viewer-0.3.3@sha256:1a609676de54153b4d7618413904b12078119a55ca3379ec75cedd1f84544cea";
  ocisExtUnzip = "docker.io/owncloud/web-extensions:unzip-0.4.3@sha256:9fc726645749514c98c6b9b5a7e6315295897ff5c62a538a3ff383a49272160b";
  ocisExtProgressBars = "docker.io/owncloud/web-extensions:progress-bars-0.3.3@sha256:8faf230c3c601fb4d212720a0edd86073e292893b032021f951512e78e215390";

  paperless = "ghcr.io/paperless-ngx/paperless-ngx:2.20.14@sha256:aacd57f01877d6838deb259f4258975982c1850395cb1bd58e1fb05360b40ca4";
  paperlessRedis = "docker.io/library/redis:8.6.2@sha256:d80663b725aa4303161e59c1f1266fd7eb1af96a4f841a43096273919b2ab795";
  paperlessGotenberg = "docker.io/gotenberg/gotenberg:8.31.0@sha256:799a261dea9e2b724cb789d1cead6ad45e9038f6e88c31182603d0375e91b96e";

  resume = "docker.io/amruthpillai/reactive-resume:v5.0.20@sha256:c82b161bcb807f4768c8fe0c40643bf7374009a25fe13d28b7aaeda5ba83beef";
  resumeBrowser = "ghcr.io/browserless/chromium:v2.48.0@sha256:1e645a20c8c82517bf1ccb5b4302c9608414770bb5b81a8f29086a84a6a5e1ec";
  resumeStorage = "docker.io/chrislusf/seaweedfs:4.19@sha256:751b523268e6f2f8615d019625129e9216ab6a6066d9536124b2aabe42fd4990";
  resumeMc = "quay.io/minio/mc:RELEASE.2025-08-13T08-35-41Z@sha256:eb4ea9884b77704230e2423e9004d2fa738dc272876b9cc41a297d29443b8780";

  silverbullet = "docker.io/zefhemel/silverbullet:2.6.1@sha256:f74038b63d2b72c9f49d44b8c256b4cabbddd38604e576273d2a3609f43b11a2";
  traefik = "traefik:v3.6.11@sha256:acfc80650104f0194a15f73dc1648f517561bc1645391a15705332a064cfc33c";
}
