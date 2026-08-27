#!/usr/bin/env bash
# Pull a published workstation image out of the artifact bucket and verify it.
#
# Checksum verification is not optional here: this downloads a multi-gigabyte
# file that is about to be written directly onto a boot disk.
set -euo pipefail

: "${WORKSTATION_BUCKET:?set WORKSTATION_BUCKET (see terraform/artifacts output)}"
: "${AWS_ENDPOINT_URL:=}"

DEST="${1:-build/downloads}"
CHANNEL="${WORKSTATION_CHANNEL:-stable}"

aws_s3() {
    if [ -n "$AWS_ENDPOINT_URL" ]; then
        aws --endpoint-url "$AWS_ENDPOINT_URL" s3 "$@"
    else
        aws s3 "$@"
    fi
}

mkdir -p "$DEST"

echo "==> Resolving latest image on channel '${CHANNEL}'"
aws_s3 cp "s3://${WORKSTATION_BUCKET}/channels/${CHANNEL}/latest.txt" "${DEST}/latest.txt" --quiet
VERSION=$(tr -d '[:space:]' < "${DEST}/latest.txt")
[ -n "$VERSION" ] || { echo "error: channel '${CHANNEL}' has no published version" >&2; exit 1; }
echo "    ${VERSION}"

PREFIX="s3://${WORKSTATION_BUCKET}/images/${VERSION}"
echo "==> Downloading ${VERSION}"
aws_s3 cp "${PREFIX}/SHA256SUMS" "${DEST}/SHA256SUMS"
aws_s3 sync "${PREFIX}/" "${DEST}/" --exclude '*' --include '*.zst' --include 'manifest.json'

echo "==> Verifying checksums"
(cd "$DEST" && grep -E '\.(raw|qcow2)\.zst$' SHA256SUMS | sha256sum -c -)

echo
echo "Image ready in ${DEST}:"
ls -lh "${DEST}"/*.zst
echo
echo "Boot it as a VM:   zstd -d ${DEST}/*.qcow2.zst && qemu-system-x86_64 -enable-kvm ..."
echo "Flash to a disk:   scripts/flash.sh --device /dev/sdX --image ${DEST}/${VERSION}.raw.zst"
