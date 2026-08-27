#!/usr/bin/env bash
# Write a workstation image to a block device.
#
# This is the single most destructive operation in the repo -- it overwrites a
# disk unrecoverably -- so it refuses to run without an explicit target, shows
# what it is about to destroy, and requires the device path to be typed back.
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: scripts/flash.sh --device /dev/sdX [--image PATH] [--yes]

  --device DEV   Target block device (e.g. /dev/sdb, /dev/nvme0n1).
                 Must be a whole disk, not a partition.
  --image PATH   Image to write. Defaults to the newest .raw or .raw.zst
                 under build/.
  --yes          Skip the confirmation prompt. For scripted use only.

The image is written with dd; the root filesystem is grown to fill the disk on
first boot, so a small image on a large disk is expected and fine.
USAGE
}

DEVICE=""; IMAGE=""; ASSUME_YES=0
while [ $# -gt 0 ]; do
    case "$1" in
        --device) DEVICE="${2:?--device needs a value}"; shift 2 ;;
        --image)  IMAGE="${2:?--image needs a value}"; shift 2 ;;
        --yes)    ASSUME_YES=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
    esac
done

[ -n "$DEVICE" ] || { echo "error: --device is required" >&2; usage; exit 2; }

if [ -z "$IMAGE" ]; then
    IMAGE=$(find build -maxdepth 2 \( -name '*.raw.zst' -o -name '*.raw' \) 2>/dev/null \
            | sort | tail -1)
    [ -n "$IMAGE" ] || { echo "error: no image found under build/; pass --image" >&2; exit 1; }
fi
[ -f "$IMAGE" ] || { echo "error: no such image: $IMAGE" >&2; exit 1; }
[ -b "$DEVICE" ] || { echo "error: $DEVICE is not a block device" >&2; exit 1; }

# Refuse partitions: writing a whole-disk image to /dev/sdb1 produces
# something that cannot boot and quietly destroys one partition instead.
if [ -e "/sys/class/block/$(basename "$DEVICE")/partition" ]; then
    # Derive the parent from sysfs rather than trimming digits off the name --
    # stripping digits turns /dev/nvme0n1p2 into "/dev/nvme", which is useless
    # advice on exactly the disks this image targets.
    PARENT=$(lsblk -no PKNAME "$DEVICE" 2>/dev/null | head -1)
    echo "error: $DEVICE is a partition. Pass the whole disk${PARENT:+ (/dev/$PARENT)}." >&2
    exit 1
fi

# Refuse the running system's own disk.
ROOT_SRC=$(findmnt -no SOURCE / || true)
ROOT_DISK=$(lsblk -no PKNAME "$ROOT_SRC" 2>/dev/null | head -1 || true)
if [ -n "$ROOT_DISK" ] && [ "/dev/$ROOT_DISK" = "$DEVICE" ]; then
    echo "error: $DEVICE is the disk this system is running from. Refusing." >&2
    exit 1
fi

echo
echo "About to COMPLETELY ERASE this device:"
echo
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL,SERIAL "$DEVICE"
echo
echo "  Image:  $IMAGE ($(du -h "$IMAGE" | cut -f1))"
echo "  Target: $DEVICE"
echo
echo "Everything on $DEVICE will be destroyed and is not recoverable."
echo

if [ "$ASSUME_YES" -ne 1 ]; then
    printf 'Type the device path to confirm: '
    read -r CONFIRM
    [ "$CONFIRM" = "$DEVICE" ] || { echo "Aborted."; exit 1; }
fi

# Unmount anything currently mounted from the target.
for part in $(lsblk -lno NAME "$DEVICE" | tail -n +2); do
    if findmnt -no TARGET "/dev/$part" >/dev/null 2>&1; then
        echo "==> Unmounting /dev/$part"
        sudo umount "/dev/$part"
    fi
done

echo "==> Writing (this takes a while; progress below)"
case "$IMAGE" in
    *.zst) zstd -dc "$IMAGE" | sudo dd of="$DEVICE" bs=4M status=progress conv=fsync ;;
    *)     sudo dd if="$IMAGE" of="$DEVICE" bs=4M status=progress conv=fsync ;;
esac

echo "==> Flushing"
sync
sudo blockdev --flushbufs "$DEVICE" 2>/dev/null || true

echo
echo "Done. $DEVICE is ready to boot."
echo "On first boot the root filesystem grows to fill the disk and the"
echo "bootloader is reinstalled for this machine's firmware."
