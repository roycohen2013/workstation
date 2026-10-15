#!/usr/bin/env bash
# Managed by Ansible (roles/desktop, files/workstation-desktop-info.sh).
# Stamps hostname and primary IP onto a copy of the base wallpaper and sets it
# as the background. Run by the workstation-desktop-info user timer.
#
# A plain file rather than a template, so shellcheck and
# tests/scripts/test-desktop-info.sh reach it. Its settings come from
# /etc/default/workstation-desktop-info, which roles/desktop writes from the
# desktop_info_* variables in group_vars; WORKSTATION_DESKTOP_INFO_CONF points
# elsewhere for the test.
#
# ImageMagick 7 renames the CLI: the command is `magick`, not `convert`.
set -euo pipefail

CONF="${WORKSTATION_DESKTOP_INFO_CONF:-/etc/default/workstation-desktop-info}"
# shellcheck source=/dev/null
. "$CONF"
: "${BASE:?not set in $CONF}" "${FONT:?not set in $CONF}" "${POINTSIZE:?not set in $CONF}"
: "${INSET:?not set in $CONF}" "${GRAVITY:?not set in $CONF}"

OUT_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/workstation"
OUT="$OUT_DIR/desktop-info.png"
STAMP="$OUT_DIR/desktop-info.txt"

[ -r "$BASE" ] || { echo "base wallpaper missing: $BASE" >&2; exit 1; }

host=$(hostname)
# Source address of the route that actually carries traffic -- not
# `hostname -I`, which lists every address including docker0 and returns
# them in no dependable order.
# `|| ip=""` for the same reason as `|| geom=""` below: with no route at all
# -- offline, Wi-Fi not yet up -- `ip route get` exits 2, and under pipefail
# the assignment would abort the script before the "no network" fallback on
# the next line could ever run.
ip=$(ip -4 route get 1.1.1.1 2>/dev/null \
       | awk '{for (i = 1; i <= NF; i++) if ($i == "src") {print $(i + 1); exit}}') || ip=""
[ -n "$ip" ] || ip="no network"
text="$host
$ip"

# Fit the canvas to the screen BEFORE drawing, or the text gets cropped
# off. GNOME's picture-options is 'zoom', which scales the wallpaper to
# FILL the display and discards the overflow: a 3840x2160 image on a
# 3840x2400 screen is scaled to 4267x2400 and loses 213px from each side.
# Text inset 40px from an edge therefore lands ~170px inside the
# discarded region and is never seen -- which is exactly what happened.
#
# Producing the image at the screen's own resolution makes zoom a no-op:
# same aspect, scale 1.0, nothing cropped, so the inset below means what
# it says. xrandr reports the XWayland screen, which GNOME always runs;
# if it is unavailable the base image's own size is used, which is no
# worse than before.
# `|| geom=""` is load-bearing. Under `set -euo pipefail` a bare
# assignment from a failing pipeline aborts the script, so without it
# the fallback below is unreachable: on a machine with no xrandr --
# which nothing in this repo installs -- the renderer would exit 127
# every time the timer fired and the wallpaper would never be stamped
# at all, which is worse than the cropping this change set out to fix.
# The case guard covers the same ground for a malformed reading.
geom=$(xrandr --current 2>/dev/null | awk '/\*/ {print $1; exit}') || geom=""
case "$geom" in
    [0-9]*x[0-9]*) ;;
    *) geom=$(magick identify -format '%wx%h' "$BASE") ;;
esac

mkdir -p "$OUT_DIR"

# Re-render only when the text actually changed. Without this the timer
# rewrites a multi-megabyte PNG every couple of minutes and re-sets the
# background, which makes the desktop flicker for no reason.
if [ -f "$OUT" ] && [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$text" ]; then
    exit 0
fi

tmp=$(mktemp "$OUT_DIR/.desktop-info.XXXXXX.png")
trap 'rm -f "$tmp"' EXIT
# Drawn twice: a dark copy offset by two pixels, then the light text over
# it, so it stays readable on a pale wallpaper as well as a dark one.
magick "$BASE" \
    -resize "${geom}^" -gravity center -extent "$geom" \
    -font "$FONT" -pointsize "$POINTSIZE" -gravity "$GRAVITY" \
    -fill '#000000A0' -annotate +$((INSET + 2))+$((INSET + 2)) "$text" \
    -fill white       -annotate "+${INSET}+${INSET}" "$text" \
    "$tmp"
mv "$tmp" "$OUT"
printf '%s' "$text" > "$STAMP"

gsettings set org.gnome.desktop.background picture-uri "file://$OUT"
gsettings set org.gnome.desktop.background picture-uri-dark "file://$OUT"
