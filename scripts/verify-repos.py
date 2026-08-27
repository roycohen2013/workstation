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

    # A CRLF checkout makes the shebang "bash\r", which fails with a message
    # that names a file that is plainly present. Detect it and say what to do,
    # rather than letting every repository fail identically and opaquely.
    if b"\r\n" in VERIFY.read_bytes().split(b"\n", 1)[0] + b"\n":
        print("error: scripts have Windows (CRLF) line endings, so the shebang "
              "reads as 'bash\\r' and will not run.\n"
              "Fix the checkout with:\n"
              "    git config core.autocrlf false\n"
              "    git rm --cached -r . >/dev/null && git reset --hard\n"
              "The committed .gitattributes prevents this on a fresh clone.",
              file=sys.stderr)
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
            ["bash", str(VERIFY), "repo", entry.get("key_url", ""), base, suite, component]
        ).returncode
        if rc not in (0, 1, 2):
            # 126/127 mean the helper could not be executed. Anything unexpected
            # is a failure of the check itself, which must not be reported as a
            # clean result.
            print(f"  ! verify-change.sh exited {rc} -- the check did not run")
            rc = 1
        # 1 (definitively wrong) outranks 2 (could not check): a real error must
        # not be masked by an unrelated network block.
        worst = 1 if 1 in (worst, rc) else max(worst, rc)
        print()

    # 1Password derives its debsig policy directory from the long ID of its
    # signing key. Nothing about the repository check touches that, and a wrong
    # value fails silently -- the policy lands where dpkg never looks and the
    # install still succeeds -- so it is checked against the published key here.
    debsig = data.get("apps_1password_debsig_key_id")
    onepw = next((r for r in repos if r.get("name") == "1password"), None)
    if debsig and onepw and not a.only:
        print("--- 1password debsig key id")
        rc = subprocess.run(
            ["bash", str(VERIFY), "keyid", onepw.get("key_url", ""), str(debsig)]
        ).returncode
        if rc not in (0, 1, 2):
            print(f"  ! verify-change.sh exited {rc} -- the check did not run")
            rc = 1
        worst = 1 if 1 in (worst, rc) else max(worst, rc)
        print()

    verdict = {0: "all repositories and key ids verified",
               1: "at least one repository is WRONG -- fix before building",
               2: "some repositories could not be checked (network blocked) -- "
                  "none were found wrong"}.get(worst, f"unexpected status {worst}")
    print(verdict)
    return worst


if __name__ == "__main__":
    sys.exit(main())
