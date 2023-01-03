
# my server setup

## show case [WIP]

## bare metal description

```bash
$ sudo inxi --filter --width 90 -SGIMCPDp --ms
System:
  Kernel: 6.1.2-arch1-1 arch: x86_64 bits: 64 Console: pty pts/3 Distro: Arch Linux
Machine:
  Type: Desktop Mobo: ASRock model: 970M Pro3 serial: <filter> UEFI: American Megatrends
    v: P1.60 date: 06/17/2016
Memory:
  RAM: total: 7.73 GiB used: 2.71 GiB (35.0%)
  Report: arrays: 1 slots: 4 modules: 2 type: DDR3
CPU:
  Info: 6-core model: AMD Phenom II X6 1090T bits: 64 type: MCP cache: L2: 3 MiB
  Speed (MHz): avg: 933 min/max: 800/3200 cores: 1: 1600 2: 800 3: 800 4: 800 5: 800
    6: 800
Graphics:
  Device-1: AMD Redwood XT [Radeon HD 5670/5690/5730] driver: radeon v: kernel
  Display: server: No display server data found. Headless machine? tty: 176x50
  API: N/A Message: No display API data available in console. Headless machine?
Drives:
  Local Storage: total: 4.2 TiB used: 91.04 GiB (2.1%)
  ID-1: /dev/sda vendor: Kingston model: SA400S37120G size: 111.79 GiB
  ID-2: /dev/sdb vendor: Western Digital model: WD40EFAX-68JH4N1 size: 3.64 TiB
  ID-3: /dev/sdc vendor: Seagate model: ST3500312CS size: 465.76 GiB
Partition:
  ID-1: / size: 111.47 GiB used: 16.46 GiB (14.8%) fs: btrfs dev: /dev/sda2
  ID-2: /boot size: 329.3 MiB used: 108.4 MiB (32.9%) fs: vfat dev: /dev/sda1
  ID-3: /data/wd-red size: 3.64 TiB used: 74.48 GiB (2.0%) fs: btrfs dev: /dev/sdb1
  ID-4: /home size: 111.47 GiB used: 16.46 GiB (14.8%) fs: btrfs dev: /dev/sda2
  ID-5: /srv size: 111.47 GiB used: 16.46 GiB (14.8%) fs: btrfs dev: /dev/sda2
  [...]
  ID-7: /var/cache size: 111.47 GiB used: 16.46 GiB (14.8%) fs: btrfs dev: /dev/sda2
  [...]
  ID-11: /var/log size: 111.47 GiB used: 16.46 GiB (14.8%) fs: btrfs dev: /dev/sda2
  ID-12: /var/tmp size: 111.47 GiB used: 16.46 GiB (14.8%) fs: btrfs dev: /dev/sda2
Info:
  Processes: 318 Uptime: 57m Init: systemd Shell: Zsh inxi: 3.3.24
```

- `/dev/sda` is a 120GB Kingston ssd, hold the root of the system.
  - `/dev/sda1` -> `/boot`: hold the boot-loader (`fat32` partition of 300MB)
  - `/dev/sda2`: btrfs partition
- `/dev/sdb` is a 4TB WD Red, for data storage.
  - `/dev/sdb1`: btrfs partition
- `/dev/sdc` is a 500GB old hdd, not trustworthy and only hold torrents. Is formatted in EXT4 and is not part of the btrfs layout.
  - `/dev/sdc1`: EXT4 partition

### btrfs sub-volumes layout

The 120GB Kingston hold the system, so `/`, `/home` are on this drive.
The 4TB WD Red hold some docker volumes and other data.

#### 120GB ssd

The layout of the main drive is:

- `@` -> `/`
- `@home` -> `/home`
- `@cache` -> `/var/cache`
- `@log` -> `/var/log`
- `@tmp` -> `/var/tmp`
- `@srv` -> `/srv`

Following [Snapper#Suggested filesystem layout](https://wiki.archlinux.org/title/Snapper#Suggested_filesystem_layout) and [Snapper#Preventing slowdowns](https://wiki.archlinux.org/title/Snapper#Preventing_slowdowns).

All the mounts are done with `fstab`, for example:

```bash
UUID=<...> / btrfs rw,relatime,ssd,space_cache=v2,subvolid=256,subvol=/@,compress=zstd 0 0
```

The options are generated using the `genfstab` script ([extra/arch-install-scripts](https://man.archlinux.org/man/extra/arch-install-scripts/genfstab.8.en))

#### 4TB WD Red

- `@data` -> `/data/wd-red`: generic data folder.
- `docker-volumes`: folder that contains some docker volumes mapped to btrfs sub-volumes. (Note, this is not a sub-volume but a normal folder.)

## docker configuration

Docker is configured to use the BTRFS storage driver, as described [here](https://docs.docker.com/storage/storagedriver/btrfs-driver/). This way the images of the containers are stored in sub-volumes and not included in the snapshots.

## snapper configuration

First, create the config for the sub-volumes you are interested in backing-up:

```bash
sudo snapper -c root create-config /
sudo snapper -c home create-config /home
```

### fix snapper sub-volume layout

As described in [Snapper#Suggested filesystem layout](https://wiki.archlinux.org/title/Snapper#Suggested_filesystem_layout) i moved the `.../.snapshots` out of the sub-volume I'm taking a snapshot of.

To do so i created a folder in the btrfs root (`snapshots/`) and inside the sub-volumes that will hold the snapshots:

```bash
sudo btrfs subvolume list /
[...]
ID 413 gen 3398 top level 5 path snapshots/@root-snap
ID 414 gen 3397 top level 5 path snapshots/@home-snap
[...]
```

Than i mapped the sub-volumes to the `.../.snapshots` using `fstab`:

```fstab
UUID=<...> /.snapshots btrfs rw,relatime,ssd,space_cache=v2,subvolid=413,subvol=/snapshots/@root-snap,compress=zstd  0 0

UUID=<...> /home/.snapshots btrfs rw,relatime,ssd,space_cache=v2,subvolid=414,subvol=/snapshots/@home-snap,compress=zstd  0 0
```

### snapper configs

The configs are located in `/etc/snapper/configs`. I enabled `NUMBER_CLEANUP`, `TIMELINE_CREATE` and `TIMELINE_CLEANUP`. And changed the limits to keep less than 10 snapshots in total.

### topgrade snapper pre-snap

To upgrade my system i use topgrade. I could have added snapper to a pacman hook, but since topgrade also does a lot of other stuff i preferred to add a pre and post step. The full topgrade config can be found [here](https://github.com/simone-viozzi/my-dot-files/blob/dotfiles-server/.config/topgrade.toml)

```toml
[pre_commands]
"snap before upgrade" = """echo \"taking a snap...\" && \
                                   sudo snapper -c root create -t single -d \"snap before upgrade\" -c number && \
                                   echo \"snap done...\""""

[post_commands]
"snapper cleanup" = """echo \"cleaning up the snaps...\" && \
                       sudo snapper -c root cleanup number && \
                       sudo snapper -c root list"""
```

### snap-sync setup

The ssd is kind of old and will die before the WD Red. To prepare for this scenario i used `snap-sync` ([link](https://github.com/qubidt/snap-sync)) to send the snapshots from the ssd to the hdd.

To set this up i created a sub-volume in the WD Red, `@system-backup`, and mounted it with `fstab` to `/system-backup`. To configure `snap-sync` you have to run in manually the first time:

```bash
sudo snap-sync --UUID <UUID of WD Red> --subvolid <subvol id of @system-backup> -c "root home" -q -n
```

To avoid the creation of another 2 sub-volumes, when asked for the path leave it empty.

The directory structure will be:

```bash
/system-backup/
├── home/
│  ├── 8/
│  └── 9/
└── root/
   ├── 9/
   └── 10/
```

As advised in the man of `snap-sync` to run it periodically you need to create a systemd unit and timer. To set the timer see [link](https://wiki.archlinux.org/title/systemd/Timers#Realtime_timer).

```bash
$ sudo vim /etc/systemd/system/snap-sync.service
[Unit]
Description=Run snap-sync backup

[Install]
WantedBy=multi-user.target

[Service]
Type=simple
ExecStart=/usr/bin/systemd-inhibit snap-sync --UUID <UUID of WD Red> --subvolid <subvol id of @system-backup> -c "root home" -q -n

$ sudo vim /etc/systemd/system/snap-sync.timer
[Unit]
Description=Run snap-sync every 3 days

[Timer]
OnCalendar=*-*-01,04,07,10,13,16,19,22,25,28,31 00:00:00
AccuracySec=12h
Persistent=true

[Install]
WantedBy=timers.target
```

Then you need to enable the timer:

```bash
sc-enable-now snap-sync.timer
```

To debug the unit you can run it with `sc-start`, it will do it's stuff and exit.

#### meaning of systemd-inhibit

`snap-sync` is a wrapper around btrfs send receive, for this reason it could take some time to move the data between the 2 drives. With `systemd-inhibit` i can prevent the shutdown of the server while the process is running. The poweroff / reboot command must include `--check-inhibitors=yes`, so for example:

```bash
systemctl poweroff --check-inhibitors=yes
```

### snap-sync cleanup

By default `snap-sync` have no clean-up algorithm. A user created a script to implement the clean-up, [link](https://gist.github.com/alanorth/fdaa3f3be16b58822a4a876afbd62604).

To use it, download, add execution permissions and move it to `/usr/local/bin/snap-sync-cleanup.sh`. Than you need systemd service and timer:

```
$ sudo vim /etc/systemd/system/snap-sync-cleanup.service
[Unit]
Description=Run snap-sync-cleanup

[Install]
WantedBy=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/bin/snap-sync-cleanup.sh

$ sudo vim /etc/systemd/system/snap-sync-cleanup.timer
[Unit]
Description=Run snap-sync-cleanup every 3 days

[Timer]
OnCalendar=*-*-01,04,07,10,13,16,19,22,25,28,31 00:00:00
AccuracySec=12h
Persistent=true

[Install]
WantedBy=timers.target

$ sc-enable-now snap-sync-cleanup.timer
```

## docker volumes on the WD Red

To create a docker volume mapped to a btrfs sub-volume you need to:

- create the sub-vol: `btrfs subvolume create @name`
- create the docker volume:

    ```bash
    docker volume create --driver local --opt type=btrfs \
        --opt device=/dev/sdb1 \
        --opt o=subvol=<path>/@name \
        name
    ```

- than you can use it in the docker-compose with:

    ```yaml
    volumes:
      name:
        external: true
    ```

