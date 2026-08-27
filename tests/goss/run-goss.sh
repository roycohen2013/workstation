#!/usr/bin/env bash
# Downloads goss and runs the image assertions from inside the build VM.
#
# goss is a single static binary with YAML assertions, which is why it is used
# here rather than testinfra: it needs no Python, no pip, and leaves nothing
# behind in the image once this script removes it.
set -euo pipefail

GOSS_VERSION="${GOSS_VERSION:-v0.4.9}"
GOSS_FILE="${GOSS_FILE:-/tmp/goss/workstation.yaml}"
GOSS_BIN=/tmp/goss/goss

echo "==> Fetching goss ${GOSS_VERSION}"
curl -fsSL -o "$GOSS_BIN" \
  "https://github.com/goss-org/goss/releases/download/${GOSS_VERSION}/goss-linux-amd64"
chmod +x "$GOSS_BIN"

# The gossfile is templated; give it the account name the image was built for
# instead of duplicating that setting in the test suite.
# shellcheck disable=SC1091
. /etc/workstation-release
export WS_USER="${WORKSTATION_USER:?/etc/workstation-release did not define WORKSTATION_USER}"

echo "==> Validating image against ${GOSS_FILE} (user=${WS_USER})"
# `|| status=$?` rather than a bare call: with `set -e` a failing goss run
# would exit here and skip the cleanup below, leaving the test binary behind
# in the image on exactly the runs where something went wrong.
status=0
"$GOSS_BIN" --gossfile "$GOSS_FILE" validate --format documentation --max-concurrent 4 || status=$?

echo "==> Removing test tooling from the image"
rm -rf /tmp/goss

exit "$status"
