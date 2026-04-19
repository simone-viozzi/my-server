# Backup System

## Architecture

Hybrid backup with two layers:

1. **Local btrfs snapshots** (via btrbk) — instant rollback, no network needed
2. **Offsite restic backups** (to Backblaze B2) — disaster recovery

```
container stop
    |
btrfs snapshot (atomic, per-volume)
    |
container start
    |
restic backup (snapshot -> B2)
    |
restic forget --prune (retention policy)
```

Each backup service has a systemd timer that triggers a script which:
- Acquires a global lock (`/var/lock/backup.lock`) to prevent concurrent backups
- Stops all containers in the service in a single `systemctl stop` call (systemd resolves dependency order — dependents stop before their dependencies, like `docker-compose down`)
- Takes btrfs snapshots of all volumes belonging to the service
- Restarts all containers in a single `systemctl start` call (systemd starts dependencies before dependents)
- Pushes snapshots to B2 via restic
- Prunes old restic snapshots per retention policy
- Sends success/failure notifications via Apprise

### What gets backed up

| Service      | Volumes                                    | Schedule | Timeout |
|--------------|------------------------------------------  |----------|---------|
| immich       | immich-upload (HDD), immich-pgdata (NVMe)  | 02:00    | 6h      |
| authelia     | authelia-data (HDD, SQLite)                | 02:30    | 30m     |
| silverbullet | silverbullet-space (HDD)                   | 03:00    | 30m     |

Volume definitions and backup annotations live in each container module (via `podman.volumes` and `backup.services`).

### Retention

| Layer           | Daily | Weekly | Monthly |
|-----------------|-------|--------|---------|
| Local snapshots | 2     | 1      | -       |
| Offsite (B2)    | 4     | 2      | 2       |

### Integrity checks

A weekly `restic check` timer runs for each service to verify B2 repo integrity.
Failures trigger notifications via the same `notify-failure@` template.

```bash
# Check status
systemctl list-timers 'restic-check-*'

# Run manually
sudo systemctl start restic-check-authelia
```

If a check fails:

1. **Read the logs** — most failures are transient (network, B2 rate limit):
   ```bash
   journalctl -u restic-check-<service> -n 50
   ```
   If transient, just re-run: `sudo systemctl start restic-check-<service>`

2. **Deep check** — verify actual data blobs, not just metadata:
   ```bash
   sudo bash -c 'set -a; source /run/secrets/rendered/restic-b2.env
   restic -r ${RESTIC_REPO_BASE}/<service> \
     --password-file /run/secrets/restic_password_<service> check --read-data'
   ```

3. **Repair index** — if the index is inconsistent but data is intact:
   ```bash
   restic ... repair index
   restic ... repair snapshots
   restic ... check
   ```

4. **Last resort: re-initialize** — only if the repo is unrecoverably corrupt.
   **This destroys all historical backups for this service.**
   Before doing this, make sure you still have local btrfs snapshots or a
   current copy of the live data. Delete the repo contents from B2 (web
   console or b2 CLI), then the next scheduled backup will auto-initialize
   a fresh repo via `restic init`.

### Secrets

All stored in sops (`secrets/secrets.yaml`):

- `b2_key_id` — B2 application key ID
- `b2_application_key` — B2 application key secret
- `restic_repo_base` — S3 endpoint + bucket (e.g., `s3:s3.eu-central-003.backblazeb2.com/bucket-name`)
- `restic_password_<service>` — per-service restic encryption password

## Operations

### Check backup status

```bash
# Timer schedule
systemctl list-timers 'backup-*'

# Last run status
systemctl status backup-authelia
systemctl status backup-immich

# View backup config
backup-config

# View logs
journalctl -u backup-authelia -n 50
journalctl -u backup-immich -n 50
```

### Trigger a manual backup

```bash
sudo systemctl start backup-authelia
# Watch progress:
journalctl -u backup-authelia -f
```

### List snapshots

Local btrfs snapshots:

```bash
ls /mnt/btrbk/hdd/docker-volumes/.snapshots/
ls /mnt/btrbk/nvme/docker-volumes/.snapshots/
```

Offsite restic snapshots (requires root for sops secrets):

```bash
sudo bash -c 'set -a; source /run/secrets/rendered/restic-b2.env
restic -r ${RESTIC_REPO_BASE}/authelia \
  --password-file /run/secrets/restic_password_authelia snapshots'
```

## Restore

### Fast: from local btrfs snapshot

Use when the machine is intact and you just need to roll back data.

```bash
# 1. Pick a snapshot
ls /mnt/btrbk/hdd/docker-volumes/.snapshots/

# 2. Stop the service
sudo systemctl stop podman-authelia.service

# 3. Replace the live subvolume with the snapshot
#    (move current out of the way first)
sudo mv /mnt/btrbk/hdd/docker-volumes/@authelia-data \
        /mnt/btrbk/hdd/docker-volumes/@authelia-data.broken
sudo btrfs subvolume snapshot \
  /mnt/btrbk/hdd/docker-volumes/.snapshots/@authelia-data.20260413T2357 \
  /mnt/btrbk/hdd/docker-volumes/@authelia-data

# 4. Restart
sudo systemctl start podman-authelia.service

# 5. Verify, then clean up
sudo btrfs subvolume delete /mnt/btrbk/hdd/docker-volumes/@authelia-data.broken
```

For immich (multi-volume), repeat steps 3-4 for both `@immich-upload` (HDD) and `@immich-pgdata` (NVMe), stopping all immich containers first:

```bash
sudo systemctl stop podman-immich-server.service podman-immich-machine-learning.service \
  podman-immich-postgres.service podman-immich-redis.service

# Restore both volumes, then:
sudo systemctl start podman-immich-postgres.service podman-immich-redis.service \
  podman-immich-server.service podman-immich-machine-learning.service
```

### Full: from B2 offsite (NixOS)

Use when local snapshots are gone but the NixOS system is running.

```bash
# 1. Stop the service
sudo systemctl stop podman-authelia.service

# 2. Restore to a temp directory
sudo bash -c 'set -a; source /run/secrets/rendered/restic-b2.env
restic -r ${RESTIC_REPO_BASE}/authelia \
  --password-file /run/secrets/restic_password_authelia \
  restore latest --target /tmp/restore-authelia'

# 3. Find the restored data
ls /tmp/restore-authelia/mnt/btrbk/hdd/docker-volumes/.snapshots/
# It mirrors the original snapshot path, e.g.:
#   /tmp/restore-authelia/mnt/btrbk/hdd/docker-volumes/.snapshots/@authelia-data.<timestamp>/

# 4. Replace the live data
SNAP=$(ls -1d /tmp/restore-authelia/mnt/btrbk/hdd/docker-volumes/.snapshots/@authelia-data.* | head -1)
sudo mv /mnt/btrbk/hdd/docker-volumes/@authelia-data \
        /mnt/btrbk/hdd/docker-volumes/@authelia-data.broken
sudo cp -a "$SNAP" /mnt/btrbk/hdd/docker-volumes/@authelia-data

# 5. Restart and verify
sudo systemctl start podman-authelia.service

# 6. Clean up
sudo rm -rf /tmp/restore-authelia
sudo btrfs subvolume delete /mnt/btrbk/hdd/docker-volumes/@authelia-data.broken
```

### Disaster recovery: from B2 on a fresh Linux system

Use when the server is gone. You need:
- Any Linux machine with `restic` installed
- The B2 credentials (key ID + application key)
- The restic repo base URL
- The restic password for the service

```bash
# 1. Install restic
#    Debian/Ubuntu: apt install restic
#    Arch: pacman -S restic
#    Nix: nix-shell -p restic
#    Or download from https://github.com/restic/restic/releases

# 2. Set credentials
export AWS_ACCESS_KEY_ID="<b2-key-id>"
export AWS_SECRET_ACCESS_KEY="<b2-application-key>"
export RESTIC_REPOSITORY="<restic-repo-base>/authelia"
export RESTIC_PASSWORD="<restic-password-for-authelia>"

# 3. List available snapshots
restic snapshots

# 4. Restore the latest (or a specific snapshot ID)
restic restore latest --target /tmp/restore-authelia

# 5. Your data is at:
#    /tmp/restore-authelia/mnt/btrbk/<disk>/docker-volumes/.snapshots/@<volume>.<timestamp>/
find /tmp/restore-authelia -type f
```

For immich, the restore contains two volumes from different disks:

```bash
export RESTIC_REPOSITORY="<restic-repo-base>/immich"
export RESTIC_PASSWORD="<restic-password-for-immich>"

restic restore latest --target /tmp/restore-immich

# Data locations:
#   /tmp/restore-immich/mnt/btrbk/hdd/docker-volumes/.snapshots/@immich-upload.<timestamp>/
#   /tmp/restore-immich/mnt/btrbk/nvme/docker-volumes/.snapshots/@immich-pgdata.<timestamp>/
```

### Where to find secrets in an emergency

All secrets are encrypted with age in `secrets/secrets.yaml`. To decrypt:

```bash
# You need the server's SSH host key (age-wrapped):
#   /etc/ssh/ssh_host_ed25519_key
# Or the age key derived from it.

sops -d secrets/secrets.yaml
```

If the server is gone but you have the SSH host key backed up, you can decrypt
the secrets file from any machine with `sops` and `age` installed.

**Keep a copy of the SSH host key and restic passwords somewhere safe outside
this server** (e.g., password manager, printed, safe deposit box).

## Adding a new service

1. In the container module, declare the volumes and the backup config together:

```nix
# ── Volumes ──
podman.volumes.my-service-data = {
  storage = "btrfs-hdd";  # plain | btrfs-hdd | btrfs-nvme
};

# ── Backup ──
backup.services.my-service = {
  enable = true;
  schedule = "03:00";
  timeout = "1h";
  volumes = [ "my-service-data" ];
};
```

Volume systemd services (`podman-volume-<name>.service`) are auto-generated from
`podman.volumes`. btrfs-backed storage types create a btrfs subvolume under the
matching disk; `plain` just creates a podman-managed volume. Only volumes listed
in `backup.services.<name>.volumes` are snapshotted and pushed to B2.

2. Add a restic password to sops:

```bash
sops secrets/secrets.yaml
# Add: restic_password_my-service: <generate-a-strong-password>
```

3. Rebuild and test:

```bash
nh os switch .
sudo systemctl start backup-my-service
journalctl -u backup-my-service -f
```

Containers are discovered automatically by name prefix (`my-service-*`) and stopped/started
as a group via `systemctl stop`/`start` — systemd uses the `After=`/`Requires=` dependencies
from the container module to determine the correct order.
