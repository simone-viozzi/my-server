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
  postgres18 = "docker.io/library/postgres:18@sha256:fbcb3dece453834980f7c89e1adad0d8854ff49032430753beec237a9ff069e0";
  tika = "docker.io/apache/tika:latest@sha256:eb02f1c06168de85505a238ca1ad6937e2d0c3805795dc1abb0d1235bbb6e6cd";

  # ── Per-service ─────────────────────────────────────────────────────
  apprise = "caronc/apprise:v1.3.3@sha256:4bfeac268ba87b8e08e308c9aa0182fe99e9501ec464027afc333d1634e65977";
  authelia = "authelia/authelia:4.39.16@sha256:edbce01c5125249e4f4faea01e0f76f0031d64b4a1d0c2514a0ca69cb126d05f";
  bentopdf = "ghcr.io/alam00000/bentopdf-simple:latest@sha256:02cfa04e24619eff21bf511c4ae1aad172f6a8a50bbb1bca37f77c1887b7a31e";
  collabora = "docker.io/collabora/code:25.04.9.4.1@sha256:8301eadc855c8e9ca90a5540ce30cf179dd248748d61c96ea82e0d28a379b0e4";
  dockerproxy = "ghcr.io/tecnativa/docker-socket-proxy:v0.4.2@sha256:1f3a6f303320723d199d2316a3e82b2e2685d86c275d5e3deeaf182573b47476";
  homepage = "ghcr.io/gethomepage/homepage:v1.12.3@sha256:cc84f2f5eb3c7734353701ccbaa24ed02dacb0d119114e50e4251e2005f3990a";

  immichServer = "ghcr.io/immich-app/immich-server:v2.6.3@sha256:0cc1f82953d9598eb9e9dd11cbde1f50fe54f9c46c4506b089e8ad7bfc9d1f0c";
  immichMl = "ghcr.io/immich-app/immich-machine-learning:v2.6.3@sha256:33b17015c3d14f2565e9b8cd36b48a70027b14b5cd20da7fbfff21a370b0309c";
  immichValkey = "docker.io/valkey/valkey:9@sha256:3b55fbaa0cd93cf0d9d961f405e4dfcc70efe325e2d84da207a0a8e6d8fde4f9";
  immichPostgres = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23";

  karakeep = "ghcr.io/karakeep-app/karakeep:release@sha256:efd9682b69401288c6caa26d76b1c723e4252fe7a962bb78eb00a6cd5227aaca";
  karakeepBrowser = "gcr.io/zenika-hub/alpine-chrome:124@sha256:58155bc929e3453820bd54c806c73d3abfc07df6454182d87a44df75ea5a1d3a";
  karakeepMeili = "docker.io/getmeili/meilisearch:v1.13.3@sha256:c4d6ab59c18d7b3636e82af862c31861ccf8afb3e9c14dddf9d3e868840667cd";

  # ocis is reused by both the ocis server and the collaboration WOPI sidecar.
  ocis = "docker.io/owncloud/ocis:8.0.1@sha256:b35c557ff56bbddc1dd74d4142d81a8a2cac9ff7e5e774516281a691e42bb153";

  paperless = "ghcr.io/paperless-ngx/paperless-ngx:latest@sha256:aacd57f01877d6838deb259f4258975982c1850395cb1bd58e1fb05360b40ca4";
  paperlessRedis = "docker.io/library/redis:8@sha256:f4e03de519aa22dc6c0a42e4afb10ef8ff15d818e9d388b0782060e2a4dd583d";
  paperlessGotenberg = "docker.io/gotenberg/gotenberg:8@sha256:799a261dea9e2b724cb789d1cead6ad45e9038f6e88c31182603d0375e91b96e";

  resume = "docker.io/amruthpillai/reactive-resume:latest@sha256:adaa9e95ea80c91d2a1ddc6cf1d5924268f6f5d610910eae29126b152395aab4";
  resumeBrowser = "ghcr.io/browserless/chromium:latest@sha256:35deff208e30b3d8681f21f43f337e475e5bee21ad8b22d41359028e677210b6";
  resumeStorage = "docker.io/chrislusf/seaweedfs:latest@sha256:854479eebcbc0060d803edb27b3bd88a0552e23fde08a26a6482e59aff887a77";
  resumeMc = "quay.io/minio/mc:latest@sha256:a7fe349ef4bd8521fb8497f55c6042871b2ae640607cf99d9bede5e9bdf11727";

  silverbullet = "docker.io/zefhemel/silverbullet:latest@sha256:6c36ff15f2230dbe3bca7e5d0c85a59c7dc831ce694517850ed5797775824d71";
  traefik = "traefik:v3.6.11@sha256:acfc80650104f0194a15f73dc1648f517561bc1645391a15705332a064cfc33c";
}
