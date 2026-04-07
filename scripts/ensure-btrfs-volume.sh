#!/usr/bin/env bash
# ensure-btrfs-volume.sh — Ensure a Podman volume backed by a btrfs subvolume exists.
#
# Usage: ensure-btrfs-volume.sh <volume-name> <subvol-name> <device-uuid>
#
# - If the Podman volume already exists, does nothing.
# - If the btrfs subvolume doesn't exist on disk, prints instructions and exits 1.
# - Otherwise, creates the Podman volume pointing to the btrfs subvolume.

set -euo pipefail

VOLUME_NAME="$1"
SUBVOL_NAME="$2"
DEVICE_UUID="$3"

PODMAN="$(command -v podman)"
DEVICE="/dev/disk/by-uuid/${DEVICE_UUID}"
SUBVOL_PATH="docker-volumes/@${SUBVOL_NAME}"

# 1. Check if Podman volume already exists
if "${PODMAN}" volume inspect "${VOLUME_NAME}" >/dev/null 2>&1; then
    echo "Podman volume '${VOLUME_NAME}' already exists, skipping."
    exit 0
fi

# 2. Check if the device exists
if [ ! -e "${DEVICE}" ]; then
    echo "ERROR: Device ${DEVICE} not found."
    echo ""
    echo "  The HDD with UUID ${DEVICE_UUID} is not available."
    echo "  Check that the disk is connected and recognized by the system:"
    echo ""
    echo "    lsblk -f"
    echo "    blkid"
    echo ""
    exit 1
fi

# 3. Check if the btrfs subvolume exists on disk
TMPDIR=$(mktemp -d)
trap 'umount "${TMPDIR}" 2>/dev/null; rmdir "${TMPDIR}" 2>/dev/null' EXIT

mount -t btrfs "${DEVICE}" "${TMPDIR}" -o ro

if ! btrfs subvolume show "${TMPDIR}/${SUBVOL_PATH}" >/dev/null 2>&1; then
    echo "ERROR: Btrfs subvolume '${SUBVOL_PATH}' not found on device ${DEVICE}."
    echo ""
    echo "  The Podman volume '${VOLUME_NAME}' needs a btrfs subvolume that doesn't exist yet."
    echo "  To create it, run:"
    echo ""
    echo "    sudo mount -t btrfs ${DEVICE} /mnt"
    echo "    sudo btrfs subvolume create /mnt/${SUBVOL_PATH}"
    echo "    sudo umount /mnt"
    echo ""
    echo "  Then restart this service:"
    echo ""
    echo "    sudo systemctl restart podman-volume-${VOLUME_NAME}.service"
    echo ""
    exit 1
fi

umount "${TMPDIR}"
rmdir "${TMPDIR}"
trap - EXIT

# 4. Create the Podman volume
echo "Creating Podman volume '${VOLUME_NAME}' backed by btrfs subvol '${SUBVOL_PATH}'..."
"${PODMAN}" volume create \
    --driver local \
    --opt type=btrfs \
    --opt "device=${DEVICE}" \
    --opt "o=subvol=${SUBVOL_PATH}" \
    "${VOLUME_NAME}"

echo "Done: Podman volume '${VOLUME_NAME}' created successfully."
