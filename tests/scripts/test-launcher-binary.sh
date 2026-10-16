#!/usr/bin/env bash
# Tests ansible/roles/apps/files/launcher-binary.sh, which finds the binary a
# package's desktop launcher runs. roles/apps wraps that binary with
# --no-sandbox and the image test checks the wrapper through the same script,
# so a wrong answer here breaks both silently. Run with `make test-scripts`.
set -euo pipefail

script="$(cd "$(dirname "$0")/../.." && pwd)/ansible/roles/apps/files/launcher-binary.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0

pass() { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }

stubs="$work/bin"
mkdir -p "$stubs" "$work/opt/app"
# dpkg -L <pkg> lists $work/<pkg>.files, or fails as dpkg does for an unknown package.
cat > "$stubs/dpkg" <<S
#!/bin/sh
[ "\$1" = -L ] && [ -f "$work/\$2.files" ] && exec cat "$work/\$2.files"
exit 1
S
chmod +x "$stubs/dpkg"

# The real binary, reached through a symlink on PATH, as electron apps install.
printf '#!/bin/sh\n' > "$work/opt/app/real-app"
chmod +x "$work/opt/app/real-app"
ln -s "$work/opt/app/real-app" "$stubs/app"

package() {  # package <name> <Exec= line or "-" for none>
    printf '%s\n' "/usr/share/doc/$1" "$work/$1.desktop" > "$work/$1.files"
    { echo "[Desktop Entry]"; [ "$2" = - ] || echo "Exec=$2"; } > "$work/$1.desktop"
}

resolve() { PATH="$stubs:$PATH" bash "$script" "$1" 2>"$work/err"; }

echo "launcher-binary"

package rel "app --flag %U"
if [ "$(resolve rel)" = "$work/opt/app/real-app" ]; then
    pass "resolves a launcher command on PATH through its symlink"
else
    fail "resolves a command on PATH"
fi

package abs "$work/opt/app/real-app %U"
if [ "$(resolve abs)" = "$work/opt/app/real-app" ]; then
    pass "resolves an absolute launcher path"
else
    fail "resolves an absolute path"
fi

if ! resolve unknown >/dev/null && grep -q 'installs no .desktop launcher' "$work/err"; then
    pass "fails, saying why, for a package with no launcher"
else
    fail "fails for a package with no launcher"
fi

package noexec -
if ! resolve noexec >/dev/null && grep -q 'has no Exec= line' "$work/err"; then
    pass "fails, saying why, for a launcher with no Exec= line"
else
    fail "fails for a launcher with no Exec= line"
fi

package gone "not-installed-anywhere --x"
if ! resolve gone >/dev/null && grep -q 'is not on PATH' "$work/err"; then
    pass "fails, saying why, when the launcher's command is not installed"
else
    fail "fails when the command is not installed"
fi

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
