#!/usr/bin/env bash
# Tests ansible/roles/desktop/files/workstation-desktop-info.sh, the wallpaper
# stamp renderer, with every external command it calls replaced by a stub on
# PATH. Run with `make test-scripts`.
#
# The case that matters most is the first fallback: with no usable xrandr the
# renderer must still stamp the wallpaper at the base image's own size. Under
# set -euo pipefail that depends on a single `|| geom=""`, and until this test
# existed the only way to find out it had gone missing was a real screen.
set -euo pipefail

script="$(cd "$(dirname "$0")/../.." && pwd)/ansible/roles/desktop/files/workstation-desktop-info.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0

pass() { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }

# --- Stubs ------------------------------------------------------------------
# Each logs its arguments to $LOG, one call per line.
stubs="$work/bin"
mkdir -p "$stubs"
cat > "$stubs/hostname" <<'S'
#!/bin/sh
echo testhost
S
# IP_MODE=offline answers as `ip route get` does with no route to anywhere.
cat > "$stubs/ip" <<'S'
#!/bin/sh
if [ "$IP_MODE" = offline ]; then
    echo "RTNETLINK answers: Network is unreachable" >&2
    exit 2
fi
echo "1.1.1.1 via 10.0.0.1 dev eth0 src 10.0.0.5 uid 0"
S
# XRANDR_MODE picks the behaviour: a geometry to report, or "missing".
cat > "$stubs/xrandr" <<'S'
#!/bin/sh
echo "xrandr $*" >> "$LOG"
[ "$XRANDR_MODE" = missing ] && exit 127
echo "Screen 0: minimum 16 x 16, current $XRANDR_MODE"
echo "   $XRANDR_MODE     60.00*+"
S
cat > "$stubs/magick" <<'S'
#!/bin/sh
echo "magick $*" >> "$LOG"
if [ "$1" = identify ]; then echo 1920x1080; exit 0; fi
for last; do :; done
: > "$last"
S
cat > "$stubs/gsettings" <<'S'
#!/bin/sh
echo "gsettings $*" >> "$LOG"
S
chmod +x "$stubs"/*

conf="$work/desktop-info.conf"
touch "$work/base.png"
cat > "$conf" <<C
BASE=$work/base.png
FONT=/fonts/Mono.ttf
POINTSIZE=32
INSET=60
GRAVITY=NorthEast
C

run() {
    LOG="$work/log" XRANDR_MODE="$1" IP_MODE="${IP_MODE:-online}" HOME="$work/home" XDG_CACHE_HOME="" \
        WORKSTATION_DESKTOP_INFO_CONF="$2" PATH="$stubs:$PATH" \
        bash "$script" >"$work/out" 2>&1
}

echo "workstation-desktop-info"

# 1. The screen's geometry sizes the canvas, so GNOME's zoom crops nothing.
: > "$work/log"
if run 2560x1440 "$conf" \
   && grep -q -- '-resize 2560x1440^ .*-extent 2560x1440' "$work/log" \
   && grep -q -- '-gravity NorthEast' "$work/log" \
   && grep -q -- '-annotate +60+60 testhost' "$work/log" \
   && [ "$(grep -c '^gsettings set' "$work/log")" = 2 ] \
   && [ -f "$work/home/.cache/workstation/desktop-info.png" ]; then
    pass "renders at the screen's geometry and sets both backgrounds"
else
    fail "renders at the screen's geometry"; cat "$work/out" "$work/log"
fi

# 2. Unchanged text: nothing is re-rendered, so the desktop does not flicker.
: > "$work/log"
if run 2560x1440 "$conf" && ! grep -q '^magick' "$work/log" && ! grep -q '^gsettings' "$work/log"; then
    pass "skips re-rendering when hostname and IP are unchanged"
else
    fail "skips re-rendering when unchanged"; cat "$work/out" "$work/log"
fi

# 3. No usable xrandr: falls back to the base image's own size.
rm -rf "${work:?}/home"; : > "$work/log"
if run missing "$conf" \
   && grep -q '^magick identify' "$work/log" \
   && grep -q -- '-resize 1920x1080^' "$work/log"; then
    pass "falls back to the base image's size when xrandr fails"
else
    fail "falls back when xrandr fails (the || geom=\"\" guard)"; cat "$work/out" "$work/log"
fi

# 4. No route to anywhere -- offline, Wi-Fi not yet up -- stamps "no network".
# `ip route get` exits 2 there, which under pipefail used to abort the script
# before its own "no network" fallback could run, every time the timer fired.
rm -rf "${work:?}/home"; : > "$work/log"
if IP_MODE=offline run 2560x1440 "$conf" && grep -q -- '-annotate +60+60 testhost' "$work/log" \
   && grep -q 'no network' "$work/home/.cache/workstation/desktop-info.txt"; then
    pass "stamps \"no network\" when there is no route"
else
    fail "stamps \"no network\" when there is no route"; cat "$work/out"
fi

# 5. A missing base wallpaper is an error with the path in it, not a blank stamp.
rm -f "$work/base.png"
if ! run 2560x1440 "$conf" && grep -q "base wallpaper missing: $work/base.png" "$work/out"; then
    pass "fails, naming the path, when the base wallpaper is missing"
else
    fail "fails when the base wallpaper is missing"; cat "$work/out"
fi
touch "$work/base.png"

# 6. A settings file missing a key fails on start, naming the key.
grep -v '^GRAVITY=' "$conf" > "$work/partial.conf"
if ! run 2560x1440 "$work/partial.conf" && grep -q 'GRAVITY' "$work/out"; then
    pass "fails, naming the key, when a setting is missing"
else
    fail "fails when a setting is missing"; cat "$work/out"
fi

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
