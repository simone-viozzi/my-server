```
# [security] Lock down plaintext secrets and move to Docker secrets
---
Many `.env` files are world-readable and sensitive values are in environment vars. This exposes credentials to any local user/process and risks leaking via logs or backups. Use file-based Docker secrets for high-sensitivity values and restrict file permissions.

## why this is needed
- World-readable `.env` files violate basic secret hygiene.
- Env vars are easy to exfiltrate and often end up in logs.
- Reduces blast radius and enables safer rotation/backup practices.

## what's needs to be done
- `find . -mindepth 2 -maxdepth 2 -name '.env' -exec chmod 600 {} \; && chown 1000:1000 {} \;`
- For Authelia/SSO/Telegram/DB credentials: create Docker **secrets**; replace `*_SECRET` with `*_SECRET_FILE` where supported.
- Remove secrets from images and git; keep secrets in `/run/secrets` or mounted secret files.
- Document a rotation cadence and owners; remove dead secrets.

## how to confirm the remediation was successful
- `find . -mindepth 2 -maxdepth 2 -name '.env' -exec stat -c '%a %U:%G %n' {} \;` → all `600 simone:simone`.
- `docker compose config` shows `secrets:` sections and `*_FILE` envs.
- `strings /proc/$(pidof <svc>)/environ | grep -Ei '(token|secret|password)'` returns nothing sensitive.

# Tags
- #security
- #secrets
- #docker
```

```
# [networking] Fix UFW policy: allow 443, limit SSH 29902, audit WAN exposes
---
Port 443 is rate-limited and several historical ports are still open. Reserve `limit` for SSH; 443 should be ALLOW. Close stale forwards and restrict LAN-only services with UFW “from LAN”.

## why this is needed
- `limit` on 443 throttles legit clients and harms UX.
- Unneeded open ports increase scan/attack surface.
- Consistent firewall policy reduces surprises.

## what's needs to be done
- `sudo ufw delete limit 443/tcp && sudo ufw allow 443/tcp`
- `sudo ufw limit 29902/tcp` (SSH)
- Close unused ports (e.g., 32400, 14014, 5012, 35643) or restrict to LAN: `sudo ufw allow from 192.168.0.0/16 to any port <PORT> proto tcp`
- Review router/NAT forwards and remove obsolete ones.

## how to confirm the remediation was successful
- `sudo ufw status numbered` shows 443 ALLOW, 29902 LIMIT, other ports LAN-scoped or closed.
- `curl -sI https://<domain>` is fast; repeated hits aren’t throttled.
- Port scans from outside show only 80/443 (and SSH if intentionally open).

# Tags
- #networking
- #ufw
- #security
```

```
# [networking] Close qBittorrent 6881/tcp+udp and any media pipeline forwards
---
Torrent stack is stopped but 6881/tcp+udp remains forwarded. Remove WAN exposes until the stack is back and intentionally required.

## why this is needed
- Idle open ports invite scanning and abuse.
- Reduces noise for Fail2ban and Netdata alerts.
- Principle of least exposure.

## what's needs to be done
- Remove router/NAT rules for `6881/tcp` and `6881/udp`.
- Ensure compose files don’t publish 6881 on host while stopped.
- Optionally add UFW rules to explicitly deny these ports.

## how to confirm the remediation was successful
- From an external host: `nc -zv <public-ip> 6881` and `nmap -sU -p 6881 <public-ip>` → closed/filtered.
- `sudo ss -lntup | grep 6881` on server → no listeners.

# Tags
- #networking
- #security
```

```
# [database] Remove direct Postgres exposure (spliit-db on :5432)
---
`spliit-db-1` binds Postgres to `0.0.0.0:5432`. This should not be internet-facing and usually not host-wide either. Route access via the app network or restrict strictly.

## why this is needed
- Direct DB exposure is a high-severity risk.
- Postgres is a frequent target for credential stuffing and exploits.
- Network segmentation is standard SOTA.

## what's needs to be done
- Remove `ports: - "5432:5432"` from the DB service; rely on Docker network.
- If host access is required, bind to `127.0.0.1:5432` and firewall to localhost only.
- Rotate DB password; audit pg_hba.conf if customized.

## how to confirm the remediation was successful
- `sudo ss -ltnp | grep ':5432'` shows `127.0.0.1` or no host binding.
- External `nc -zv <public-ip> 5432` → closed.
- App still connects successfully over internal Docker network.

# Tags
- #database
- #security
- #networking
```

```
# [reverse-proxy] Add global security headers via Traefik middleware
---
There is no global security-headers middleware. Add HSTS, X-Content-Type-Options, frame protection, referrer and permissions policies; attach to public routers.

## why this is needed
- OWASP baseline hardening is missing.
- HSTS enforces HTTPS and helps prevent downgrade.
- Consistent headers reduce app-by-app drift.

## what's needs to be done
- Enable file provider: mount `./dynamic` and add `--providers.file.directory=/etc/traefik/dynamic`.
- Create `headers.yaml` with HSTS, frame deny, content-type nosniff, referrer, permissions-policy.
- Attach `secure-headers@file` to all public routers (mind compose label syntax).

## how to confirm the remediation was successful
- `curl -sI https://<domain> | grep -Ei 'strict-transport-security|x-content-type-options|referrer-policy|permissions-policy'`
- Spot-check multiple services; all return the headers.

# Tags
- #traefik
- #security
```

```
# [tls] Enforce modern TLS profile & SNI strictness
---
TLS runs fine but no explicit `tls.options` are defined. Add a modern profile (TLS ≥1.2, curated cipher suites) and set `sniStrict=true` on Traefik.

## why this is needed
- Reduces downgrade/legacy handshake risks.
- Hardens against weak ciphers and mis-SNI traffic.
- Consistent posture across services.

## what's needs to be done
- Add `dynamic/tls.yaml` with `tls.options.modern` (minVersion TLS1.2, cipher suites).
- Set router label `traefik.http.routers.<name>.tls.options=modern@file`.
- Optionally enable HTTP/3 once stable in your client fleet.

## how to confirm the remediation was successful
- `openssl s_client -connect <domain>:443 -tls1_0` → fails; `-tls1_2` → succeeds.
- `curl --http3 -I https://<domain>` works if HTTP/3 enabled.

# Tags
- #tls
- #traefik
- #security
```

```
# [reverse-proxy] Fix HTTP→HTTPS UX: open 80/tcp or go HSTS-only
---
HTTP is redirected in Traefik but UFW blocks 80/tcp, so users never see the redirect. Decide policy: open 80 for redirects, or keep 80 closed and preload HSTS.

## why this is needed
- Current state causes confusing failures on `http://`.
- Clear policy improves user experience and onboarding.
- HSTS-only is valid, but must be explicit and consistent.

## what's needs to be done
- Option A: `sudo ufw allow 80/tcp` and keep Traefik redirect.
- Option B: keep 80 closed, enable strict HSTS (1y, preload), and update domains in HSTS preload list.
- Communicate policy in admin docs.

## how to confirm the remediation was successful
- Option A: `curl -I http://<domain>` → `301` to `https://`.
- Option B: `curl -I https://<domain>` shows long-lived HSTS; `http://` connection is blocked by firewall.

# Tags
- #networking
- #traefik
- #ux
- #needsReview
```

```
# [logging] Rotate Traefik access logs and include 5xx
---
Traefik access logs only capture 4xx and have no host logrotate. Expand to 400–599 and add `/etc/logrotate.d/traefik` to prevent growth and keep Fail2ban effective.

## why this is needed
- 5xx visibility is vital for incident triage.
- Unrotated logs risk disk bloat and broken file handles.
- Consistent evidence trail for Fail2ban and audits.

## what's needs to be done
- Update Traefik flags: `--accesslog=true --accesslog.filters.statusCodes=400-599`.
- Add logrotate with `copytruncate`, daily/size caps, 14 rotates.
- Validate Fail2ban filters still match the log format.

## how to confirm the remediation was successful
- `grep -E ' 5[0-9][0-9] ' /path/to/traefik/logs/access.log` returns hits when inducing a test 500.
- `logrotate -d /etc/logrotate.d/traefik` dry-run shows rotation plan.

# Tags
- #logging
- #traefik
- #fail2ban
```

````
# [rate-limiting] Add Traefik rate-limits on auth/API routes
---
No rate-limit middleware is configured. Add moderate limits (e.g., 20 rps, burst 40) to Authelia and login APIs to reduce brute force/credential stuffing.

## why this is needed
- Reduces load and noise before Fail2ban triggers.
- Minimizes abuse while retaining UX for legitimate users.
- Complements SSO regulation settings.

## what's needs to be done
- Define `middlewares.rate-limit` in dynamic config (average/burst).
- Attach rate-limit to Authelia and app login routers (mind order with forward-auth).
- Monitor for false positives; tune per app if needed.

## how to confirm the remediation was successful
- Rapid curl loop to `/login` returns `429` after burst:
  ```
  for i in {1..200}; do curl -s -o /dev/null -w '%{http_code}\n' https://<domain>/login; done | sort | uniq -c
  ```
- Traefik access log shows 429s; app CPU stays calm.

# Tags
- #traefik
- #security
- #performance
````

```
# [backups] Add application-consistent Postgres backups + PITR
---
Btrfs snapshots are crash-consistent. Add logical dumps or base backups with WAL archiving (PITR) for critical DBs (Immich, Paperless, Mealie, Spliit, Plane).

## why this is needed
- Ensures clean restores across schema changes.
- Enables point-in-time recovery after accidental deletions/ransom/errors.
- Meets higher RPO/RTO targets.

## what's needs to be done
- For each DB: schedule `pg_dump` (daily) into a dedicated volume path included in backups.
- For critical DBs: configure `archive_mode=on`, `archive_command`, periodic `pg_basebackup`, and offsite WAL retention.
- Document/test restore runbooks (stop app → restore dump/base backup → replay WAL).

## how to confirm the remediation was successful
- `psql -c '\dt'` on a test restore shows expected tables.
- PITR test: drop a test row, recover to timestamp before drop; verify row exists.

# Tags
- #backups
- #database
- #reliability
```

```
# [filesystem] Schedule Btrfs scrub & balance maintenance
---
No periodic scrub/balance timers are configured. Add monthly scrubs and ad-hoc balances to detect/repair latent errors.

## why this is needed
- Scrub finds and fixes checksum mismatches early.
- Prevents long-term data rot on spinning disks.
- Industry practice for Btrfs-managed arrays.

## what's needs to be done
- Create systemd timers: `btrfs scrub start -Bd /dev/sda` and `/dev/sdb` monthly.
- Add balance (light) when `btrfs fi usage` shows high metadata/data imbalance.
- Alert via Apprise on failures.

## how to confirm the remediation was successful
- `systemctl list-timers | grep btrfs-scrub` shows active timers.
- `btrfs scrub status /mountpoint` shows recent successful run.

# Tags
- #storage
- #btrfs
- #maintenance
```

```__
# [services] Fix Mealie DB migrations (unhealthy state)
---
Mealie reports `relation "groups" does not exist`. DB schema is missing/partial; migrations must run cleanly.

## why this is needed
- Unhealthy app is unusable and may corrupt further.
- Clean schema ensures feature parity and future upgrades.

## what's needs to be done
- Ensure Mealie points to the intended Postgres service (`POSTGRES_SERVER=postgres` on the same network).
- Reset or run migrations: wipe dev DB if acceptable, or run the app’s migration entrypoint for the current image.
- Pin a known-good Mealie tag matching the DB schema.

## how to confirm the remediation was successful
- `docker logs mealie | grep -i 'migrat'` shows success.
- Healthcheck passes; app UI loads without DB errors.

# Tags
- #application
- #database
- #reliability
```

```
# [services] Recover Plane stack (DB resolution + live image build)
---
Multiple Plane containers are restarting: DB host doesn’t resolve; `live` image missing `dist/server.js`. Fix network, DB service, and image tag/build.

## why this is needed
- Broken stack wastes resources and risks data drift.
- Stabilizing Plane unblocks usage and upgrades.

## what's needs to be done
- Ensure `plane-db` is running and on the same Docker network as `api/worker/beat`.
- Validate `PGHOST=plane-db` name resolution: `docker exec <api> getent hosts plane-db`.
- Use an official tag that includes built `live/dist/*` or rebuild image correctly.

## how to confirm the remediation was successful
- `docker ps --format '{{.Names}}\t{{.Status}}' | grep plane` shows all **healthy**.
- App loads and basic CRUD works.

# Tags
- #application
- #database
- #networking
```

```
# [identity] Enforce SSO everywhere and require 2FA for admins
---
Auth is mixed (SSO and local). Expand Authelia OIDC to Immich, Paperless, etc., and require 2FA for admin (ideally all users).

## why this is needed
- Reduces brute-force surfaces and password reuse risks.
- Centralizes access policies and revocation.
- Improves user experience.

## what's needs to be done
- Enable OIDC in apps supporting it (Immich, Paperless, etc.), disable local login where feasible.
- Apply Authelia policy: default deny, group-based allow, 2FA for admin-protected routes.
- Verify all public routers are behind forward-auth or native OIDC.

## how to confirm the remediation was successful
- Direct access to app routes returns 302 to `auth.simoserver.it`.
- Admin login requires 2FA; Authelia logs show successful policy enforcement.

# Tags
- #sso
- #security
- #identity
```

```
# [fail2ban] Align bantimes and add recidive; ensure 5xx visibility
---
Bantime is 1h while Authelia uses 12h. Increase bantime for key jails, add recidive, and ensure Traefik logs include 5xx so F2B can react.

## why this is needed
- Consistent ban durations improve deterrence.
- Recidive blocks persistent offenders longer.
- 5xx patterns aid abuse detection.

## what's needs to be done
- Set `bantime = 12h` for Authelia/Traefik jails; add `recidive` jail with longer bans.
- Update Traefik access-log filter to `400-599`.
- Test filters against current log format.

## how to confirm the remediation was successful
- `sudo fail2ban-client get traefik bantime` → `43200`.
- Offender triggers `recidive` → `fail2ban-client status recidive` shows banned IP.

# Tags
- #fail2ban
- #security
- #logging
```

```
# [ipv6] Decide and enforce IPv6 ingress policy
---
Docker/Traefik listen on v6 and UFW has v6 rules, but there are no AAAA DNS records. Define whether IPv6 should be reachable and configure consistently.

## why this is needed
- Prevents accidental exposure via raw IPv6.
- Consistency across DNS, firewall, and listeners.
- Simplifies troubleshooting.

## what's needs to be done
- Option A: fully enable v6—add AAAA DNS, mirror UFW rules, monitor.
- Option B: restrict v6—disable or block v6 ingress in UFW; ensure Traefik not externally reachable via v6.
- Document the decision.

## how to confirm the remediation was successful
- `curl -6 -I https://<domain>` either succeeds (if enabled) or fails (if disabled).
- `sudo ufw status` shows matching v6 rules; external scans align with policy.

# Tags
- #ipv6
- #networking
- #needsReview
```

```
# [docker] Reduce Docker socket exposure (especially RW)
---
Traefik (RO), Portainer (RW), Watchtower (RW) mount the Docker socket. RW mounts are a high-value target; minimize consumers and scope.

## why this is needed
- Docker socket RW ≈ root on host.
- Limits lateral movement if one app is compromised.
- Industry guidance is to restrict or broker access.

## what's needs to be done
- Keep Traefik **RO**; ensure no RW mounts outside Portainer (if needed).
- Consider Watchtower **monitor-only** (no RW) or label-based opt-in.
- Use socket-proxy or scoped APIs if continued access is required.

## how to confirm the remediation was successful
- `docker inspect <svc> | jq -r '.[0].HostConfig.Binds'` shows RO or no `/var/run/docker.sock` for non-admin apps.
- Functional tests for Traefik/Portainer still pass.

# Tags
- #docker
- #security
```

```
# [updates] Switch Watchtower to opt-in or monitor-only; enable cleanup
---
Watchtower updates everything and keeps old images. Convert to label-based opt-in or `--monitor-only` for prod-like stacks, and clean up old layers.

## why this is needed
- Uncontrolled updates can break production unexpectedly.
- Image bloat wastes disk.
- Controlled cadence aligns with change management.

## what's needs to be done
- Add `--label-enable` and label only the stacks you want auto-updated.
- Or use `--monitor-only` + notifications, then update manually.
- Add `--cleanup` to prune old images post-update.

## how to confirm the remediation was successful
- `docker inspect watchtower | jq '.[0].Args'` shows expected flags.
- Only labeled services are updated; image disk usage drops after cycles.

# Tags
- #watchtower
- #operations
- #reliability
```

````
# [docker] Set global logging defaults (driver=local, size caps)
---
Logs rotate in some services but there’s no global cap. Set `daemon.json` defaults to `log-driver: local` with `max-size`/`max-file` and sensible ulimits/live-restore.

## why this is needed
- Prevents disk exhaustion from chatty containers.
- Ensures consistent behavior across stacks.
- Improves resilience during daemon restarts.

## what's needs to be done
- `/etc/docker/daemon.json`:
  ```json
  { "live-restore": true, "icc": false, "log-driver": "local",
    "log-opts": {"max-size": "10m", "max-file": "5"},
    "default-ulimits": {"nofile": {"Name":"nofile","Soft":1048576,"Hard":1048576}} }
  ```
- Restart Docker with maintenance window; verify compatibility.

## how to confirm the remediation was successful
- `docker info | grep -E 'Logging Driver|Live'`
- `docker inspect <svc> | jq -r '.[0].HostConfig.LogConfig'` shows driver=local and opts.

# Tags
- #docker
- #logging
- #hardening
- #needsReview
````

```
# [ssh] Harden SSH: disable X11, align PAM, tune limits
---
SSH has X11 forwarding enabled and conflicting PAM settings. Disable X11, make `UsePAM` explicit, limit auth tries, and ensure UFW limit is applied to SSH.

## why this is needed
- Reduces attack surface and session complexity.
- Consistent auth path avoids surprises.
- Proven CIS-style hardening.

## what's needs to be done
- In `sshd_config`: `X11Forwarding no`, `MaxAuthTries 3`, `LoginGraceTime 30`, confirm `PasswordAuthentication no`.
- Choose `UsePAM yes` (for MFA) or `no` (keys-only) and remove conflicting drop-ins.
- Apply `sudo ufw limit 29902/tcp` and restart SSH.

## how to confirm the remediation was successful
- `sshd -T | grep -E 'x11forwarding|maxauthtries|usepam|passwordauthentication'`
- `ssh -X` fails as expected; auth limits enforced.

# Tags
- #ssh
- #security
```

```
# [reverse-proxy] Fix domain label typos (split vs spliit)
---
There’s an inconsistency between `split` and `spliit` naming. Typos can silently bypass intended middlewares and ACLs.

## why this is needed
- Ensures SSO/rate-limit/headers apply to the right routes.
- Prevents “shadow routes” without protection.
- Improves maintainability.

## what's needs to be done
- Grep compose/labels for both tokens and unify to a single canonical name.
- Update DNS/Traefik/router rules accordingly.
- Redeploy affected stacks.

## how to confirm the remediation was successful
- `grep -RInE 'spliit|split' containers/` returns only the canonical name.
- Visiting the domain shows the expected Authelia/rate-limit headers.

# Tags
- #traefik
- #dns
- #quality
```

```
# [monitoring] Add healthchecks to services lacking them
---
Several containers run without healthchecks. Add simple HTTP/TCP checks so orchestrator and dashboards reflect true state.

## why this is needed
- Enables early detection and auto-restart logic.
- Improves inventory accuracy (healthy/unhealthy).
- Aids Watchtower gating and alerting.

## what's needs to be done
- Add `healthcheck:` per service (curl endpoint or `pg_isready` etc.).
- Choose sensible intervals/timeouts/start-period to avoid flapping.
- Surface health in dashboards (Homepage/Homarr).

## how to confirm the remediation was successful
- `docker inspect <svc> --format '{{json .State.Health}}' | jq`
- Homepage/Homarr shows green checks for healthy services.

# Tags
- #observability
- #reliability
```

```
# [admin-surfaces] Add IP allow-lists for admin routes
---
Traefik dashboard and other sensitive surfaces rely only on SSO/2FA. Add IP allow-lists for admin routes as an extra control.

## why this is needed
- Defense-in-depth against auth bypass/0-days.
- Reduces brute-force/noise against admin surfaces.
- Common best practice for small, stable admin source IPs.

## what's needs to be done
- Create a Traefik IP allow-list middleware with home/work CIDRs.
- Attach to `traefik.simoserver.it` and other admin endpoints (Portainer if ever exposed).
- Keep a break-glass procedure for travel.

## how to confirm the remediation was successful
- From an unauthorized network, `curl -I https://traefik.simoserver.it` → 403.
- From allowed IPs, admin is reachable (still behind SSO/2FA).

# Tags
- #security
- #traefik
```

```
# [operations] Define maintenance window & change management
---
Auto-updates and ad-hoc changes risk downtime. Define a monthly patch window, snapshot plan, and rollback steps.

## why this is needed
- Predictable updates reduce surprise outages.
- Users can be notified; backups and snapshots are fresh.
- Faster, safer rollbacks.

## what's needs to be done
- Establish monthly patch window; pre-snapshot critical datasets.
- Stage updates (dev/test if possible), then prod; keep previous tags for rollback.
- Document checklist: comms, snapshots, update order, smoke tests.

## how to confirm the remediation was successful
- A written runbook exists; last maintenance run has notes and rollback points.
- Snapshots visible for the window; services pass smoke tests post-update.

# Tags
- #operations
- #reliability
```

```
# [backups] Document & test restore runbooks (tabletop + live)
---
Backups are only as good as restores. Create step-by-step restore guides and perform periodic tests (including PITR where enabled).

## why this is needed
- Ensures backups are usable under pressure.
- Surfaces gaps in permissions, tooling, or data coverage.
- Builds confidence in RPO/RTO.

## what's needs to be done
- For each app: write restore steps (stop → receive snapshot/restore dump → swap → start).
- Quarterly tabletop test; annual live test on non-prod copy or staging.
- Track metrics: time-to-restore, data loss window.

## how to confirm the remediation was successful
- A test restore of a representative app finishes within target RTO and passes functional checks.
- Runbook updated with lessons learned.

# Tags
- #backups
- #reliability
```

```
# [tls] Optional: enable HTTP/3 after headers/TLS hardening
---
HTTP/3 can improve performance on flaky/mobile networks. Enable after security headers and TLS profile are in place; monitor impact.

## why this is needed
- Faster connection setup and resilience to loss.
- Complements modern browser stacks.
- Optional but beneficial.

## what's needs to be done
- Add `--entrypoints.websecure.http3` to Traefik.
- Ensure firewall allows UDP/443 if required by your path.
- Monitor Netdata/Traefik metrics for errors.

## how to confirm the remediation was successful
- `curl --http3 -I https://<domain>` returns 200/301.
- Browser devtools show h3 in protocol column.

# Tags
- #performance
- #traefik
- #needsReview
```

```
# [identity] Standardize session lifetimes and SSO UX
---
Session/inactivity/remember-me settings vary. Align lifetimes across apps and SSO to balance security and convenience.

## why this is needed
- Predictable sign-in behavior and fewer lockouts.
- Reduced stolen cookie risk with reasonable expiry.
- Cleaner support burden.

## what's needs to be done
- Set Authelia session lifetime/inactivity consistent with policy (e.g., 1h idle, 12h absolute; remember-me for low-risk only).
- Align app-level sessions to rely on SSO tokens.
- Document defaults and exceptions.

## how to confirm the remediation was successful
- Inspect cookies and Authelia config; expiries match policy.
- Users report consistent login behavior across apps.

# Tags
- #sso
- #ux
```

```
# [images] Pin image versions (or digests); remove `latest`
---
Many services use `:latest`. Pin to versions or digests to get reproducible deploys and safe rollbacks.

## why this is needed
- Avoids surprise breaking changes on restart.
- Clear upgrade intent and changelog tracking.
- Easier incident rollback.

## what's needs to be done
- Replace `image: foo:latest` with `foo:1.2.3` (or `@sha256:<digest>`).
- Track upstream release notes; update intentionally during maintenance windows.
- Keep previous tag noted for rollback.

## how to confirm the remediation was successful
- `docker compose config | grep -E 'image:'` shows fixed versions/digests.
- `docker image ls` tracks expected tags; restarts don’t alter versions.

# Tags
- #release
- #reliability
- #docker
```
