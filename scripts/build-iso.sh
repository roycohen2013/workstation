#!/usr/bin/env bash
# Remaster the Ubuntu live-server ISO into an unattended installer.
#
# Complements the image rather than replacing it:
#   image        -> instant VM, or dd onto a disk you control
#   this ISO     -> a clean install on hardware whose disk layout you do not
#                   know in advance, letting the real installer handle
#                   partitioning, drivers and firmware
#
# Both end up running the same ansible/site.yml, so they cannot drift.
set -euo pipefail

# The Ubuntu release is written down once, in packer/variables.pkr.hcl, and
# read from there rather than copied here. Two copies drift: the ISO built by
# this script and the image built by Packer would silently target different
# releases, and nothing downstream would notice until something built against
# the wrong suite. Parsed rather than sourced because that file is HCL; if the
# parse ever stops working the script stops with it instead of guessing.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -z "${RELEASE:-}" ]; then
    RELEASE="$(sed -n '/variable "ubuntu_release"/,/^}/ s/.*default *= *"\([^"]*\)".*/\1/p' \
        "${REPO_ROOT}/packer/variables.pkr.hcl")"
fi
if [ -z "$RELEASE" ]; then
    echo "error: could not read ubuntu_release from packer/variables.pkr.hcl" >&2
    echo "       set RELEASE=<version> to override, and fix the parse in this script" >&2
    exit 1
fi
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

# Absolute, not relative. xorriso's own boot-layout report (read further down)
# can embed a raw path back to this exact file -- real Ubuntu ISOs have a
# hybrid MBR/GPT boot area that xorriso cannot regenerate from higher-level
# flags, only copy byte-for-byte from the original, so its report says
# exactly that: read these bytes from build/cache/<iso>. That report is
# reused later from inside $EXTRACT, a different directory entirely, and a
# relative path there resolves against the wrong base and points at nothing.
ISO_PATH="$(cd "$CACHE" && pwd)/${ISO_NAME}"

# --- Extract ------------------------------------------------------------------
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
EXTRACT="${WORK}/iso"

echo "==> Extracting"
xorriso -osirrox on -indev "$ISO_PATH" -extract / "$EXTRACT" >/dev/null 2>&1
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
#
# The report is shell-quoted text meant to be reparsed by a shell (values with
# special characters come back as e.g. --modification-date='2026083121063400'),
# not plain whitespace-separated words. Capturing it into an unquoted variable
# and expanding that unquoted -- which is what this used to do -- does word
# splitting but does NOT strip those embedded quote characters, since they are
# not shell syntax at that point, just data. xorriso then receives arguments
# like the literal seven characters '2026083121063400' -- quote marks
# included -- and rejects them: "Not an ECMA-119 time string." xargs performs
# the same quote-stripping tokenization a shell would, without eval's risk of
# also executing anything embedded in the text (low, given this is xorriso's
# own report of a checksum-verified official ISO -- but avoidable at no cost).
echo "==> Reading source ISO boot layout"
mapfile -d '' -t MKISOFS_ARGS < <(
    xorriso -indev "$ISO_PATH" -report_el_torito as_mkisofs 2>/dev/null \
        | grep -v '^-V' \
        | xargs -n1 printf '%s\0'
)
[ "${#MKISOFS_ARGS[@]}" -gt 0 ] || { echo "error: could not read boot layout from source ISO" >&2; exit 1; }

echo "==> Building ${OUT_ISO}"
( cd "$EXTRACT" && xorriso -as mkisofs -r \
    -V "WORKSTATION_${VERSION}" \
    "${MKISOFS_ARGS[@]}" \
    -o "$(cd "$OLDPWD" && pwd)/${OUT_ISO}" . ) >/dev/null

sha256sum "$OUT_ISO" | tee "${OUT_ISO}.sha256"

echo
echo "Built ${OUT_ISO}"
echo "Write to USB with:  scripts/flash.sh --device /dev/sdX --image ${OUT_ISO}"
echo
echo "WARNING: this ISO installs unattended and wipes the target disk with no"
echo "         further prompting. Do not leave it in a machine you care about."
