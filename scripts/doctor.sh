#!/usr/bin/env bash
# Preflight: does this machine still match what the repo assumes?
#
# Every failure this repo has hit in practice was environment drift rather than
# broken config -- Ubuntu replaced sudo with sudo-rs, a vendor moved its
# keyring path, a collection release removed a plugin, a tool dropped a flag.
# None of those are visible by reading the repo, and most surface deep inside a
# 40-minute build or after a password prompt that silently never matched.
#
# This checks the assumptions directly, in seconds. FAIL means something will
# break; WARN means something is degraded but usable.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 1

if [ -t 1 ]; then
    R=$'\033[31m'; Y=$'\033[33m'; G=$'\033[32m'; B=$'\033[1m'; N=$'\033[0m'
else
    R=""; Y=""; G=""; B=""; N=""
fi

fails=0
warns=0

section() { printf '\n%s%s%s\n' "$B" "$1" "$N"; }
ok()   { printf '  %sok%s    %s\n' "$G" "$N" "$1"; }
warn() { printf '  %swarn%s  %s\n' "$Y" "$N" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; warns=$((warns + 1)); }
fail() { printf '  %sFAIL%s  %s\n' "$R" "$N" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fails=$((fails + 1)); }

# --- Tools --------------------------------------------------------------------
# Split by consequence: without the first group you cannot build at all, so a
# miss is a failure. The second only gates `make lint`, so a miss is a warning
# -- reporting it as fatal would make doctor useless on a machine that only
# ever runs `make fetch` and `make flash`.
section "Tools"

for t in packer qemu-img ansible-playbook git curl; do
    if command -v "$t" >/dev/null 2>&1; then
        ok "$t"
    else
        fail "$t is missing" "needed to build. See the Requirements section of README.md"
    fi
done

for t in yamllint ansible-lint shellcheck terraform terraform-docs docsible xorriso; do
    if command -v "$t" >/dev/null 2>&1; then
        ok "$t"
    else
        warn "$t is missing" "\`make lint\` or \`make iso\` needs it -- run \`make apply\` to install"
    fi
done

# --- Pinned tool versions -----------------------------------------------------
# versions.env is what CI installs. A local mismatch is not an error -- you are
# allowed a newer packer than CI -- but it explains the class of bug where a
# build passes on one and fails on the other, which is otherwise baffling.
section "Tool versions vs CI pins"

if [ -f versions.env ]; then
    pinned_packer="$(sed -n 's/^PACKER_VERSION=//p' versions.env)"
    pinned_tf="$(sed -n 's/^TERRAFORM_VERSION=//p' versions.env)"
    if command -v packer >/dev/null 2>&1 && [ -n "$pinned_packer" ]; then
        have="$(packer version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
        if [ "$have" = "$pinned_packer" ]; then
            ok "packer $have matches the CI pin"
        else
            warn "packer $have locally, CI pins $pinned_packer" \
                "not fatal, but differences here explain 'works locally, fails in CI'"
        fi
    fi
    if command -v terraform >/dev/null 2>&1 && [ -n "$pinned_tf" ]; then
        have="$(terraform version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
        if [ "$have" = "$pinned_tf" ]; then
            ok "terraform $have matches the CI pin"
        else
            warn "terraform $have locally, CI pins $pinned_tf" \
                "not fatal; see versions.env"
        fi
    fi
else
    warn "versions.env is missing" "CI reads its tool pins from it"
fi

# --- Virtualisation -----------------------------------------------------------
section "Virtualisation"

if [ ! -e /dev/kvm ]; then
    fail "/dev/kvm is missing" \
        "enable VT-x/AMD-V in firmware; on WSL2 set nestedVirtualization=true"
elif [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
    fail "/dev/kvm exists but is not accessible (group: $(stat -c %G /dev/kvm 2>/dev/null))" \
        "sudo usermod -aG kvm \$USER, then log out and back in"
else
    ok "/dev/kvm is accessible"
fi

# --- Privilege escalation -----------------------------------------------------
# The one that cost the most to diagnose. sudo-rs treats a caller-supplied -p
# prompt as untrusted and substitutes its own, so Ansible's become plugin never
# recognises the prompt and times out with a correct password. `make apply`
# routes around it via sudo.ws; this checks that escape hatch still exists.
section "Privilege escalation"

if ! command -v sudo >/dev/null 2>&1; then
    fail "sudo is missing" "\`make apply\` cannot escalate without it"
elif sudo --version 2>&1 | head -1 | grep -qi 'sudo-rs'; then
    if command -v sudo.ws >/dev/null 2>&1; then
        ok "sudo is sudo-rs; classic sudo.ws present, which \`make apply\` uses"
    else
        fail "sudo is sudo-rs and classic sudo.ws is not installed" \
            "\`make apply\` will time out waiting for a become prompt. See TROUBLESHOOTING.md"
    fi
else
    ok "sudo is the classic implementation"
fi

# --- Ansible collections ------------------------------------------------------
# requirements.yml caps community.general below 12.0.0 because 12.0.0 removed
# the callback plugin ansible.cfg used. The cap only helps if the version that
# actually loads is the pinned one: a system-wide copy in dist-packages can sit
# alongside the repo's own, and only the first on the search path is used.
section "Ansible collections"

if command -v ansible-galaxy >/dev/null 2>&1; then
    listing="$(ANSIBLE_CONFIG="$REPO/ansible.cfg" ansible-galaxy collection list 2>/dev/null)"
    while read -r name pin; do
        [ -n "$name" ] || continue
        # First match wins, mirroring Ansible's own search order.
        effective="$(printf '%s\n' "$listing" | awk -v n="$name" '$1 == n { print $2; exit }')"
        if [ -z "$effective" ]; then
            warn "$name is not installed" "run \`make deps\`"
            continue
        fi
        copies="$(printf '%s\n' "$listing" | awk -v n="$name" '$1 == n { print $2 }' | sort -u | wc -l)"
        upper="$(printf '%s' "$pin" | grep -o '<[0-9][0-9.]*' | tr -d '<')"
        # The cap is exclusive ("<12.0.0"), so equality must fail too -- and
        # 12.0.0 exactly is the version that removed the callback plugin, so
        # letting the boundary through would miss the one release this check
        # exists for. sort -V alone cannot express that; equality is tested
        # separately.
        over_cap=false
        if [ -n "$upper" ]; then
            if [ "$effective" = "$upper" ] ||
               [ "$(printf '%s\n%s\n' "$effective" "$upper" | sort -V | head -1)" != "$effective" ]; then
                over_cap=true
            fi
        fi
        if [ "$over_cap" = true ]; then
            fail "$name $effective is loaded but the pin is $pin" \
                "run \`make deps\`; a version above the cap has broken this repo before"
        elif [ "$copies" -gt 1 ]; then
            ok "$name $effective (pin $pin; other versions installed elsewhere are shadowed)"
        else
            ok "$name $effective (pin $pin)"
        fi
    done < <(awk '/^ *- name:/ { n = $3 } /^ *version:/ && n { gsub(/"/, "", $2); print n, $2; n = "" }' \
                 ansible/requirements.yml)
else
    warn "ansible-galaxy is missing, cannot check collection versions"
fi

# --- APT state ----------------------------------------------------------------
# A single origin declared twice with different signed-by paths makes apt
# refuse to read its source list at all -- every install fails, not just the
# offending repo. It happens whenever a vendor's documented install and this
# repo disagree on where the keyring lives.
section "APT sources"

if command -v apt-get >/dev/null 2>&1; then
    if apt-get indextargets >/dev/null 2>&1; then
        ok "apt can read its source list"
    else
        fail "apt cannot read its source list" \
            "run \`apt-get indextargets\` to see the error. See TROUBLESHOOTING.md"
    fi

    dupes="$(grep -rhoE '^deb .*' /etc/apt/sources.list.d/*.list /etc/apt/sources.list 2>/dev/null \
        | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^https?:/) url = $i
                 match($0, /signed-by=[^] ]*/)
                 key = (RSTART ? substr($0, RSTART + 10, RLENGTH - 10) : "none")
                 if (url) print url, key }' \
        | sort -u | awk '{ seen[$1]++ } END { for (u in seen) if (seen[u] > 1) print u }')"
    if [ -n "$dupes" ]; then
        fail "an origin is declared with more than one signed-by path:" "$dupes"
    else
        ok "no conflicting signed-by declarations"
    fi
else
    warn "apt-get is missing; skipping apt checks"
fi

# --- Disk ---------------------------------------------------------------------
# A build writes a raw image, a qcow2 and their compressed copies. Running out
# part-way wastes the whole run, and the failure reads as a compression error.
section "Disk"

avail_kb="$(df -Pk "$REPO" 2>/dev/null | awk 'NR == 2 { print $4 }')"
if [ -n "$avail_kb" ]; then
    avail_gb=$((avail_kb / 1024 / 1024))
    if [ "$avail_gb" -lt 25 ]; then
        warn "${avail_gb}G free where builds are written" \
            "a full \`make image\` wants roughly 25G; \`make clean\` frees old output"
    else
        ok "${avail_gb}G free for build output"
    fi
fi

# --- Summary ------------------------------------------------------------------
printf '\n'
if [ "$fails" -gt 0 ]; then
    printf '%s%d failure(s)%s, %d warning(s). Fix the failures before building.\n' \
        "$R" "$fails" "$N" "$warns"
    exit 1
fi
if [ "$warns" -gt 0 ]; then
    printf '%sNo failures%s, %d warning(s) -- usable, some targets may not run.\n' "$G" "$N" "$warns"
    exit 0
fi
printf '%sEverything checks out.%s\n' "$G" "$N"
