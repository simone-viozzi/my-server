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
  apprise = "caronc/apprise:v1.5.1@sha256:c06bdf3074331fabc2dc254bd856bf3d337ba13cea61a21ddab68a820d04d52c";
  authelia = "authelia/authelia:4.39.20@sha256:b5f415d5f14b154c2aa2b186d9f329d879e223da36e115cd871db4c261d5af54";
  bentopdf = "ghcr.io/alam00000/bentopdf-simple:v2.8.6@sha256:430b73233fd5d7c1de63dc94665687f4ebaac37ceb9b867b425785368c78ecda";
  collabora = "docker.io/collabora/code:25.04.9.4.1@sha256:8301eadc855c8e9ca90a5540ce30cf179dd248748d61c96ea82e0d28a379b0e4";
  dockerproxy = "ghcr.io/tecnativa/docker-socket-proxy:v0.4.2@sha256:1f3a6f303320723d199d2316a3e82b2e2685d86c275d5e3deeaf182573b47476";
  homepage = "ghcr.io/gethomepage/homepage:v1.13.2@sha256:c881120b024d6a8e2f3c9664efc568984e4352e47df459d6b32e225374c71955";

  immichServer = "ghcr.io/immich-app/immich-server:v2.7.5@sha256:cd4aaf5d917fe19b942bba0df4e50eed8e6766190b381e85687cc7880255674e";
  immichMl = "ghcr.io/immich-app/immich-machine-learning:v2.7.5@sha256:c7a8bd9cc982024a55da94c235122449ff8fa91347b6e99f902f31e0349fc623";
  immichValkey = "docker.io/valkey/valkey:9.0.3@sha256:06eccea34d6e9ff4f7daacd598629fb07bf8ddc5cdbc5717bcc13266abcb70e2";
  immichPostgres = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23";

  karakeep = "ghcr.io/karakeep-app/karakeep:0.32.0@sha256:f351c5c37cf7bebfe5a32ad99bbd071f8df773f2c55093b30b57771ac83a8667";
  # alpine-chrome's most specific tag is the chrome major (`:124`); upstream does not publish patch tags.
  karakeepBrowser = "gcr.io/zenika-hub/alpine-chrome:124@sha256:58155bc929e3453820bd54c806c73d3abfc07df6454182d87a44df75ea5a1d3a";
  karakeepMeili = "docker.io/getmeili/meilisearch:v1.41.0@sha256:d84b081420b2e5899f5acc3745e1d6510950430fef3ee6b9df5e53b0bf3e19c9";

  # ocis is reused by both the ocis server and the collaboration WOPI sidecar.
  ocis = "docker.io/owncloud/ocis:8.0.6@sha256:0292cda75549cd9199d763a40794d8d7eb411bed56ccba1169eb02f0ba27c4b5";

  # oCIS web extensions (single-arch linux/amd64 images — no manifest list).
  # Init-container pattern: each copies its app dir into the shared ocis-apps volume.
  ocisExtDrawio = "docker.io/owncloud/web-extensions:draw-io-0.3.3@sha256:57ef8c26e4e811f92e6e2ac784c42969f50ef0ac9e4384dbbf13b12f2a4c1ae4";
  ocisExtJsonViewer = "docker.io/owncloud/web-extensions:json-viewer-0.3.3@sha256:1a609676de54153b4d7618413904b12078119a55ca3379ec75cedd1f84544cea";
  ocisExtUnzip = "docker.io/owncloud/web-extensions:unzip-0.4.3@sha256:9fc726645749514c98c6b9b5a7e6315295897ff5c62a538a3ff383a49272160b";
  ocisExtProgressBars = "docker.io/owncloud/web-extensions:progress-bars-0.3.3@sha256:8faf230c3c601fb4d212720a0edd86073e292893b032021f951512e78e215390";

  paperless = "ghcr.io/paperless-ngx/paperless-ngx:2.20.15@sha256:835974fc3368fc6714aa38542db7a1f0f542d03244e39b981e519aefc100f355";
  paperlessRedis = "docker.io/library/redis:8.6.2@sha256:d80663b725aa4303161e59c1f1266fd7eb1af96a4f841a43096273919b2ab795";
  paperlessGotenberg = "docker.io/gotenberg/gotenberg:8.31.0@sha256:799a261dea9e2b724cb789d1cead6ad45e9038f6e88c31182603d0375e91b96e";

  resume = "docker.io/amruthpillai/reactive-resume:v5.2.3@sha256:da1b936d960fa54299be902045c4ecfffe4ec0435949c7e259cbabe15465f4b7";
  # browserless removed in reactive-resume v5.1.0 — PDF generation is now client-side.
  resumeStorage = "docker.io/chrislusf/seaweedfs:4.19@sha256:751b523268e6f2f8615d019625129e9216ab6a6066d9536124b2aabe42fd4990";
  resumeMc = "quay.io/minio/mc:RELEASE.2025-08-13T08-35-41Z@sha256:eb4ea9884b77704230e2423e9004d2fa738dc272876b9cc41a297d29443b8780";

  silverbullet = "docker.io/zefhemel/silverbullet:2.9.0@sha256:9df706c803f7f0a7bc02ae9759273699041f9bd25d5ae8bf062160d5afe6dbd1";
  traefik = "traefik:v3.7.6@sha256:e2c19575dd9ed00f0a6ebc662c0a0c8c8c5df15779100ad7aca14cb5b09d875c";
}
