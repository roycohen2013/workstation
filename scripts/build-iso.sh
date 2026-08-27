#!/usr/bin/env bash
# Remaster the Ubuntu live-server ISO into an unattended installer.
#
# Complements the golden image rather than replacing it:
#   golden image -> instant VM, or dd onto a disk you control
#   this ISO     -> a clean install on hardware whose disk layout you do not
#                   know in advance, letting the real installer handle
#                   partitioning, drivers and firmware
#
# Both end up running the same ansible/site.yml, so they cannot drift.
set -euo pipefail

RELEASE="${RELEASE:-26.04}"
ISO_NAME="ubuntu-${RELEASE}-live-server-amd64.iso"
ISO_URL="${ISO_URL:-https://releases.ubuntu.com/${RELEASE}/${ISO_NAME}}"
SUMS_URL="${SUMS_URL:-https://releases.ubuntu.com/${RELEASE}/SHA256SUMS}"

CACHE="${CACHE:-build/cache}"
OUT_DIR="${OUT_DIR:-build}"
VERSION="${VERSION:-dev}"
OUT_ISO="${OUT_DIR}/workstation-${VERSION}-installer.iso"

USERNAME="${USERNAME:-roy}"
HOSTNAME_="${HOSTNAME_:-workstation}"
KEYBOARD="${KEYBOARD:-us}"
REPO_URL="${REPO_URL:-https://github.com/roycohen2013/workstation.git}"
PASSWORD_HASH="${PASSWORD_HASH:-}"

for tool in xorriso curl sed; do
    command -v "$tool" >/dev/null || { echo "error: $tool is required (apt install xorriso)" >&2; exit 1; }
done

# The installer needs a real password hash; there is no safe default, because
# a default would mean every machine installed from this ISO shares a login.
if [ -z "$PASSWORD_HASH" ]; then
    echo "==> Set a login password for ${USERNAME}"
    PASSWORD_HASH=$(openssl passwd -6)
fi

mkdir -p "$CACHE" "$OUT_DIR"

# --- Fetch and verify the source ISO -----------------------------------------
if [ ! -f "${CACHE}/${ISO_NAME}" ]; then
    echo "==> Downloading ${ISO_NAME}"
    curl -fL --progress-bar -o "${CACHE}/${ISO_NAME}" "$ISO_URL"
fi

echo "==> Verifying source ISO"
curl -fsSL "$SUMS_URL" -o "${CACHE}/SHA256SUMS"
(cd "$CACHE" && grep " \*\?${ISO_NAME}\$" SHA256SUMS | sha256sum -c -)

# --- Extract ------------------------------------------------------------------
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
EXTRACT="${WORK}/iso"

echo "==> Extracting"
xorriso -osirrox on -indev "${CACHE}/${ISO_NAME}" -extract / "$EXTRACT" >/dev/null 2>&1
chmod -R u+w "$EXTRACT"

# --- Inject the autoinstall seed ---------------------------------------------
echo "==> Injecting autoinstall seed"
mkdir -p "${EXTRACT}/nocloud"
sed -e "s|@USERNAME@|${USERNAME}|g" \
    -e "s|@HOSTNAME@|${HOSTNAME_}|g" \
    -e "s|@KEYBOARD@|${KEYBOARD}|g" \
    -e "s|@REPO_URL@|${REPO_URL}|g" \
    -e "s|@PASSWORD_HASH@|${PASSWORD_HASH}|g" \
    iso/nocloud/user-data.tmpl > "${EXTRACT}/nocloud/user-data"
: > "${EXTRACT}/nocloud/meta-data"

# Point every boot entry at the embedded seed and stop waiting at the menu.
echo "==> Rewriting boot entries"
for cfg in "${EXTRACT}/boot/grub/grub.cfg" "${EXTRACT}/EFI/boot/grub.cfg"; do
    [ -f "$cfg" ] || continue
    sed -i 's|linux\s*/casper/vmlinuz\(.*\)---|linux /casper/vmlinuz\1 autoinstall ds=nocloud\;s=/cdrom/nocloud/ ---|g' "$cfg"
    sed -i 's/^set timeout=.*/set timeout=5/' "$cfg"
done

# md5 manifest, if present, no longer matches the modified tree; the integrity
# check would fail the install otherwise.
rm -f "${EXTRACT}/md5sum.txt"

# --- Repack -------------------------------------------------------------------
# Rather than hand-writing mkisofs boot arguments (which differ between Ubuntu
# releases and are easy to get subtly wrong, producing an ISO that boots in a
# VM but not off USB), ask xorriso to report the exact arguments the source ISO
# was built with and reuse them verbatim.
echo "==> Reading source ISO boot layout"
MKISOFS_ARGS=$(xorriso -indev "${CACHE}/${ISO_NAME}" -report_el_torito as_mkisofs 2>/dev/null \
               | grep -v '^-V' | tr '\n' ' ')
[ -n "$MKISOFS_ARGS" ] || { echo "error: could not read boot layout from source ISO" >&2; exit 1; }

echo "==> Building ${OUT_ISO}"
# shellcheck disable=SC2086
( cd "$EXTRACT" && xorriso -as mkisofs -r \
    -V "WORKSTATION_${VERSION}" \
    ${MKISOFS_ARGS} \
    -o "$(cd "$OLDPWD" && pwd)/${OUT_ISO}" . ) >/dev/null

sha256sum "$OUT_ISO" | tee "${OUT_ISO}.sha256"

echo
echo "Built ${OUT_ISO}"
echo "Write to USB with:  scripts/flash.sh --device /dev/sdX --image ${OUT_ISO}"
echo
echo "WARNING: this ISO installs unattended and wipes the target disk with no"
echo "         further prompting. Do not leave it in a machine you care about."
