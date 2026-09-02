#!/usr/bin/env bash
# Upload a built image to the artifact bucket and point a channel at it.
#
# Retention lives here rather than in Terraform (see terraform/artifacts/main.tf)
# so there is exactly one place that decides how many builds are kept.
set -euo pipefail

: "${WORKSTATION_BUCKET:?set WORKSTATION_BUCKET (terraform -chdir=terraform/artifacts output)}"
: "${AWS_ENDPOINT_URL:=}"

VERSION="${VERSION:?set VERSION, e.g. 2026.08.27-a1b2c3d}"
CHANNEL="${WORKSTATION_CHANNEL:-stable}"
KEEP="${WORKSTATION_KEEP:-5}"
SRC="build/workstation-${VERSION}"

aws_s3() {
    if [ -n "$AWS_ENDPOINT_URL" ]; then
        aws --endpoint-url "$AWS_ENDPOINT_URL" "$@"
    else
        aws "$@"
    fi
}

[ -d "$SRC" ] || { echo "error: no build at ${SRC}" >&2; exit 1; }
[ -f "${SRC}/SHA256SUMS" ] || { echo "error: ${SRC}/SHA256SUMS missing; build did not finish" >&2; exit 1; }

# Never publish something that does not match its own checksums -- this is the
# last point before an image goes somewhere it will be flashed onto a disk.
echo "==> Verifying local artifacts"
(cd "$SRC" && sha256sum -c SHA256SUMS --ignore-missing)

echo "==> Uploading ${VERSION}"
aws_s3 s3 sync "$SRC/" "s3://${WORKSTATION_BUCKET}/images/${VERSION}/" \
    --exclude '*' --include '*.zst' --include 'SHA256SUMS' --include 'manifest.json' \
    --include 'workstation-manifest.json' --include 'workstation-declared.json' \
    --include 'docs.html'

# The pointer moves only after the upload succeeds, so a failed publish leaves
# the channel on the previous good image rather than on a partial one.
echo "==> Pointing channel '${CHANNEL}' at ${VERSION}"
printf '%s\n' "$VERSION" > /tmp/latest.txt
aws_s3 s3 cp /tmp/latest.txt "s3://${WORKSTATION_BUCKET}/channels/${CHANNEL}/latest.txt"
rm -f /tmp/latest.txt

echo "==> Pruning to the newest ${KEEP} builds"
CURRENT=$(aws_s3 s3 ls "s3://${WORKSTATION_BUCKET}/images/" \
          | awk '{print $2}' | tr -d '/' | sort)
TOTAL=$(printf '%s\n' "$CURRENT" | grep -c . || true)
if [ "$TOTAL" -gt "$KEEP" ]; then
    printf '%s\n' "$CURRENT" | head -n "-${KEEP}" | while read -r old; do
        [ -n "$old" ] || continue
        # Never delete whatever a channel currently points at, however old.
        if [ "$old" = "$VERSION" ]; then continue; fi
        echo "    removing ${old}"
        aws_s3 s3 rm "s3://${WORKSTATION_BUCKET}/images/${old}/" --recursive --quiet
    done
fi

echo
echo "Published ${VERSION} to channel '${CHANNEL}'."
echo "Image contents: s3://${WORKSTATION_BUCKET}/images/${VERSION}/docs.html"
echo "Pull it elsewhere with: make fetch"
