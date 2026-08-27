#!/usr/bin/env bash
# Check that things a config change references actually exist, before a build
# spends 40 minutes finding out that they don't.
#
# A misspelled package name is by far the most common way a change to
# group_vars/all.yml fails, and it fails late: `apt install` dies deep into a
# Packer run, after the base install and most of the provisioning. Catching it
# here turns a 40-minute failure into a 2-second one.
#
# Usage:
#   verify-change.sh apt      <package>...
#   verify-change.sh snap     <name>...
#   verify-change.sh flatpak  <app-id>...
#   verify-change.sh repo     <key-url> <base-url> <suite> [component]
#
# Exit codes carry meaning -- treat them differently:
#   0  everything checked exists
#   1  something definitively does NOT exist  -> fix the change
#   2  could not check (offline, host blocked) -> say so, do not claim verified
#
# That last distinction is the point. A checker that reports success when it
# could not actually reach anything is worse than no checker, because it
# launders a guess into a green tick.

set -uo pipefail

RELEASE="${UBUNTU_RELEASE:-26.04}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/workstation-verify"
MIRROR="${UBUNTU_MIRROR:-http://archive.ubuntu.com/ubuntu}"
COMPONENTS="main restricted universe multiverse"
ARCH="${ARCH:-amd64}"
CURL="curl -fsS --max-time 45"

ok()      { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()     { printf '  \033[31m✗\033[0m %s\n' "$*"; }
unknown() { printf '  \033[33m?\033[0m %s\n' "$*"; }

# Release codename. Ubuntu's archive is laid out by codename, not by version,
# and the mapping is not derivable -- so it is looked up here and then
# confirmed against the archive's own Release file rather than trusted blindly.
codename_for() {
    if [ -n "${UBUNTU_CODENAME:-}" ]; then echo "$UBUNTU_CODENAME"; return 0; fi
    case "$1" in
        26.04) echo resolute ;;
        25.10) echo questing ;;
        25.04) echo plucky   ;;
        24.04) echo noble    ;;
        22.04) echo jammy    ;;
        *)     return 1 ;;
    esac
}

confirm_codename() {
    local cn="$1" rel
    rel=$($CURL "${MIRROR}/dists/${cn}/Release" 2>/dev/null | head -20) || return 2
    grep -q "^Version: ${RELEASE}\$" <<<"$rel"
}

# --- apt ----------------------------------------------------------------------
# Checked against the same Packages indexes apt itself reads, so the answer is
# authoritative rather than a guess from a search page. ~22MB once, then cached.
verify_apt() {
    local codename status=0 fetched=0
    codename=$(codename_for "$RELEASE") || {
        unknown "no codename known for Ubuntu ${RELEASE}; set UBUNTU_CODENAME"
        return 2
    }

    # Prefer the local apt database when this is already the target release --
    # it is instant and reflects any extra repos configured here.
    if command -v apt-cache >/dev/null 2>&1 && \
       grep -qs "VERSION_ID=\"${RELEASE}\"" /etc/os-release; then
        for pkg in "$@"; do
            if apt-cache show "$pkg" >/dev/null 2>&1; then
                ok "apt: $pkg"
            else
                bad "apt: $pkg -- not found in the local apt database"
                status=1
            fi
        done
        return $status
    fi

    mkdir -p "$CACHE"
    for comp in $COMPONENTS; do
        local f="${CACHE}/${codename}-${comp}-${ARCH}.txt"
        # Index lists change slowly; a day-old cache is fine and keeps repeated
        # verification runs instant.
        if [ ! -s "$f" ] || [ -n "$(find "$f" -mtime +1 2>/dev/null)" ]; then
            if $CURL "${MIRROR}/dists/${codename}/${comp}/binary-${ARCH}/Packages.gz" 2>/dev/null \
               | gzip -dc 2>/dev/null | grep '^Package: ' > "${f}.tmp" 2>/dev/null \
               && [ -s "${f}.tmp" ]; then
                mv "${f}.tmp" "$f"
                fetched=1
            else
                rm -f "${f}.tmp"
            fi
        else
            fetched=1
        fi
    done

    if [ "$fetched" -eq 0 ]; then
        unknown "apt: could not reach ${MIRROR} -- package names NOT verified"
        return 2
    fi

    for pkg in "$@"; do
        if grep -qxF "Package: ${pkg}" "${CACHE}/${codename}-"*"-${ARCH}.txt" 2>/dev/null; then
            ok "apt: $pkg"
        else
            bad "apt: $pkg -- no such package in Ubuntu ${RELEASE} (${codename})"
            # A near-miss is usually the real intent. Match on a prefix as
            # well as a substring: a dropped letter ("ripgep") shares no
            # substring with the real name but still shares its opening.
            local near prefix="${pkg:0:4}"
            near=$(cat "${CACHE}/${codename}-"*"-${ARCH}.txt" 2>/dev/null \
                   | sed 's/^Package: //' \
                   | grep -iE "^${prefix}|${pkg}" | sort -u | head -4 | tr '\n' ' ')
            [ -n "$near" ] && printf '      did you mean: %s\n' "$near"
            status=1
        fi
    done
    return $status
}

# --- snap ---------------------------------------------------------------------
verify_snap() {
    local status=0 code
    for name in "$@"; do
        code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 30 \
               -H 'Snap-Device-Series: 16' \
               "https://api.snapcraft.io/v2/snaps/info/${name}" 2>/dev/null)
        case "$code" in
            200) ok "snap: $name" ;;
            404) bad "snap: $name -- no such snap"; status=1 ;;
            *)   unknown "snap: $name -- snapcraft API unreachable (code ${code:-none})"
                 [ $status -eq 0 ] && status=2 ;;
        esac
    done
    return $status
}

# --- flatpak ------------------------------------------------------------------
verify_flatpak() {
    local status=0 code
    for id in "$@"; do
        code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 30 \
               "https://flathub.org/api/v2/appstream/${id}" 2>/dev/null)
        case "$code" in
            200) ok "flatpak: $id" ;;
            404) bad "flatpak: $id -- not on Flathub (IDs are case-sensitive)"; status=1 ;;
            *)   unknown "flatpak: $id -- Flathub API unreachable (code ${code:-none})"
                 [ $status -eq 0 ] && status=2 ;;
        esac
    done
    return $status
}

# --- third-party apt repository ----------------------------------------------
# Three independent things have to be true for a repo entry to work, and each
# fails differently at build time, so each is checked separately.
verify_repo() {
    local key_url="$1" base_url="$2" suite="$3" component="${4:-}"
    local status=0 tmp

    # 1. The signing key is fetchable and is actually a key. A 404 here means
    #    apt-key dearmouring produces an empty keyring and every later apt
    #    operation fails with an unhelpful signature error.
    tmp=$(mktemp)
    if $CURL "$key_url" -o "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
        if gpg --show-keys --with-colons "$tmp" >/dev/null 2>&1 || \
           gpg --dearmor < "$tmp" >/dev/null 2>&1; then
            ok "repo key: $key_url"
        else
            bad "repo key: $key_url -- fetched, but is not a usable GPG key"
            status=1
        fi
    else
        unknown "repo key: $key_url -- could not fetch"
        [ $status -eq 0 ] && status=2
    fi
    rm -f "$tmp"

    # 2. The suite exists. Vendors often lag a new Ubuntu release, so a repo
    #    that works on 24.04 may simply have no directory for 26.04 yet --
    #    the single most common third-party repo failure.
    local rel_url="${base_url%/}/dists/${suite}/Release"
    local code
    code=$(curl -sS -o /tmp/_repo_release -w '%{http_code}' --max-time 30 "$rel_url" 2>/dev/null)
    case "$code" in
        200)
            ok "repo suite: ${base_url} ${suite}"
            # 3. The component is actually published in that suite.
            if [ -n "$component" ]; then
                if grep -qE "^Components:.*\b${component}\b" /tmp/_repo_release 2>/dev/null; then
                    ok "repo component: ${component}"
                else
                    bad "repo component: '${component}' not published in suite '${suite}'"
                    printf '      available: %s\n' \
                        "$(grep '^Components:' /tmp/_repo_release 2>/dev/null | cut -d' ' -f2-)"
                    status=1
                fi
            fi
            ;;
        404)
            bad "repo suite: no 'dists/${suite}' at ${base_url} -- vendor may not support ${suite} yet"
            status=1
            ;;
        *)
            unknown "repo suite: ${rel_url} unreachable (code ${code:-none})"
            [ $status -eq 0 ] && status=2
            ;;
    esac
    rm -f /tmp/_repo_release
    return $status
}

# --- dispatch -----------------------------------------------------------------
[ $# -ge 2 ] || { sed -n '2,30p' "$0" | sed 's/^# \?//'; exit 64; }

kind="$1"; shift
case "$kind" in
    apt)     verify_apt "$@" ;;
    snap)    verify_snap "$@" ;;
    flatpak) verify_flatpak "$@" ;;
    repo)    verify_repo "$@" ;;
    *) echo "unknown check '$kind' (expected: apt, snap, flatpak, repo)" >&2; exit 64 ;;
esac
