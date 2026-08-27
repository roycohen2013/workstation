#!/usr/bin/env python3
"""Record what is actually installed in this image.

Runs inside the image, immediately before roles/seal. That position matters:
seal deletes /var/lib/apt/lists, and those lists are the only way to say which
repository a package came from. Run this after seal and the origin column goes
quietly empty rather than failing, which is the worst kind of broken.

Writes /etc/workstation-manifest.json. The file stays in the image on purpose --
a running machine should be able to answer "what am I?" without the build output
that produced it.

Every collector degrades to an empty result rather than raising: a missing
flatpak binary or an unreadable dconf must not fail an image build over
documentation.
"""
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

APT_LISTS = Path("/var/lib/apt/lists")


def run(cmd, **kw):
    """Run a command, returning stdout or '' on any failure."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=120, **kw)
        return r.stdout if r.returncode == 0 else ""
    except Exception:
        return ""


def apt_packages():
    """Installed packages with version, size and summary."""
    fmt = ("${Package}\\t${Version}\\t${Architecture}\\t${Installed-Size}"
           "\\t${Provides}\\t${binary:Summary}\\n")
    out = run(["dpkg-query", "-W", "-f=" + fmt])
    pkgs = {}
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) < 4 or not parts[0]:
            continue
        name, version, arch, size = parts[0], parts[1], parts[2], parts[3]
        provides = parts[4] if len(parts) > 4 else ""
        pkgs[name] = {
            "name": name,
            "version": version,
            "arch": arch,
            # Installed-Size is in KiB and is blank for some virtual entries.
            "size_kb": int(size) if size.strip().isdigit() else 0,
            # Virtual names this package satisfies. The drift check needs these:
            # declaring a virtual name is legitimate, and without Provides the
            # check would report a package as missing that is plainly installed.
            "provides": [x.split()[0] for x in provides.split(",") if x.strip()],
            "summary": parts[5] if len(parts) > 5 else "",
        }
    return pkgs


def manual_set():
    """Packages apt considers explicitly requested, not pulled in as a dependency.

    This is the single most useful distinction in the whole manifest: it is what
    separates software we asked for from software that arrived via Recommends.
    """
    return {p.strip() for p in run(["apt-mark", "showmanual"]).splitlines() if p.strip()}


def index_targets():
    """Enumerate apt's package indexes with their metadata.

    Uses apt's own view rather than globbing /var/lib/apt/lists. Two reasons:
    modern apt stores those lists lz4-compressed, so a naive *_Packages glob
    matches nothing at all (and reports an empty origin column while insisting
    the lists are present); and indextargets carries real Component/Base-URI
    fields instead of guesses parsed out of a mangled filename.
    """
    out = run(["apt-get", "indextargets", "--no-release-info"])
    targets, cur = [], {}
    for line in out.splitlines():
        if not line.strip():
            if cur:
                targets.append(cur)
                cur = {}
            continue
        if ": " in line:
            k, v = line.split(": ", 1)
            cur[k.strip()] = v.strip()
    if cur:
        targets.append(cur)
    return [t for t in targets if t.get("Created-By") == "Packages"]


def read_index(filename):
    """Read an apt index, whatever compression it uses.

    apt-helper handles every format apt itself writes; shelling out to it beats
    keeping our own list of suffixes in sync with apt's CompressionTypes.
    """
    candidates = [filename] + [filename + ext
                               for ext in (".lz4", ".gz", ".xz", ".zst", ".bz2")]
    helper = "/usr/lib/apt/apt-helper"
    for path in candidates:
        if not os.path.exists(path):
            continue
        if os.path.exists(helper):
            data = run([helper, "cat-file", path])
            if data:
                return data
        try:
            return Path(path).read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
    return ""


def origin_map(interesting):
    """Map package -> origin repository.

    Resolved only for the packages passed in (the manual set). Doing it for all
    ~2000 installed packages means reading every index to no benefit -- nobody
    asks which repo libc6 came from.
    """
    origins = {}
    for t in index_targets():
        filename = t.get("Filename", "")
        if not filename:
            continue
        # "https://host/path suite/component amd64 Packages" -> "host suite/component"
        desc = t.get("Description", "")
        m = re.match(r"https?://([^/\s]+)\S*\s+(\S+)", desc)
        label = f"{m.group(1)} {m.group(2)}" if m else desc or filename
        for line in read_index(filename).splitlines():
            if line.startswith("Package: "):
                name = line[9:].strip()
                if name in interesting and name not in origins:
                    origins[name] = label
    return origins


def snaps():
    out = run(["snap", "list"])
    items = []
    for line in out.splitlines()[1:]:
        f = line.split()
        if len(f) >= 4:
            items.append({"name": f[0], "version": f[1], "channel": f[3]})
    return items


def flatpaks():
    out = run(["flatpak", "list", "--app", "--columns=application,version,branch"])
    items = []
    for line in out.splitlines():
        f = [c.strip() for c in line.split("\t")]
        if f and f[0]:
            items.append({
                "id": f[0],
                "version": f[1] if len(f) > 1 else "",
                "branch": f[2] if len(f) > 2 else "",
            })
    return items


def enabled_units():
    out = run(["systemctl", "list-unit-files", "--state=enabled", "--no-legend", "--no-pager"])
    return sorted({ln.split()[0] for ln in out.splitlines() if ln.split()})


def dconf_settings():
    # dconf needs a session bus; inside a build VM there is none, so this is
    # expected to come back empty. The configured values are still visible in
    # the config snapshot rendered from group_vars.
    out = run(["dconf", "dump", "/"])
    return out if out.strip() else ""


def firewall():
    out = run(["ufw", "status"])
    return [ln.strip() for ln in out.splitlines()
            if "ALLOW" in ln or "DENY" in ln]


def os_release():
    info = {}
    try:
        for line in Path("/etc/os-release").read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                info[k] = v.strip().strip('"')
    except OSError:
        pass
    return info


def image_release():
    """Whatever roles/seal has already recorded, so the two never disagree."""
    info = {}
    p = Path("/etc/workstation-release")
    if p.exists():
        for line in p.read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                info[k] = v.strip()
    return info


def root_usage_mb():
    try:
        st = os.statvfs("/")
        return round((st.f_blocks - st.f_bfree) * st.f_frsize / 1048576)
    except OSError:
        return 0


def main():
    dest = sys.argv[1] if len(sys.argv) > 1 else "/etc/workstation-manifest.json"

    pkgs = apt_packages()
    manual = manual_set() & set(pkgs)
    origins = origin_map(manual)

    for name, p in pkgs.items():
        p["manual"] = name in manual
        p["origin"] = origins.get(name, "")

    osr = os_release()
    rel = image_release()

    manifest = {
        "schema": 1,
        "image": {
            "version": rel.get("WORKSTATION_VERSION", "unknown"),
            "build_date": rel.get("WORKSTATION_BUILD_DATE", "unknown"),
            "user": rel.get("WORKSTATION_USER", ""),
            "distribution": f"{osr.get('NAME', '')} {osr.get('VERSION_ID', '')}".strip(),
            "codename": osr.get("VERSION_CODENAME", ""),
            "kernel": run(["uname", "-r"]).strip(),
            "root_used_mb": root_usage_mb(),
        },
        "packages": {
            "apt": sorted(pkgs.values(), key=lambda p: p["name"]),
            "snap": snaps(),
            "flatpak": flatpaks(),
        },
        # Every name that counts as "installed" for a dependency or a
        # declaration: real package names plus the virtual names they provide.
        "satisfied_names": sorted(
            set(pkgs) | {v for p in pkgs.values() for v in p["provides"]}
        ),
        "counts": {
            "apt_total": len(pkgs),
            "apt_manual": len(manual),
            "apt_auto": len(pkgs) - len(manual),
        },
        "services_enabled": enabled_units(),
        "firewall": firewall(),
        "dconf": dconf_settings(),
        "tooling": {
            "snap_present": shutil.which("snap") is not None,
            "flatpak_present": shutil.which("flatpak") is not None,
            # Not "does the lists dir exist" -- it can be full of files we
            # cannot read. Report whether origins actually resolved, which is
            # the thing a reader would otherwise have to infer from silence.
            "apt_indexes_readable": len(origins) > 0,
            "origins_resolved": len(origins),
        },
    }

    Path(dest).write_text(json.dumps(manifest, indent=2, sort_keys=False) + "\n")
    c = manifest["counts"]
    print(f"wrote {dest}: {c['apt_total']} apt "
          f"({c['apt_manual']} manual, {c['apt_auto']} auto), "
          f"{len(manifest['packages']['snap'])} snap, "
          f"{len(manifest['packages']['flatpak'])} flatpak")
    if not origins and manual:
        print("WARNING: no package origins resolved -- apt indexes were "
              "unreadable. This role must run BEFORE roles/seal, which deletes "
              "/var/lib/apt/lists.", file=sys.stderr)


if __name__ == "__main__":
    main()
