#!/usr/bin/env bash
# Managed by Ansible (roles/apps, files/launcher-binary.sh).
#
#   launcher-binary <package>
#
# Prints the real path of the binary a package's desktop launcher runs: the
# first word of the Exec= line in the first .desktop file the package
# installs, looked up on PATH if it is not absolute, with symlinks resolved.
#
# Discovered rather than hard-coded because electron-builder's install layout
# has moved between releases, and a guessed path that turned out wrong would
# silently skip whatever needed the binary. roles/apps uses it to place the
# BalenaEtcher --no-sandbox wrapper, and the image test in
# tests/goss/features.goss.tmpl uses the same script to check it, so the two
# cannot disagree about which file is the binary.
#
# Exits 1, with the reason on stderr, when any step finds nothing.
set -euo pipefail

pkg="${1:?usage: launcher-binary <package>}"

desktop=$(dpkg -L "$pkg" 2>/dev/null | grep -E '\.desktop$' | head -1) || true
[ -n "$desktop" ] || { echo "$pkg installs no .desktop launcher" >&2; exit 1; }

exec_line=$(grep -m1 '^Exec=' "$desktop" | sed 's/^Exec=//') || true
cmd="${exec_line%% *}"
[ -n "$cmd" ] || { echo "$desktop has no Exec= line" >&2; exit 1; }

case "$cmd" in
    /*) bin="$cmd" ;;
    *)  bin=$(command -v "$cmd") || { echo "$cmd (from $desktop) is not on PATH" >&2; exit 1; } ;;
esac
readlink -f "$bin"
