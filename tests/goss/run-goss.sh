#!/usr/bin/env bash
# Runs a goss suite against the machine it is on:
#   - inside the Packer build VM, as the image's last test (image.yaml)
#   - on the GitHub runner after apply.yml's converge (shared.yaml)
#   - on this machine after `make apply`, via `make verify` (shared.yaml)
#
#   run-goss.sh <suite.yaml>
#
# goss is a single static binary with YAML assertions, which is why it is used
# rather than testinfra: it needs no Python and leaves nothing behind once this
# script exits.
#
# The suites are templates over the declared set roles/manifest recorded in
# /etc/workstation-declared.json, passed here as goss's --vars. The file must
# already exist -- this script never generates it -- so a machine is checked
# against what it was last converged to, not against whatever group_vars says
# now.
set -euo pipefail

suite="${1:?usage: run-goss.sh <suite.yaml>}"
vars="${GOSS_VARS:-/etc/workstation-declared.json}"

# The pin lives in versions.env. In a checkout it is read from there; inside
# the Packer VM this script runs from a temporary path with no repo around it,
# so Packer passes the same two values in the environment instead.
versions="$(dirname "$0")/../../versions.env"
if [ -z "${GOSS_VERSION:-}" ] && [ -r "$versions" ]; then
    while IFS='=' read -r key value; do
        case "$key" in
            GOSS_VERSION) GOSS_VERSION="$value" ;;
            GOSS_SHA256)  GOSS_SHA256="$value" ;;
        esac
    done < <(grep -E '^GOSS_[A-Z0-9_]+=' "$versions")
fi
: "${GOSS_VERSION:?not set and no versions.env found}"
: "${GOSS_SHA256:?not set and no versions.env found}"

if [ ! -r "$vars" ]; then
    echo "error: $vars not found." >&2
    echo "roles/manifest writes it at the end of a converge -- run \`make apply\` first." >&2
    exit 1
fi

# A fresh directory, removed on every exit path, so the test binary never
# outlives the run -- above all inside the image, where it would ship.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "==> Fetching goss ${GOSS_VERSION}"
curl -fsSL -o "$work/goss" \
  "https://github.com/goss-org/goss/releases/download/${GOSS_VERSION}/goss-linux-amd64"
# Verified like every other pinned download here: a release URL alone proves
# nothing about what it served.
echo "${GOSS_SHA256}  $work/goss" | sha256sum --check --quiet -
chmod +x "$work/goss"

echo "==> Validating $(basename "$suite") against $vars"
"$work/goss" --gossfile "$suite" --vars "$vars" \
  validate --format documentation --max-concurrent 4
