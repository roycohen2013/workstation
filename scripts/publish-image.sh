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

# Whatever a channel points at is pinned, however old. A channel pointer is the
# only thing `make fetch` resolves through, so deleting the image underneath one
# breaks that channel outright -- and a channel deliberately parked on an older
# build (a slow-moving `stable` while `edge` races ahead) is exactly the case
# where age alone is the wrong reason to delete. Protecting only the version
# being published, as this once did, is not the same guarantee.
#
# The set is read from the bucket rather than tracked here: other machines
# publish to other channels, so this script cannot know from its own arguments
# what else holds a pointer.
#
# A pointer that cannot be read fails the whole listing. A partial answer is the
# dangerous one: it looks like a complete pinned set, so the channel that could
# not be read is precisely the one whose image gets deleted. Both failures
# return explicitly rather than leaning on `set -e`, which does not apply here
# -- the caller tests this function in an `if` condition, and that suspends
# errexit for the whole call, function body included. The `while` is fed by a
# heredoc rather than a pipe for the same reason: `return` has to leave the
# function, not just a pipeline subshell nothing looks at.
pinned_versions() {
    local channels channel version
    channels=$(aws_s3 s3 ls "s3://${WORKSTATION_BUCKET}/channels/" \
               | awk '{print $2}' | tr -d '/') || return 1
    while read -r channel; do
        [ -n "$channel" ] || continue
        version=$(aws_s3 s3 cp \
                  "s3://${WORKSTATION_BUCKET}/channels/${channel}/latest.txt" - \
                  --quiet | tr -d '[:space:]') || return 1
        # An empty pointer pins nothing; it is not a read failure.
        [ -n "$version" ] || continue
        printf '%s\n' "$version"
    done <<EOF
$channels
EOF
}

# A prune that cannot see the pinned set is not safe to run: not knowing what a
# channel points at is not the same as nothing being pinned. Keeping a few extra
# images costs storage; deleting the image under a channel breaks every machine
# that fetches from it. So this warns and leaves the bucket alone -- the publish
# itself has already succeeded by this point and is not failed over retention.
if PINNED=$(pinned_versions); then
    # The version just published is pinned too. Its own pointer was written
    # above so the listing already covers it; naming it again keeps the
    # guarantee independent of that ordering.
    PINNED=$(printf '%s\n%s\n' "$PINNED" "$VERSION" | sed '/^$/d' | sort -u)

    CURRENT=$(aws_s3 s3 ls "s3://${WORKSTATION_BUCKET}/images/" \
              | awk '{print $2}' | tr -d '/' | sort)
    TOTAL=$(printf '%s\n' "$CURRENT" | grep -c . || true)
    if [ "$TOTAL" -gt "$KEEP" ]; then
        # Keeping a pinned build can leave more than KEEP images in the bucket.
        # That is the intended trade: a channel that still resolves beats an
        # exact retention count.
        printf '%s\n' "$CURRENT" | head -n "-${KEEP}" | while read -r old; do
            [ -n "$old" ] || continue
            if printf '%s\n' "$PINNED" | grep -qxF "$old"; then
                echo "    keeping ${old} (a channel points at it)"
                continue
            fi
            echo "    removing ${old}"
            aws_s3 s3 rm "s3://${WORKSTATION_BUCKET}/images/${old}/" \
                --recursive --quiet
        done
    fi
else
    echo "    warning: could not read the channel pointers, so nothing was" >&2
    echo "    pruned rather than risk deleting an image a channel still" >&2
    echo "    resolves to. ${VERSION} is published; re-run to prune." >&2
fi

echo
echo "Published ${VERSION} to channel '${CHANNEL}'."
echo "Image contents: s3://${WORKSTATION_BUCKET}/images/${VERSION}/docs.html"
echo "Pull it elsewhere with: make fetch"
