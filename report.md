# Table of Contents

1. Scope & Methodology
   1.1 What this report covers
   1.2 How status was collected & validated

2. Host & Platform Overview
   2.1 Hardware summary
   2.2 Operating system / kernel
   2.3 Container runtime & orchestration

3. Networking
   3.1 Host firewall (UFW) & nftables
   3.2 Docker networks inventory
   3.3 Traefik front-door summary
   3.4 ACME challenges & HTTP→HTTPS behavior
   3.5 Fail2ban coverage & integration

4. Identity & Access Control
   4.1 Authelia SSO: protected services & policies
   4.2 Per-service local credentials

5. Storage, Data & Backups
   5.1 Disk layout & mounts (Btrfs subvols)
   5.2 Docker volumes by stack
   5.3 Media library paths & permissions (UID/GID 1002)
   5.4 Snapper configs & retention (btrfs2cloud-backup)
   5.5 Backup/restore notes & snapshot locations

6. Monitoring, Logging & Alerting
   6.1 Netdata, Watchtower, Fail2ban — notification targets
   6.2 Logging backends
   6.3 Log rotation status

7. Services Inventory & Health
   7.1 Summary matrix
   7.2 Stack-by-stack details
   7.3 Exposed services & ingress routes
   7.4 Dependencies
   7.5 Flagged issues & quick remediation pointers

8. Reverse Proxy & Certificates (Deep Dive)
   8.1 Traefik entrypoints, routers, middlewares
   8.2 ACME resolvers & challenge types
   8.3 Access/error logging & security headers

9. Notifications & Webhooks
   9.1 Apprise topics/targets in use
   9.2 Other app-specific notifications
   9.3 Telegram channel routing

10. OCIS (ownCloud Infinite Scale)
    10.1 Production setup overview
    10.2 Storage, identity, and TLS integration

11. Access Patterns & Users
    11.1 Usage profile (<10 users, internet-facing)
    11.2 Rate limits / protections

12. Security & Hardening
    12.1 Host hardening summary
    12.2 Secrets at rest — locations & permissions (UID 1000)
    12.3 Recommendations & quick wins

# 1. Scope & Methodology

## 1.1 What this report covers

- **Boundary:** Docker **and** host services (e.g., fail2ban). Libvirt/VMs are out of scope, but we will **confirm none exist** (see 1.2).
- **Inventory classification:** Every container is categorized as **Running**, **Stopped**, **Broken**, or **Ephemeral** (one-shot/utility; still listed but tagged).
- **Problem states included:** Containers that are **restarting** or **unhealthy** (e.g., `plane-app-*`, Mealie) are explicitly called out.
- **Portainer:** Used **only for visibility**; no Portainer-managed stacks. All drift checks assume Compose-managed containers.
- **Secrets handling:** **Environment variable names only** are listed; **values are redacted**.
- **Reachability check surface:** **Traefik front-door** endpoints only: `https://<service>.simoserver.it`.
- **Media pipeline:** Tracked as **Stopped** in the inventory; **no deep-dive** section.
- **Snapshot nature:** **Point-in-time** capture, timestamped in **Europe/Rome**.

## 1.2 How status was collected & validated

- **Timestamping:** Capture a single “as-of” timestamp (Europe/Rome) at the start of the run.
- **Docker inventory (high-level):**
  - Enumerate all containers (incl. health + restart counts).
  - **Status rules:**
    - **Running:** `State=running` and either `healthy` or no healthcheck; not in `restarting`.
    - **Stopped:** `State=exited`/`created`.
    - **Broken:** `State=unhealthy` **or** `State=restarting` **or** `RestartCount ≥ 3` (sampled over a short window to catch active loops).
    - **Ephemeral:** One-shot/maintenance containers (e.g., migrations/backups) that exit shortly after start; still listed but tagged.
- **Compose ↔ runtime drift:**
  - For each **compose directory** (subfolders containing `compose.yml`/`docker-compose.yml`), render canonical spec with `docker compose config` and map services to running containers via `com.docker.compose.*` labels.
  - **Report diffs** across: images (name:tag@digest), ports, volumes/binds, **environment (names only)**, labels (incl. Traefik), networks, restart policy, and healthcheck.
  - **Flag** runtime-only containers (no matching compose service) and compose-only services (no running container).
  - Note: Compose has no strict built-in drift checker; where supported, `docker compose up --dry-run` can show intended actions. Otherwise, diff `compose config` output vs. `docker inspect`.
- **Front-door reachability (Traefik):**
  - For each service domain: issue an HTTPS **HEAD/GET** to `https://<service>.simoserver.it` and record status/redirects and certificate presence.
  - (Optional) Probe `http://` to confirm **80 → 443 redirect** is active.
- **Host services:**
  - **fail2ban:** capture service status and active jails summary.
  - **netdata / watchtower / traefik:** if containerized, they appear in the Docker inventory; if host-services, record their service status at snapshot time.
- **Logging/monitoring notes captured as context:** immich uses **journald** (for fail2ban compatibility); alerts flow to **Telegram**; no additional host log rotation beyond Docker options.
- **Libvirt “nothing running” confirmation (expected none):**
  - `virsh list --all` and `virsh net-list --all` should both be empty for VMs/networks.

# 2. **Host & Platform Overview**
## 2.1 Hardware summary *(README note: current hardware differs from repo README; this section supersedes it)*
- **Form factor:** Bare metal (not virtualized) — `systemd-detect-virt: none`.
- **Motherboard/UEFI:** Gigabyte B450 AORUS M • UEFI F65b (2023-09-20).
- **CPU:** AMD Ryzen 5 5600G (6C/12T).
- **Memory:** 16 GiB DDR4 installed (2/4 slots; non-ECC). Swap: 19 GiB (btrfs swapfile).
- **GPU:** Integrated AMD Cezanne (amdgpu) — headless.
- **NIC:** `eno1` — IPv4 `192.168.178.251/24`, IPv6 prefixes present.
  - `virbr0` exists (libvirt bridge) but **DOWN**; no active guests.
- **Storage:**
  - **sda:** 240 GB Kingston SATA SSD → Arch root (btrfs subvolumes).
  - **sdb:** 4 TB WD Red SATA HDD → data & Docker volumes (btrfs, multiple subvols/snapshots).

## 2.2 Operating system / kernel (Arch Linux)
- **OS:** Arch Linux.
- **Kernel/arch:** `6.15.3-arch1-1` (x86_64).
- **Hostname / TZ / time:** `server` • `Europe/Rome` • NTP synced.
- **LSMs:** capability, landlock, lockdown, yama, bpf (cgroup v2 host).

## 2.3 Container runtime & orchestration
- **Docker:** `28.3.3` (root dir: `/var/lib/docker`).
- **Docker Compose:** `2.39.1`.
- **Storage driver:** `btrfs` (set in `/etc/docker/daemon.json`).
- **Default logging driver:** `json-file`.
- **Cgroups:** Driver `systemd`, **Cgroup v2**.
- **Runtimes:** `runc` (default), `io.containerd.runc.v2` • containerd present.
- **Swarm:** inactive.


# 3. **Networking**

**Summary:** Traefik fronts all public traffic on `:443` (TLS-ALPN-01 for ACME). `:80` is configured in Traefik for HTTP→HTTPS redirection, but UFW currently does **not** allow 80/tcp inbound. Fail2ban enforces bans at the **host firewall** via iptables (INPUT and DOCKER-USER), covering SSH and several containerized apps. No libvirt guests are running (default libvirt network is present but unused).

---

## 3.1 **Host firewall (UFW) & nftables**
- **UFW:** Active, default **deny (incoming)** / allow (outgoing/routed). Explicit rules include `443/tcp (LIMIT)`, `29902/tcp (ALLOW)`, `32400/tcp (ALLOW)`, `14014/tcp,udp (ALLOW)`, `9090/tcp (ALLOW)`, `5012/tcp (ALLOW)`, `35643/tcp (ALLOW)`. **No rule for 80/tcp.**
- **Listeners:** `:80` and `:443` are listening via Docker (Traefik) on v4 and v6.
- **nftables:** Only **libvirt** tables/chains are present (guest_*), no custom rulesets beyond libvirt.
- **Libvirt state:** No VMs; `default` network is active.

> **Implication:** External HTTP→HTTPS redirects will be blocked at the host firewall unless 80/tcp is allowed in UFW. ACME is unaffected (TLS-ALPN-01 uses 443).

## 3.2 **Docker networks inventory**
Bridge networks present:
- `apprise`, `bridge` (default), `hoarder_local`, `homepage-net`, `immich_immich`,
  `mealie_local`, `media`, `ocis_full_ocis-net`, `paperless_internal`, `plane-app_local`,
  `portainer_internal`, `proxy` (Traefik), `spliit_local`, plus `host`, `none`.

**Traefik attachment:** `proxy` (reverse-proxy front-door).
**Other notable networks:** `homepage-net` (used to surface apps on the homepage).

## 3.3 **Reverse proxy & certificates (Traefik)**
- **Deployment:** Docker, image tag **`traefik:latest`**, configured **via labels** (file provider not used). Logs volume at `./logs:/var/log`.
- **Entrypoints:**
  - `web` → `:80` (HTTP)
  - `websecure` → `:443` (HTTPS)
- **Global redirect:** `web` → `websecure` via `entryPoints.web.http.redirections.entryPoint.to=websecure` and middleware `redirect-to-https`.
- **ACME (resolver `leresolver`):**
  - Email: `${EMAIL}` (from `.env`)
  - **Challenge:** **TLS-ALPN-01 = enabled**; **HTTP-01 = disabled**; DNS-01 = disabled
  - **Storage:** `/certs/acme.json` **inside a Docker named volume (`certs`)**; not host-bind-mounted (permissions managed in-container).

## 3.4 **ACME challenges & HTTP→HTTPS behavior**
- **Challenge path:** TLS-ALPN-01 on `:443` only (works without `:80`).
- **HTTP→HTTPS:** Redirect is configured in Traefik, **but UFW does not currently allow 80/tcp**; external HTTP requests won’t reach Traefik to be redirected. If you want browser-level redirects from plain HTTP, add a UFW allow (or keep 80 blocked and rely on direct HTTPS/HSTS).
- **IPv6:** No AAAA records for `*.simoserver.it`; public ACME/traffic is IPv4-only (Traefik still listens on v6 locally).

## 3.5 **Fail2ban coverage & integration**
- **Actions backend:** **iptables** (`iptables-multiport`, `iptables-allports`).
  - Hooks: `INPUT` (for `sshd`), **`DOCKER-USER`** (for containerized services) → bans are **global** across all container ports.
  - Reject mode: `REJECT --reject-with icmp(6)-port-unreachable`.
- **Enabled jails (7):** `authelia`, `immich`, `jellyfin`, `jellyseerr`, `paperless`, `sshd`, `traefik`. *(Currently 0 banned across jails.)*
- **Log sources:**
  - **Traefik:** `./logs` (bind-mounted into the container)
  - **Authelia:** `authelia/config/authelia.log`
  - **Immich:** **journald** (unit: `immich-server`)
  - Others read from their respective Docker JSON/journald as configured.
- **UDP note:** If any UDP services are re-exposed (e.g., qBittorrent `6881/udp`), consider adding a UDP-aware ban action. Currently the media pipeline is **stopped**; router forwards for qBittorrent (`6881/tcp,udp`) can be **closed**.

**External reachability (router forwards):** `29902/tcp` (SSH), `80/tcp`, `443/tcp`, *(qBittorrent `6881/tcp,udp` — legacy; can be removed while the stack is stopped).*


# 4. **Identity & Access Control**

## 4.1 Authelia SSO: protected services & policies

- **SSO architecture**: Traefik forward-auth to **Authelia** for selected services; others use their own local auth.
- **Auth backend**: `users_database.yml` (file-based).
- **Default policy**: `deny`.
- **Groups**: `admins`, `users`.

**Domain policies (excerpt of effective rules):**
- `auth.simoserver.it` → **bypass** (login/consent).
- `traefik.simoserver.it` → **two_factor** (restricted to **group: admins**).
- `silverbullet.simoserver.it`
  - **bypass** for static client assets (`/.client/manifest.json`, client PNGs, `service_worker.js`).
  - **one_factor** for **group: admins** (Silverbullet doesn’t support native SSO; protected via Traefik + Authelia middleware).
- `hoarder.simoserver.it` → **one_factor** (`users`, `admins`).
- `mealie.simoserver.it` → **one_factor** (`users`, `admins`).
- `gpt.simoserver.it` (OpenWebUI) → **one_factor** (`users`, `admins`).
- `split.simoserver.it` → **one_factor** (`users`, `admins`).
  _Note: service name elsewhere appears as **spliit**; verify domain spelling to avoid an unenforced rule._

**Session / cookie settings**
- Cookie domain: `simoserver.it`, name: `authelia_session`, `SameSite=lax`.
- Session expiration: **1h**; inactivity timeout: **5m**; “remember me”: **2 months**.
- Session secret: `/run/secrets/SESSION_SECRET`.
  _Sessions are in-memory (no Redis); they reset on container restarts._

**OIDC provider (Authelia)**
- Issuer: `https://auth.simoserver.it`
- Registered clients (values redacted):
  - **Mealie** → OIDC enabled; **local login form still available** (`ALLOW_SIGNUP=false`, `OIDC_AUTO_REDIRECT=false`, `OIDC_SIGNUP_ENABLED=true`). Redirect: `https://mealie.simoserver.it/login`.
  - **Hoarder** → **OIDC-only** (no separate local login). Redirect: `https://hoarder.simoserver.it/api/auth/callback/custom`.
  - **OpenWebUI (gpt)** → **OIDC-only** (`ENABLE_LOGIN_FORM=false`, `ENABLE_SIGNUP=false`). Redirect: `https://gpt.simoserver.it/oauth/oidc/callback`.

**Dashboards**
- **Traefik dashboard**: `https://traefik.simoserver.it/` protected with **2FA (admins only)**.
- **Portainer UI**: **not exposed** externally (no Authelia route).

**Config & secrets locations**
- Authelia stack: `./authelia/{docker-compose.yml, config/, data/, secrets/}`.
- Observed files: `config/configuration.yml`, `config/users_database.yml`, `config/authelia.log`.
- Ownership: user **uid 1000** (`simone`).
  _Hardening note_: `configuration.yml` and `users_database.yml` appear world-readable/executable (e.g., `-rwxr-xr-x`). Recommend **0600/0640** and `chown 1000:1000` for config; keep secrets in `/run/secrets` (already used for `SESSION_SECRET`).

---

## 4.2 Per-service local credentials (where applicable)

- **SSO-integrated**
  - **Mealie**: Authelia **OIDC** enabled; local login form present. Relevant env toggles (values redacted): `ALLOW_SIGNUP`, `OIDC_AUTO_REDIRECT`, `OIDC_SIGNUP_ENABLED`, plus OIDC client/secret vars in the compose `.env`.
  - **Hoarder**: **OIDC-only** (no local login). OIDC client/secret in compose `.env` (redacted).
  - **OpenWebUI (gpt)**: **OIDC-only**. Env toggles (redacted): `ENABLE_LOGIN_FORM=false`, `ENABLE_SIGNUP=false`, plus OIDC client/secret vars.

- **Forward-auth protected (no native SSO)**
  - **Silverbullet**: Protected by Traefik + Authelia middleware; app itself does not support OIDC. Static asset endpoints bypassed for client load.

- **Local-auth (not SSO-gated unless Traefik labels added)**
  - Examples in this environment: **Immich**, **Jellyfin/Jellyseerr**, **Paperless**, **OCIS**, **Kavita**, **Scrutiny**, **Netdata**, **Homepage/Homarr**, **Stirling-PDF**, **MySpeed**, **Plane**, **Spliit**, **Portainer** (internal only).
  - **Credential source**: each stack’s `.env` and/or application database/volume.
  - **Env var naming**: documented at stack level (values redacted). Common patterns include admin bootstrap variables (e.g., `ADMIN_USER`, `ADMIN_PASSWORD`/`*_FILE`) where supported.

_Notes_
- Secrets are stored alongside each compose in `.env`/`secrets` and owned by **uid/gid 1000** (values redacted in this report).
- If desired, we can enumerate each stack’s exact **env var names** from the compose files and list them here with values redacted.

# 5. **Storage, Data & Backups**

**Summary:**
- SSD `/dev/sda` (Btrfs) hosts OS and `/var/*`; HDD `/dev/sdb` (Btrfs) hosts app data via dedicated subvolumes mounted under `/docker-volumes/*` and bound into Docker named volumes.
- Snapshots exist per-dataset in `.<snapshots>` subvolumes and are replicated offsite by **btrfs2cloud-backup** (weekly, randomized).
- Media library is owned by service account **torrents:torrents (UID/GID 1002)**; perms are intentionally broad for pipeline compatibility.

---

### 5.1 Disk layout & mounts (Btrfs)
- **Physical disks**
  - `sda` – 240 GB **Kingston SA400S37240G** (SSD) → `btrfs` root with subvolumes:
    - `/` → `subvol=@`, plus `/@home`, `/@cache`, `/@log`, `/@tmp`, `/@srv`, `/@swap`, `/@quemu-storage-pool`, and Snapper subvols under `/.snapshots`, `/home/.snapshots`.
    - Mount opts (representative): `compress=zstd`, `ssd`, `discard=async`, `space_cache=v2`.
  - `sdb` – 4 TB **WD40EFAX-68JH4N1** (HDD) → `btrfs` data pool:
    - Top-level: `/data/wd-red`, `/system-backup`.
    - **Per-service subvols** mounted as `/docker-volumes/@<name>` with matching `.<snapshots>` (e.g., `/docker-volumes/immich-pgdata` and `/docker-volumes/immich-pgdata/.snapshots`).
- **Where Docker stores data**
  - `Docker Root Dir`: `/var/lib/docker` (Btrfs).
  - Named volumes are mounted at `/var/lib/docker/volumes/<name>/_data` and **backed by** the HDD subvols listed in 5.2 (see `findmnt` mappings).

---

### 5.2 Docker volumes by stack (selected mapping)
> All paths below resolve under `/var/lib/docker/volumes/<name>/_data` and are backed by `/docker-volumes/@<name>` (with `.<snapshots>` alongside) unless noted.

- **Reverse proxy (Traefik)**
  - `traefik_certs` → contains `acme.json` at `/certs/acme.json` inside the container (named volume, not host file bind).

- **OCIS (ownCloud Infinite Scale)**
  - `ocis-config`, `ocis-data`, `ocis_full_ocis-apps`, `ocis_wopi_companion-data`, `ocis_wopi_wopi-recovery`.

- **Paperless**
  - `paperless-data`, `paperless-media`, `paperless-pgdata`, `paperless_redisdata`.

- **Immich**
  - `immich-pgdata`, `immich-upload`, `immich_tsdata`, `immich_model-cache`.

- **Mealie**
  - `mealie-data`, `mealie-pgdata`.

- **Plane (makeplane)**
  - Current: `plane-app_pgdata`, `plane-app_redisdata`, `plane-app_rabbitmq_data`, `plane-app_logs_{api,worker,beat-worker,migrator}`.
  - Legacy/parallel present: `plane-db`, `plane-uploads`. *(Duplicate lineage noted; see drift section for reconciliation.)*

- **Hoarder**
  - `hoarder-data`, `hoarder_hoarder-meilisearch`.

- **Spliit**
  - `spliit-db`, `spliit_postgres_data`. *(Both present.)*

- **Monitoring / misc**
  - Netdata: `netdata_netdatalib`, `netdata_netdatacache`, plus legacy/alt names `monitor_*` and `moritor_*`.
  - Speedtest-tracker: `speedtest-tracker_myspeed`, `speedtest-tracker_speedtest-db`.
  - Portainer: `portainer_portainer-data`.

- **Media pipeline (currently **Stopped**)**
  - `media-lib` (library), `qbit-config`, `qbit-torrents`, `jackett-*`, `prowlarr-config`, `sonarr-config`, `radarr-config`, `readarr-config`, `jellyfin-config`, `jellyfin_jellyfin-cache`.

---

### 5.3 Media library paths & permissions
- **Primary library**: `/home/simone/media-lib`
  - Owner: **torrents:torrents (UID/GID 1002)**; mode **0777** (broad by design).
  - Top-level dirs observed: `media/`, `torrents/`, `usenet/` (0777), and private `/.Trash-1002` (0700).
- **Data pool root**: `/data/wd-red` → owner `simone`, mode **0755**.
- **Note:** UID/GID **1002** is used in multiple stacks; on-disk ownership aligns with container expectations.

---

### 5.4 Snapper configs & retention (managed by **btrfs2cloud-backup**)
- **Configs present** (non-exhaustive): `root`, `home`, `immich-{pgdata,upload}`, `paperless-{data,media,pgdata}`, `mealie-{data,pgdata}`, `ocis-{config,data}`, `kavita-config`, `jellyfin-config`, `silverbullet-space`, `plane-{db,uploads}`, `hoarder-data`, `spliit-db`, … *(all have matching `.<snapshots>` subvols).*
- **Retention (examples):**
  - `root` / `home`
    - Number: keep **3** (important **2**), min age **1800s**.
    - Timeline: **enabled**; Daily **2**, Weekly **1** (root); Daily **2** (home); Hourly/Monthly/Yearly as reported.
  - DB datasets (`paperless-pgdata`, `immich-pgdata`)
    - Number: keep **3** (important **10**), min age **1800s**.
    - Timeline: **disabled** (`TIMELINE_CREATE=no`). *(Limits exist but not used while timeline is off.)*
- **Scheduling:** Offsite replication handled by systemd **timers, weekly** with `RandomizedDelaySec=4d` (per-dataset units; see 5.5).

---

### 5.5 Backup/restore notes & snapshot locations
- **Mechanism:** `btrfs2cloud-backup` (one unit per dataset)
  - Creates a **Snapper** snapshot (`type=single`, `config=<name>`), then streams via:
    - `btrfs send` → `zstd -<level>` → **OpenSSL AES-256** → `rclone rcat` to `${CLOUD_NAME}:${BUCKET_NAME}/${config_name}/`.
  - **State file** `${timestamp}_state.txt` marks in-progress/OK; old snapshots pruned to `SNAPSHOTS_TO_KEEP`.
  - **Notifications:** via **Apprise** to Telegram.
  - **Coordination:** `flock` lock + `systemd-inhibit` to avoid sleep; retries enabled for rclone.
  - **Schedule:** `.timer` units **weekly** (persistent). Manual run: `systemctl start btrfs2cloud-<config>.service`.
  - **Config:** `/etc/btrfs2cloud/config` (contains `CLOUD_NAME`, `BUCKET_NAME`, `RCLONE_CONFIG_PATH`, `OPENSSL_PASSWD`, etc.). *(Values managed out-of-band; not stored in repo.)*
- **Databases:**
  - Primary protection is **filesystem snapshots** (crash-consistent).
  - Some apps also write **periodic logical dumps** into their own volume; these are included if present. *(No coordinated quiesce across containers.)*
- **Snapshot locations (on disk):** `<dataset>/.snapshots/<id>/snapshot`.
  **Offsite path:** `${CLOUD_NAME}:${BUCKET_NAME}/${config_name}/${timestamp}_snapshot`.
- **Restore approach (on-prem / offsite):**
  1. **Stop** target container(s).
  2. **Receive** desired snapshot into a staging subvol (`btrfs receive …`).
  3. **Swap** the live subvolume/volume mount to the restored snapshot and **start** container(s).
- **Intentionally excluded from offsite (policy: “no value / reproducible”):**
  - Caches & ephemeral data: `jellyfin_jellyfin-cache`, `immich_model-cache`, Netdata caches (`*netdatacache`, `*netdatalib`), Redis/RabbitMQ data (`paperless_redisdata`, `plane-app_redisdata`, `plane-app_rabbitmq_data`, `authentik_*redis*`), browser/Chrome work dirs, temporary converters (e.g., Tika/Gotenberg working data).
  - *(Exact exclude set follows the per-dataset unit selection; anything without a Snapper config is de-facto excluded.)*
- **Maintenance:** No scheduled **btrfs scrub/balance** timers currently configured.

**Out of scope / empty:** `/quemu-storage-pool` (present, currently empty).


# 6. **Monitoring, Logging & Alerting**

**6.1 Netdata, Watchtower, Fail2ban — notification targets (Telegram)**
- **Netdata (containerized)**: runs with `pid: host` and `network_mode: host`; claimed to Netdata Cloud via `NETDATA_CLAIM_*`. Alerting uses **native `health_alarm_notify` → Telegram** (bot token & chat ID **redacted**). No custom silences/overrides—defaults in effect.
- **Watchtower**: polls **hourly** (`WATCHTOWER_POLL_INTERVAL=3600`), exposes metrics/API (tokened) and sends **Telegram** notifications via **Shoutrrr URL**. No cron `--schedule`, no `--cleanup` flag (old images not auto-pruned), and **no label filtering** → monitors all running containers.
- **Fail2ban**: jails = `authelia, immich, jellyfin, jellyseerr, paperless, sshd, traefik`. Actions are host-level **iptables** (INPUT / DOCKER-USER). Notifications use a **custom `action.d/apprise.conf`** to post to the **Apprise** container (Telegram target). No IPs currently banned.
- **Apprise hub**: central notifier used by **btrfs2cloud** and **Fail2ban** (and available to others). Primary tag/topic: `admin`.

**6.2 Logging backends**
- **Immich**: logs to **journald** (chosen so Fail2ban can match via `journalmatch` on the container unit).
- **Traefik**: writes app/file logs under its bound `./logs` directory (used by Fail2ban).
- **Other services**: standard Docker logging plus app-level file logs for Fail2ban. Docker’s global default is `json-file`; several services **override** to `logging.driver: local` and set size caps.
  - Examples observed:
    - `netdata`: `driver=local`, `max-size=10m`, `max-file=3`
    - `watchtower`: `driver=local`, `max-size=10m`, `max-file=2`

**6.3 Log rotation status (host & containers)**
- **Host (journald)**: default retention (no custom `journald.conf`).
- **Docker logs**: no global `log-opts` in `daemon.json`; **per-service** caps/rotation are set in many compose files (see examples above). Where not set, Docker log growth follows the driver’s defaults.
- **App file logs**: Fail2ban-watched files (e.g., **Traefik `./logs`**, Paperless/Jellyfin/Jellyseerr paths) currently **have no external logrotate** configured.
- **Netdata & Watchtower**: container log rotation handled via the compose `max-size/max-file` shown above.

# 7. Services Inventory & Health
**Snapshot:** 2025-08-16T18:58:39+02:00 (Europe/Rome)

## 7.1 Summary matrix (by container/service name)

**Running — healthy**
- authelia • homepage • immich_server • immich_postgres • immich_redis • immich_machine_learning • netdata
- paperless-webserver • ocis_full-collabora-1 • spliit-db-1 • watchtower • kavita

**Running — no healthcheck (or not reported)**
- traefik • apprise • homarr • hoarder-hoarder-web-1 • hoarder-hoarder-chrome-1 • hoarder-hoarder-meilisearch-1
- MySpeed • paperless_db • paperless_broker • paperless_gotenberg • paperless_tika
- ocis_full-ocis-1 • ocis_full-collaboration-1 • ocis_full-tika-1
- portainer • portainer_agent • scrutiny • silverbullet-silverbullet-1 • spliit-app-1 • open-webui/ollama (via stack) • stirling-pdf-stirling-pdf-1 • homepage

**Restarting (problem)**
- plane-app-api-1 • plane-app-worker-1 • plane-app-live-1 • plane-app-beat-worker-1
  - **Symptoms:** `api/worker/beat` fail on DB connect: `django.db.utils.OperationalError: Name does not resolve` (cannot resolve **PGHOST**).
  - **Live** fails with `Cannot find module '/app/live/dist/server.js'` (image/build mismatch).

**Running — unhealthy**
- **mealie**: health = `unhealthy`
  - **Symptom:** DB error `relation "groups" does not exist` → schema/migrations not applied.

**Stopped (intentionally or pipeline paused)**
- **Media pipeline:** qbittorrent, jackett, flaresolverr, prowlarr, sonarr, radarr, readarr (all stopped)
- **Jellyfin** (stopped)

> Ephemeral/maintenance containers are included when present (e.g., paperless `change-vol-ownership`), and tagged as **ephemeral**.

---

## 7.2 Stack-by-stack details

> **Conventions:** Env **names only** (values redacted). Volumes shown as `host_or_named_volume:container_path`. Networks list includes external networks used. Healthchecks summarized where defined.

### Traefik / Proxy
- **Image:** `traefik:latest`
- **Ports:** `80→80`, `443→443`
- **Key labels:** routers for domains via `...rule: Host(\`$VAR\`)`, TLS via `leresolver`, global HTTP→HTTPS redirect
- **Volumes:** `./logs:/var/log`, `certs:/certs`, `/var/run/docker.sock:/var/run/docker.sock:ro`
- **Networks:** `proxy`, `homepage-net`
- **Notes:** Access log enabled to file; ACME TLS-ALPN-01; dashboard at `${TRAEFIK_DOMAIN}` behind Authelia 2FA.

### Authelia (SSO)
- **Image:** `authelia/authelia:latest`
- **Ports:** internal only (`9091`)
- **Volumes/Secrets:** `./config:/config`, `./data:/var/lib/authelia`, secrets: `JWT_SECRET`, `SESSION_SECRET`, `STORAGE_PASSWORD`, `STORAGE_ENCRYPTION_KEY` (files)
- **Env:** `TZ`, plus OIDC config in file; sessions in-memory
- **Networks:** `proxy`
- **Ingress:** `${AUTH_DOMAIN}` → service port `9091` (TLS)
- **Protected apps:** Mealie, Hoarder, OpenWebUI (OIDC); Spliit via forward-auth; Traefik dashboard 2FA; Silverbullet uses middleware (limited SSO support).

### Immich
- **Images:** `immich-server:${IMMICH_VERSION:-release}`, `immich-machine-learning:${IMMICH_VERSION:-release}`, `valkey:8-bookworm`, `immich-app/postgres:14-...`
- **Ports:** API served via Traefik (internal service port `2283`)
- **Volumes:** `immich-upload:/usr/src/app/upload`; `immich-pgdata:/var/lib/postgresql/data`; `model-cache:/cache`
- **Env (names):** `DB_* (USER/PASSWORD/NAME)`, standard Immich `.env`
- **Networks:** `proxy`, `immich`, `homepage-net`
- **Health:** server healthy (journald logging); ML has Docker healthcheck.

### Paperless-ngx
- **Images:** `paperless-ngx:latest`, `redis:7`, `postgres:15`, `gotenberg:7.8`, `paperless-ngx/tika:latest`
- **Ports:** `8150→8000` (also behind Traefik)
- **Volumes:** `paperless-data:/usr/src/paperless/data`, `paperless-media:/usr/src/paperless/media`, `paperless-pgdata:/var/lib/postgresql/data`, `./logs:/usr/src/paperless/data/log`
- **Env (names):** `PAPERLESS_DBHOST`, `PAPERLESS_REDIS`, `PAPERLESS_TIKA_*`, `.env`
- **Networks:** `proxy`, `internal`, `homepage-net`
- **Health:** web healthcheck `curl http://localhost:8000` (OK)

### Mealie (**issue: unhealthy**)
- **Image:** `ghcr.io/mealie-recipes/mealie:latest`
- **Ports:** behind Traefik (service port `9000`)
- **Volumes:** `mealie-data:/app/data/`
- **Env (names):** `ALLOW_SIGNUP=false`, `BASE_URL`, DB (`DB_ENGINE=postgres`, `POSTGRES_*`, `POSTGRES_SERVER=postgres`), OIDC (`OIDC_*`)
- **DB service:** `postgres:15` (healthcheck `pg_isready`; volume `mealie-pgdata:/var/lib/postgresql`)
- **Networks:** `proxy`, `local`
- **Symptom:** `ProgrammingError: relation "groups" does not exist` → database schema not created/migrated.

### Hoarder
- **Images:** `karakeep:release`, `alpine-chrome:123`, `getmeili/meilisearch:v1.6`
- **Ports:** via Traefik (service `3000`)
- **Volumes:** `hoarder-data:/data`, `hoarder-meilisearch:/meili_data`
- **Env (names):** `.env`, `NEXTAUTH_URL`, `OAUTH_WELLKNOWN_URL`, `MEILI_ADDR`, `BROWSER_WEB_URL`
- **Networks:** `proxy`, `homepage-net`, `local`
- **Health:** not reported by containers; web shows healthy in `docker ps`.

### OCIS (incl. Collabora)
- **Images:** `owncloud/ocis:latest`, `collabora/code:24.04...`, plus side services in the bundle
- **Ports:** via Traefik (`9200` target)
- **Volumes:** `ocis-config:/etc/ocis`, `ocis-data:/var/lib/ocis`, extra config files mapped
- **Env (names):** `OCIS_URL`, `COLLABORA_DOMAIN`, `ONLYOFFICE_DOMAIN`, SMTP vars
- **Networks:** `ocis-net`, `proxy`
- **Health:** Collabora has healthcheck in its compose; others run fine.

### Portainer
- **Images:** `portainer/portainer-ce:latest`, agent `portainer/agent:2.16.2`
- **Ports:** `9445→9443`, `8000→8000` (local/LAN only), agent `9001`
- **Volumes:** `portainer-data:/data`
- **Networks:** `homepage-net`, `internal`
- **Ingress:** **not** exposed via Traefik (dashboard local at https://localhost:9445)

### Homepage / Homarr
- **Images:** `gethomepage/homepage:latest`, `homarr:latest`
- **Ports:** `3000→3000` (Homepage), `7575→7575` (Homarr)
- **Volumes:** homepage config and Homarr data directories
- **Networks:** `homepage-net`, Homarr also `proxy`
- **Ingress:** Homarr via `${PUBLIC_HOMEPAGE_DOMAIN}` (TLS)

### Plane (makeplane) — **broken**
- **Images:** `makeplane/plane-backend:stable` (api/worker/beat/migrator), `makeplane/plane-live:stable`, `plane-frontend`, `plane-space`, `plane-admin`, plus `postgres:15.7-alpine`, `valkey:7.2.5-alpine`, `rabbitmq:3.13`, `minio:latest`
- **Ports:** proxied via Traefik by the `proxy` service (target `80`)
- **Volumes:** `plane-db:/var/lib/postgresql/data`, `plane-uploads:/export`, `logs_*`, `redisdata`, `rabbitmq_data`
- **Env (names):** DB (`PGHOST`, `PGDATABASE`, `POSTGRES_USER/PASSWORD/DB`, `DATABASE_URL`), Redis (`REDIS_*`), MQ (`RABBITMQ_*`), S3/minio (`AWS_*`, `MINIO_*`, `AWS_S3_ENDPOINT_URL`), app (`WEB_URL`, `SECRET_KEY`, `CORS_ALLOWED_ORIGINS`, `API_BASE_URL`, etc.)
- **Networks:** `local`, `proxy` (for the bundled proxy)
- **Observed failures:**
  - `api/worker/beat`: **cannot resolve** DB host → `Name does not resolve` (likely `plane-db` not running/attached or network mismatch).
  - `live`: **missing build artifact** `live/dist/server.js` in image (tag/build issue).
- **Ingress:** `${APP_BASE_URL_}` (TLS) via plane `proxy` service.

### Spliit
- **Images:** local `spliit-app` build, `postgres:16`
- **Ports:** app behind Traefik (service `3000`), **DB exposed on host 0.0.0.0:5432** (flagged)
- **Volumes:** `spliit-db:/var/lib/postgresql/data`
- **Env (names):** from `.env` for both app & DB
- **Networks:** `proxy`, `local`, `homepage-net`
- **Health:** DB healthcheck `pg_isready` OK

### Jellyfin & Servarr suite (**stopped**)
- **Images (planned):** `jellyfin/jellyfin`, `linuxserver/*` (qbittorrent, jackett, prowlarr, sonarr, radarr, readarr), `flaresolverr`
- **Ports (when running):** various host ports (e.g., 8078, 6881/tcp+udp, 9117, 9696, 8989, 7878, 8787)
- **Volumes:** `jellyfin-config`, `jellyfin-cache`, `media-lib` (UID/GID 1002), plus per-app configs
- **Ingress:** Jellyseerr is still configured via Traefik; Jellyfin route exists in compose but service is stopped.
- **Note:** Router currently forwards **6881** for qBittorrent — this can be **closed** while the stack is stopped.

### Others
- **Apprise:** `caronc/apprise:latest`, `8005→8000`, network `apprise`
- **Netdata:** `netdata:stable`, host net/pid; alerts to Telegram
- **Scrutiny:** `7534→8080`, `7535→8086`, SMART via `/dev/sd*`
- **MySpeed:** `4674→5216`
- **Stirling-PDF:** Traefik ingress on `${PDF_DOMAIN}`
- **Silverbullet:** Traefik ingress on `${SILVERBULLET_DOMAIN}`, middleware with Authelia
- **OpenWebUI:** `${GPT_DOMAIN}` via Traefik; local `ollama` sidecar on `local` network

---

## 7.3 Exposed services & ingress routes (`*.simoserver.it` via Traefik)

| Domain (env)                | Router / Target Port | Middleware | Notes |
|----------------------------|----------------------|------------|-------|
| `${AUTH_DOMAIN}`           | `authelia` → 9091    | —          | OIDC/SSO issuer |
| `${TRAEFIK_DOMAIN}`        | `traefik` → api@internal | **Authelia** | 2FA protected |
| `${PUBLIC_HOMEPAGE_DOMAIN}`| `homepage` → 7575    | —          | Homarr |
| `${IMMICH_DOMAIN}`         | `media-immich-api` → 2283 | —    | Immich API |
| `${PAPERLESS_DOMAIN}`      | `paperless` → 8000   | —          | Paperless-ngx |
| `${KAVITA_DOMAIN}`         | `kavita` → 5000      | —          | Kavita |
| `${PDF_DOMAIN}`            | `pdf` → 8080         | —          | Stirling-PDF |
| `${SPLIIT_DOMAIN}`         | `spliit-app` → 3000  | **Authelia** | One-factor per ACL |
| `${SILVERBULLET_DOMAIN}`   | `silverbullet` → 3000 | **Authelia** (middleware) | App itself lacks native SSO |
| `${MEALIE_DOMAIN}`         | `mealie` → 9000      | **Authelia OIDC** | Unhealthy (DB schema) |
| `${HOARDER_DOMAIN}`        | `hoarder-web` → 3000 | **Authelia OIDC** |  |
| `${OCIS_DOMAIN}`           | `ocis` → 9200        | —          | oCIS |
| `${GPT_DOMAIN}`            | `gpt` → 8080         | **Authelia OIDC** | OpenWebUI |
| `${JELLYSEERR_DOMAIN}`     | `jellyseerr` → 5055  | —          | Running |
| `${JELLYFIN_DOMAIN}`       | `jellyfin` → 8096    | (route exists) | **Service stopped** |

> **TLS:** All above use `entryPoints=websecure` with `tls.certresolver=leresolver`. HTTP (`:80`) is redirected → HTTPS.

**Host-published (LAN) services (not via Traefik):**
`9445/tcp` Portainer, `7534/7535` Scrutiny, `4674` MySpeed, `3000` Homepage, `7575` Homarr, `5000` Kavita, `8150` Paperless, `8005` Apprise, `9001` Portainer agent.
**Internet NAT** (router): `80`, `443`, `29902` (SSH), `6881/tcp+udp` (qBittorrent) — **recommend closing 6881** while the torrent stack is stopped.

---

## 7.4 Dependencies (databases, caches, storage)

- **Authelia:** file-based users (`users_database.yml`), in-memory sessions; no Redis.
- **Immich:** `immich_postgres` (PostgreSQL 14) + `immich_redis` (Valkey). Media at `immich-upload` (btrfs volume, snapshotted).
- **Paperless:** `paperless_db` (PostgreSQL 15) + `paperless_broker` (Redis). Media/data volumes (`paperless-media`, `paperless-data`).
- **Mealie:** local `postgres:15` service (`mealie-pgdata`).
- **Hoarder:** `hoarder-meilisearch` + headless `hoarder-chrome`; single data volume `hoarder-data`.
- **OCIS:** self-contained; config/data volumes (`ocis-config`, `ocis-data`); optional Collabora.
- **Plane:** `plane-db` (PostgreSQL), `plane-redis` (Valkey), `plane-mq` (RabbitMQ), optional `plane-minio` (S3); multiple log volumes.
- **Spliit:** `spliit-db` (PostgreSQL 16); **DB currently exposed on host:5432 (review)**.
- **Media pipeline (stopped):** various services all binding into `media-lib` volume (UID/GID 1002 `torrents`).
- **Infrastructure/Monitoring:** Traefik (certs volume), Portainer(+agent), Netdata (host mounts), Scrutiny (binds `/dev/sd*`), Watchtower, Apprise.

---

### Flagged issues & quick remediation pointers

- **Plane (multiple containers restarting):**
  - Ensure the `plane-db` service is **running** and on the same **`local`** network as `api/worker/beat`; verify `PGHOST=plane-db` resolves (`docker exec ... getent hosts plane-db`).
  - Recreate or start the bundled DB/Redis/RabbitMQ if you intended to use the in-stack services.
  - **live** image/tag likely missing build artifacts → use an official tag that contains `live/dist/*` or rebuild with the expected build step.

- **Mealie (unhealthy; missing tables):**
  - Confirm it’s pointed to the intended Postgres (`POSTGRES_SERVER=postgres`) and that the DB is empty/fresh.
  - Trigger/verify DB migrations for Mealie (clean start often performs migrations automatically); if the DB was partially initialized, consider wiping the `mealie` schema or running the app’s migration entrypoint for your version.

- **Security hygiene:**
  - **Close router port 6881 (tcp/udp)** while qBittorrent is stopped.
  - **Review `spliit-db-1` exposure (5432)** — unless you explicitly require external access, remove the host bind.



# 9. **Reverse Proxy & Certificates (Deep Dive)**
**Point-in-time:** 2025-08-16T18:58:39+02:00 (Europe/Rome)

### 9.1 Traefik entrypoints, routers, middlewares
**Entrypoints**
- `web` → `:80` (enabled)
  Redirects all HTTP to HTTPS via entrypoint redirection.
- `websecure` → `:443` (enabled)
  Primary TLS entrypoint. **HTTP/3/QUIC:** not enabled.
- Forwarded headers / ProxyProtocol: **not in use** (trust lists commented out).

**Routers (examples as deployed)**
- `traefik` (dashboard) → `Host(\`${TRAEFIK_DOMAIN}\`)`, entrypoint `websecure`, TLS via `leresolver`, **middleware:** `authelia@docker`.
- Service routers (selected):
  `mealie`, `paperless`, `kavita`, `immich`, `hoarder`, `spliit-app`, `silverbullet`, `gpt`, `ocis`, `jellyseerr`, `homepage` — all match on `Host(\`<app>.simoserver.it\`)`, terminate TLS on `websecure` via `leresolver`.

**Middlewares**
- Global redirect: `redirect-to-https` (HTTP→HTTPS).
- Forward-auth: `authelia@docker` attached to:
  - Traefik dashboard (`traefik.simoserver.it`) – **2FA for admins**.
  - Spliit (`split.simoserver.it`) – **SSO** (Authelia).
  - Silverbullet (`silverbullet.simoserver.it`) – **SSO** (Authelia).
- No global security-headers/rate-limit/compression middlewares defined. *(Flagged for hardening; see §9.3.)*

**Networking / bindings**
- Published on host: `0.0.0.0:80`, `0.0.0.0:443` (and IPv6 listeners). Docker reports `docker-proxy` on both ports.
- Traefik joins networks: `proxy` (ingress) and `homepage-net` (for homepage widget).

---

### 9.2 ACME resolvers & challenge types
**Resolver**
- Name: `leresolver`
- Email: `${EMAIL}`

**Storage**
- In-container path: `/certs/acme.json`
- **Backed by Docker named volume:** `traefik_certs` → `/var/lib/docker/volumes/traefik_certs/_data`

**Challenges**
- **TLS-ALPN-01:** **enabled** (primary).
- **HTTP-01:** **disabled** (no httpChallenge configured).
- **DNS-01:** **disabled**.

**IPv6**
- No AAAA DNS records published; ACME over IPv6 is **not** used.

**Backup stance for `acme.json`**
- **Not backed up by design.** Rationale: Traefik will automatically re-issue certificates via Let’s Encrypt if `:80/:443` are reachable and DNS is correct. *(Note: mass re-issuance can hit LE rate limits; optional low-priority backup of `traefik_certs` volume can mitigate.)*

---

### 9.3 Access/error logging & security headers
**Access logging (current)**
- Enabled: `--accesslog=true`
- Path: `/var/log/access.log` → host bind `./logs/access.log`
- Filter: `--accessLog.filters.statusCodes=400-499` (client errors only)
- Format: default (CLF).
- **Rotation:** No host logrotate configured for `./logs`; file can grow until manually rotated. (Docker’s `local` log rotation **does not** apply to this file.)

**Traefik service log**
- `--log.level=INFO` to stdout/stderr; Docker `local` logging driver with `max-size=10m`, `max-file=10` on the container (so Traefik’s **service** logs rotate).

**Security headers (current)**
- **None** globally. Per-router header middlewares are **not** attached (Jellyfin examples are commented out).

**Review flags & recommended hardening**
- **[Action] Include 5xx in access log filter** (helps incident triage):
  Change to `--accessLog.filters.statusCodes=400-599`.
- **[Action] Add log rotation for access log file** (`./logs/access.log`):
  Add a host `logrotate` rule (e.g., daily, `size 50M`, `rotate 14`, `copytruncate`).
- **[Action] Enforce modern TLS profile & SNI strictness:** *(requires enabling file provider)*
  Add static flag & mount for dynamic config, then define:
```yaml
# traefik command (add):
- "--providers.file.directory=/etc/traefik/dynamic"
- "--providers.file.watch=true"
# volumes (add):
- ./dynamic:/etc/traefik/dynamic:ro
```

`./dynamic/tls.yaml`:

```yaml
tls:
  options:
    modern:
      minVersion: VersionTLS12
      sniStrict: true
      curvePreferences:
        - CurveP256
        - CurveP384
      cipherSuites:
        - TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
```

Then on routers (via labels) set `traefik.http.routers.<name>.tls.options=modern@file`.

* **\[Action] Add global security headers middleware:** *(also via file provider)*
  `./dynamic/headers.yaml`:

  ```yaml
  http:
    middlewares:
      secure-headers:
        headers:
          stsSeconds: 31536000
          stsIncludeSubdomains: true
          stsPreload: true
          forceSTSHeader: true
          frameDeny: true
          contentTypeNosniff: true
          browserXssFilter: true
          referrerPolicy: "no-referrer"
          permissionsPolicy: >-
            camera=(), microphone=(), geolocation=(), payment=()
  ```

  Attach on each router: `traefik.http.routers.<name>.middlewares=secure-headers@file[,authelia@docker]`.
* **\[Optional] Enable HTTP/3 (QUIC)** on `websecure` for better latency on modern clients:

  ```
  - "--entrypoints.websecure.http3"
  ```

  *(Leave disabled if you prefer to keep the surface minimal.)*
* **\[Note] Forwarded header trust lists** remain off (no CDN/LB in front). If you add one later, configure `entryPoints.*.forwardedHeaders.trustedIPs` accordingly.

# 10. **Notifications & Webhooks**
**As of:** 2025-08-16T18:58:39+02:00 (Europe/Rome)

## 10.1 **Apprise topics/targets in use**
- **Transports:** Telegram only (two chats).
  - **admin** → administrators’ Telegram chat.
  - **users** (implicit; used historically by Jellyfin + power events) → general user Telegram chat.
- **Where configured:**
  - **Apprise container**: mounted `./apprise_config/` (Telegram targets defined here).
  - **Fail2ban**: custom action `apprise.conf` (host) used by jails to send ban/unban to Apprise.
- **Endpoint exposure:** Apprise HTTP API on **:8005** (LAN-only by design; not forwarded on the router).

## 10.2 **Other app-specific notifications / webhooks**
- **btrfs2cloud** (backup script): posts to Apprise REST (`/notify/apprise`) with tag **admin** (start/finish + cleanup details).
- **Fail2ban**: uses **custom action.d → Apprise** to Telegram (ban/unban events).
- **Power events**: **startup** and **poweroff** scripts send to Apprise (users channel).
- **Netdata**: native **Telegram** via `health_alarm_notify` (no Apprise intermediary).
- **Watchtower**: native **Telegram** via `WATCHTOWER_NOTIFICATION_URL`.
- **Jellyfin**: had a **direct Telegram/webhook** to users channel (stack now being decommissioned).
- **Paperless / Immich / OCIS / Traefik**: **no** direct notifications configured.
- **Authelia (SMTP)**: email notifications enabled (Gmail SMTP).
  - `address: submission://smtp.gmail.com:587`
  - `username: simoserver.it@gmail.com`
  - `password: **** REDACTED ****`
  - `sender: simoserver.it@gmail.com`
  - TLS `server_name: smtp.gmail.com`, `skip_verify: false`

## 10.3 **Telegram channel routing**
- **Netdata** → **admin** chat (alerts).
- **Watchtower** → **admin** chat (update reports & summaries).
- **Fail2ban** → **admin** chat (ban/unban).
- **btrfs2cloud** → **admin** chat (backup start/done).
- **Power events** (startup/shutdown) → **users** chat.
- **Jellyfin** (legacy) → **users** chat.

**Notes & recommendations**
- **Noise control:** no global throttling/rate-limit rules today; consider enabling selective severities (e.g., Netdata WARN/CRIT only) and Apprise message de-duplication if chatter increases.
- **Security:** keep Apprise’s **:8005** HTTP strictly LAN-only; optional: add a small **fail2ban** jail for its access log or a simple Traefik-forward-auth if ever exposed.

# 13. **OCIS (ownCloud Infinite Scale)**

**Status @ 2025-08-16 18:58:39+02:00**
- Public FQDN: **ocis.simoserver.it** (via Traefik).
- Containers: `ocis` (core), `collaboration` (WOPI driver), `collabora` (office), `tika` (full-text).
- Health: `collabora` **healthy**; others **up** (no healthcheck).
- Watchtower: `monitor-only` labels set (no auto-updates).

### 13.1 Production setup overview
- **Ingress & exposure**
  - Traefik router: `Host(ocis.simoserver.it)` → service port **9200**.
  - TLS terminated at Traefik (Let’s Encrypt **TLS-ALPN-01**). Backend leg plain HTTP (**PROXY_TLS=false**).
- **Editors / WOPI**
  - **Collabora Online** enabled with dedicated services:
    - Collaboration service (`ocis collaboration server`) published at **ocis-wopiserver.simoserver.it**.
    - Collabora frontend at **ocis-collabora.simoserver.it**.
  - MIME routing via `app-registry.yaml` (ODF → Collabora; OOXML/PDF → OnlyOffice entries present but OnlyOffice **not deployed**).
- **Search / Content extraction**
  - **Apache Tika** enabled; OCIS points to `http://tika:9998`; full-text search toggled on.
- **Web extensions**
  - Enabled volumes & initializers for: **unzip**, **draw.io**, **json-viewer**, **progress-bars**, **external-sites** (served from `ocis-apps` volume).
- **Notifications**
  - OCIS `notifications` service enabled; SMTP configured (Gmail). See 13.2.

### 13.2 Storage, identity, and TLS integration
- **Storage**
  - Primary backend: **local filesystem** (no S3NG).
  - Named volumes: **`ocis-config`** (config) and **`ocis-data`** (user/content data).
  - Backups: covered by **btrfs2cloud** timers (crash-consistent Btrfs snapshots; offsite via rclone/encrypted).
- **Identity / auth**
  - **Internal IDM** (default). `IDM_CREATE_DEMO_USERS` **disabled** (no demo users).
  - **Basic auth for WebDAV**: **disabled** (`PROXY_ENABLE_BASIC_AUTH=false`).
  - **Email**: SMTP via Gmail (`smtp.gmail.com:587`, sender `simoserver.it@gmail.com`) for OCIS notifications.
- **TLS & security headers**
  - TLS handled by Traefik; certificates stored in `traefik_certs` volume (regenerated if lost).
  - Custom **CSP** at `config/ocis/csp.yaml`:
    - `default-src 'none'`; `frame-ancestors 'self'`; `frame-src` allows Collabora & OnlyOffice FQDNs and draw.io; `connect-src` permits Companion (if used) and GitHub raw; `img-src` allows data/blob and office FQDNs; `script-src/style-src 'self' 'unsafe-inline'`.
  - Forwarded headers / PROXY protocol: **not used** (see Section 9).

---

#### Notes & small TODOs
- **Logging for F2B:** OCIS currently logs to Docker **local** driver only; if a Fail2ban jail is desired, also emit to a file or journald with a stable identifier and add a filter.
- **OnlyOffice entries in app-registry:** Present for convenience, but **service not deployed**; keep Collabora as sole editor to avoid lock/interop issues.
- **Hardening (optional):** consider Traefik `tls.options` (min TLS 1.2+, modern ciphers, SNI strict) and adding HTTP security headers middleware; HTTP/3 is **not** enabled by design.

# 14. Access Patterns & Users

## 14.1 Usage profile (<10 users, internet-facing)
- **Audience/roles:** ~6–10 users total, **1 admin**.
- **Auth mix today:** many services behind **Authelia SSO**, but **some apps still use local accounts** → **migration to SSO is pending**.
- **2FA:** **not universally enforced**; varies by service.
- **Public/anonymous features in use:**
  - **OCIS** public shares enabled.
  - **Immich** public shares enabled.
- **Where users come from / devices:**
  - **Desktop:** Paperless-ngx, OCIS.
  - **Mobile:** Immich, Hoarder (Karakeep).
- **Exposure model:**
  - Most apps **internet-facing via Traefik** on `*.simoserver.it` with HTTPS.
  - **Portainer (9445)** is **LAN-only** (no WAN forward).
  - No VPN requirement; SSO is considered sufficient today.
- **Traffic pattern:** no clear peak; usage evenly spread.

## 14.2 Rate limits / protections (current state)
- **Reverse proxy (Traefik):**
  - **No rate-limit middleware** configured (defaults only).
  - Global redirect HTTP→HTTPS; access log captures **4xx** (not 5xx).
  - ForwardedHeaders / ProxyProtocol **not in use**.
- **Authelia regulation (anti-bruteforce):**
  - `max_retries=3`, `find_time=10m`, `ban_time=12h`.
  - 2FA present but **inconsistently required** (service-dependent).
- **Fail2ban jails (common policy):**
  - Jails: `sshd`, `authelia`, `immich`, `paperless`, `jellyfin`, `jellyseerr`, `traefik`.
  - Policy (each): `maxretry=3`, `findtime=3600s`, `bantime=3600s` (1h).
- **Network hardening:**
  - **No IP allow-lists** at Traefik/firewall layer.
  - **IPv6** not in use on ingress.
  - Note: **`spliit-db-1` exposes Postgres on host :5432** → **flagged for review** (see §7.2).

### Gaps & to-dos (recommended)
1. **Unify auth**: migrate remaining local accounts to **Authelia**; enable OIDC where supported (Immich, Paperless, etc.).
2. **Enforce 2FA**: at least for **admin** accounts globally; ideally for all users.
3. **Add rate-limits** in Traefik for public routers (e.g., 20 rps burst 40) and for auth endpoints (tighter).
4. **Harden admin surfaces**: consider IP allow-list (home/work) for Traefik dashboard and other sensitive routes.
5. **Align ban times**: consider increasing Fail2ban `bantime` to match **Authelia’s 12h** for consistency.
6. **Review public sharing defaults** (OCIS/Immich) and document intended policy (expiry, password, audience).
7. **Close direct DB exposure**: remove host-level `:5432` for Spliit unless required, or firewall it narrowly.


# 15. **Security & Hardening**

### 15.1 Host hardening summary
- **Base OS:** Arch Linux (kernel 6.15.3), headless. Time sync via `systemd-timesyncd` (active).
- **Firewall (UFW):** Default **deny (incoming)** / allow (outgoing). Explicit rules include:
  - `443/tcp` (**LIMIT IN**), custom SSH `29902/tcp` (**ALLOW IN**), plus 32400, 14014/tcp+udp, 9090/tcp, 5012, 35643. One explicit **DENY** for `3.85.226.144`. v6 rules mirror many v4 allows.
  - Note: `LIMIT` on 443 throttles clients and can degrade UX; usually reserve `limit` for SSH.
- **SSH:** Port **29902**, **Pubkey-only** (`PasswordAuthentication no`, `AuthenticationMethods publickey`). `UsePAM no` in main config, but `UsePAM yes` is set in an included drop-in; main file wins (effective **no**). `KbdInteractiveAuthentication no`. **X11Forwarding yes** (server use-case: should be **no**).
- **Sudo:** Admin via `wheel`; no global `NOPASSWD`. Exception: dedicated **`poweroff`** user can run `systemctl start safe-poweroff` without password.
- **Disk / FS:** No LUKS/full-disk encryption. Btrfs for system and data.
- **Backups:** `btrfs send | zstd | openssl aes-256 -pbkdf2 | rclone` (encrypted at rest in cloud; password supplied via env at runtime).
- **Docker:** Rootful engine, **cgroups v2**, no `daemon.json` hardening (no userns-remap, no live-restore, no default-ulimits). Several services mount the **Docker socket**:
  - **RW:** portainer, watchtower
  - **RO:** traefik, netdata, homepage
  Netdata uses **AppArmor unconfined**; otherwise no seccomp/AppArmor overrides. No auditd rules tuned.
- **Ingress (Traefik):** Public 80/443; Let’s Encrypt; no HTTP/3; forwarded headers/proxy protocol not used. No Traefik rate-limit middlewares. IPv6 **allowed in UFW** and Docker, but there are **no AAAA records** published (service may still be reachable by raw v6 IP).

---

### 15.2 Secrets at rest — locations & permissions (UID 1000)
- **`.env` files (per stack)** — examples under `*/.env`:
  - Current perms are mostly **`0644`** (world-readable). **Action:** set to **`0600`** and keep owner `simone:simone` (UID 1000).
  - Suggested one-liner to fix across the repo (run at repo root):
    ```bash
    find . -mindepth 2 -maxdepth 2 -name '.env' -exec chown 1000:1000 {} \; -exec chmod 600 {} \;
    ```
- **Authelia secrets** — `authelia/secrets/`:
  - Core secrets (`jwt`, `session`, `storage_password`, `storage_encryption_key`) are **`0600`** ✅.
  - `authelia_smtp_password` and `google_clientid` are **`0644`**; tighten to **`0600`** (even if not highly sensitive).
  - Move any plaintext credentials from `config/configuration.yml` into secrets/env files where supported.
- **Other secrets**:
  - **OIDC client secrets, Telegram tokens**: currently in various `.env` files → secure via **`0600`** or promote to **Docker secrets** where possible.
  - **Backup encryption passphrase**: avoid exporting directly in the shell; store in a **root-readable file** (e.g., `/root/.secrets/btrfs2cloud-pass` with `600`) and source via a systemd `EnvironmentFile=` for the timer/service.

---

### 15.3 Recommendations & quick wins (impact vs effort)

> Legend — **Impact:** 🟥 high / 🟧 medium / 🟨 low. **Effort:** ⬇ low / ⬆ medium / ⬆⬆ high.
> Notes include **warnings & consequences** where applicable.

**Immediate (low effort, high value)**
1) **Fix world-readable secrets** (all `*/.env`, Authelia SMTP/Google files) — **Impact 🟥 / Effort ⬇**
   ```bash
   find . -mindepth 2 -maxdepth 2 -name '.env' -exec chmod 600 {} \;
   chmod 600 authelia/secrets/authelia_smtp_password authelia/secrets/google_clientid
   ```
   *Consequence of not doing it:* local users on the host can read credentials.

2) **UFW rules hygiene** — **Impact 🟥 / Effort ⬇**
   - Change **443** rule from `LIMIT` → `ALLOW`:
     ```bash
     sudo ufw delete limit 443/tcp
     sudo ufw allow 443/tcp
     ```
   - Apply `limit` to **SSH port 29902** instead:
     ```bash
     sudo ufw limit 29902/tcp
     ```
   - Review/close unused exposes (e.g., **32400**, **14014**, **5012**, **35643**, **9090**) if not needed on WAN:
     ```bash
     # Example: restrict to LAN
     sudo ufw delete allow 32400
     sudo ufw allow from 192.168.0.0/16 to any port 32400 proto tcp
     ```

3) **Disable X11 over SSH** — **Impact 🟧 / Effort ⬇**
   - Set `X11Forwarding no` in sshd and restart: `sudo systemctl restart sshd`.

4) **Traefik log rotation** (access log is used by Fail2ban) — **Impact 🟧 / Effort ⬇**
   - Add `/etc/logrotate.d/traefik`:
     ```
     /path/to/traefik/logs/*.log {
       daily
       rotate 14
       compress
       delaycompress
       missingok
       notifempty
       copytruncate
     }
     ```
   - Keep **copytruncate** to avoid breaking Fail2ban file handles.

5) **Fail2ban coverage sanity** — **Impact 🟧 / Effort ⬇**
   - You already jail **authelia/immich/jellyfin/jellyseerr/paperless/sshd/traefik** at `maxretry=3`/`bantime=3600`. Consider **longer bantime (e.g., 12h)** for Authelia/Traefik if brute-force noise is observed:
     ```bash
     bantime = 12h
     ```

**Short-term (medium effort)**
6) **IPv6 stance** — **Impact 🟥 / Effort ⬆**
   - If you **don’t want IPv6 exposure**, remove v6 allows (you already have several `ALLOW IN (v6)`), or set `IPV6=no` in `/etc/default/ufw` and re-apply rules.
   - *Consequence:* if left open, services can still be reachable via raw IPv6 address even without AAAA DNS.

7) **Harden SSH banners & PAM consistency** — **Impact 🟧 / Effort ⬆**
   - Make `UsePAM` consistent (currently `no` overrides a drop-in that says `yes`). Choose one model:
     - **Keys-only, no PAM** (simpler): keep `UsePAM no`.
     - **Keys + PAM** (for MFA/U2F): set `UsePAM yes` and integrate MFA (see next item).
   - Add `LoginGraceTime 30` and `MaxAuthTries 3`.

8) **SSO & app auth alignment** — **Impact 🟥 / Effort ⬆**
   - Migrate remaining local accounts (Immich, Paperless, etc.) to **Authelia SSO** to centralize policy and MFA.
   - *Consequence:* short downtime and user re-onboarding; pays off with unified 2FA and fewer brute-force surfaces.

9) **Traefik TLS/security headers & rate limits** — **Impact 🟥 / Effort ⬆**
   - Add a **global TLS options** block (TLS 1.2+, modern ciphers, `sniStrict=true`) and an **HSTS**/security-headers middleware applied to public routers.
   - Add **rate-limit** middleware on Authelia and API-heavy routes (keeps Fail2ban effective; just avoid over-throttling).
   - *Consequence:* older clients may fail TLS handshakes if you drop legacy ciphers.

**Medium-term (higher effort / change management)**
10) **Reduce Docker socket exposure** — **Impact 🟥 / Effort ⬆⬆**
    - Keep **Portainer (rw)** if required; ensure auth + LAN-only.
    - **Watchtower:** consider **monitor-only** or image-pinning with manual upgrades; if you keep it, it needs rw socket.
    - **Traefik:** keep **RO** (already ro).
    - **Homepage/Netdata:** RO is acceptable, or drop the mount and use Docker labels/Prometheus endpoints instead.
    - *Consequence:* removing mounts may break features; plan per-service replacements.

11) **Docker engine hardening (`/etc/docker/daemon.json`)** — **Impact 🟧 / Effort ⬆**
    - Suggested baseline:
      ```json
      {
        "live-restore": true,
        "icc": false,
        "log-driver": "local",
        "default-ulimits": {
          "nofile": {"Name": "nofile", "Hard": 1048576, "Soft": 1048576}
        }
      }
      ```
    - Consider `"userns-remap": "default"` **only** if volumes/permissions are audited first.
    - *Consequence:* enabling user namespaces/rootless can break bind-mounted permissions and some images.

12) **Server kernel/channel** — **Impact 🟧 / Effort ⬆**
    - For a home server, consider **`linux-lts`** for stability vs. Arch’s fast-moving mainline.
    - *Consequence:* occasional module/driver differences; usually safer for long uptimes.

13) **System updates & reboot policy** — **Impact 🟧 / Effort ⬆**
    - Define a **patch window** (e.g., monthly) with snapshot + reboot.
    - Arch doesn’t favor unattended upgrades on servers; use **manual** `pacman -Syu` with Btrfs snapshot rollback plan.

14) **Host auditing** — **Impact 🟧 / Effort ⬆**
    - Enable **persistent journald**, and consider minimal **auditd** rules for auth, sudo, and Docker daemon actions.

**Nice-to-haves**
15) **SSH MFA (WebAuthn/U2F or TOTP)** — **Impact 🟧 / Effort ⬆**
    - If you flip to `UsePAM yes`, add **pam_u2f** or **pam_google_authenticator** for the admin account.
    - *Consequence:* recovery keys/devices and break-glass procedure required.

---

#### Notes & constraints
- **SSH port** stays at **29902** per preference.
- **userns-remap/rootless:** flagged as **breaking risk** for mounted volumes and some images; apply only after a permissions audit and with rollback plan.
- **Fail2ban & logs:** ensure Traefik keeps **CLF format** and access logs include **4xx+5xx** so jails work as intended.
