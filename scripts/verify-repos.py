#!/usr/bin/env python3
"""Check every third-party apt repository declared in group_vars.

Wraps .claude/skills/config-change/scripts/verify-change.sh so the repository
list comes from the config rather than from copy-pasted URLs that go stale the
moment a vendor is added.

It also substitutes {{ ansible_distribution_release }} in repo lines. Docker and
HashiCorp template the Ubuntu codename; checking those by hand means knowing
that 26.04 is "resolute", which is exactly the kind of detail worth not relying
on someone remembering.

  scripts/verify-repos.py [--codename resolute] [--only NAME]

Exit codes match verify-change.sh, aggregated over all repositories:
  0  every repository verified
  1  at least one is definitively wrong  -> fix it
  2  at least one could not be checked (blocked/offline), none wrong
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
VERIFY = REPO / ".claude" / "skills" / "config-change" / "scripts" / "verify-change.sh"
GROUP_VARS = REPO / "ansible" / "group_vars" / "all.yml"

# The archive is laid out by codename, not version, and the mapping is not
# derivable. Kept in step with verify-change.sh's own table.
CODENAMES = {"26.04": "resolute", "25.10": "questing", "24.04": "noble", "22.04": "jammy"}


def default_codename():
    """Read the release Packer is configured to build, then map it."""
    try:
        hcl = (REPO / "packer" / "variables.pkr.hcl").read_text()
        m = re.search(r'variable\s+"ubuntu_release".*?default\s*=\s*"([^"]+)"', hcl, re.S)
        if m:
            return CODENAMES.get(m.group(1), "resolute")
    except OSError:
        pass
    return "resolute"


def parse_deb_line(line):
    """Split a sources.list line into base URL, suite and first component."""
    body = re.sub(r"^\s*deb\s+\[[^\]]*\]\s*", "", line.strip())
    parts = body.split()
    if len(parts) < 3:
        return None
    return parts[0].rstrip("/"), parts[1], parts[2]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--codename", default=None,
                    help="Ubuntu codename to substitute (default: from packer variables)")
    ap.add_argument("--only", help="check just this repository by name")
    a = ap.parse_args()

    if not VERIFY.exists():
        print(f"error: {VERIFY} not found", file=sys.stderr)
        return 1

    try:
        import yaml
    except ImportError:
        print("error: PyYAML is required -- pip install pyyaml", file=sys.stderr)
        return 1

    codename = a.codename or default_codename()
    data = yaml.safe_load(GROUP_VARS.read_text())
    repos = data.get("apps_apt_repos", []) or []

    print(f"Checking {len(repos)} repositories against Ubuntu '{codename}'\n")
    worst = 0
    for entry in repos:
        name = entry.get("name", "?")
        if a.only and a.only != name:
            continue
        repo_line = " ".join(str(entry.get("repo", "")).split())
        repo_line = repo_line.replace("{{ ansible_distribution_release }}", codename)
        parsed = parse_deb_line(repo_line)
        if not parsed:
            print(f"  {name}: could not parse repo line -- skipped")
            worst = max(worst, 1)
            continue
        base, suite, component = parsed
        print(f"--- {name} ({suite}/{component})")
        rc = subprocess.run(
            [str(VERIFY), "repo", entry.get("key_url", ""), base, suite, component]
        ).returncode
        # 1 (definitively wrong) outranks 2 (could not check): a real error must
        # not be masked by an unrelated network block.
        worst = 1 if 1 in (worst, rc) else max(worst, rc)
        print()

    verdict = {0: "all repositories verified",
               1: "at least one repository is WRONG -- fix before building",
               2: "some repositories could not be checked (network blocked) -- "
                  "none were found wrong"}[worst]
    print(verdict)
    return worst


if __name__ == "__main__":
    sys.exit(main())
