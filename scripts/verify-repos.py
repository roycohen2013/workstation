#!/usr/bin/env python3
"""Check every third-party apt repository declared in group_vars.

Wraps .claude/skills/config-change/scripts/verify-change.sh so the repository
list comes from the config rather than from copy-pasted URLs that go stale the
moment a vendor is added.

It also substitutes the Ubuntu codename into repo lines. Docker and HashiCorp
template it; checking those by hand means knowing that 26.04 is "resolute",
which is exactly the kind of detail worth not relying on someone remembering.

Beyond repositories it checks the pinned direct downloads -- BalenaEtcher and
terraform-docs -- which no repository check covers: both are pinned by version
with a recorded sha256, and a withdrawn or re-cut release otherwise surfaces
only mid-build.

  scripts/verify-repos.py [--codename resolute] [--only NAME] [--checksums]

--checksums additionally downloads each pinned artifact and hashes it. Off by
default because BalenaEtcher alone is ~150MB; existence is the cheap check
worth running often.

Exit codes match verify-change.sh, aggregated over everything checked:
  0  all verified
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


def render(template, data):
    """Fill {{ var }} references from group_vars, one level deep.

    Deliberately not Jinja: these URLs reference plain scalars declared beside
    them, and pulling in a template engine to substitute two variables would
    mean this check fails for reasons unrelated to what it is checking.
    """
    out = str(template)
    for _ in range(5):
        new = re.sub(r"\{\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}\}",
                     lambda m: str(data.get(m.group(1), m.group(0))), out)
        if new == out:
            break
        out = new
    return " ".join(out.split())


def check_pinned_downloads(data, want_checksums):
    """Do the pinned release artifacts still exist, and still hash as declared?

    Repositories are checked above, but the two things installed from a direct
    URL -- BalenaEtcher and terraform-docs -- are not covered by that at all.
    Both are pinned by version with a recorded sha256, and a vendor deleting or
    re-cutting a release only surfaces mid-build otherwise.
    """
    import urllib.error
    import urllib.request

    targets = []
    for label, url_key, sha_key in (
        ("balena-etcher", "balena_etcher_deb_url", "balena_etcher_deb_sha256"),
        ("terraform-docs", "dev_terraform_docs_url", "dev_terraform_docs_sha256"),
    ):
        if data.get(url_key):
            targets.append((label, render(data[url_key], data), data.get(sha_key)))

    worst = 0
    for label, url, sha in targets:
        print(f"--- {label}")
        if "{{" in url:
            print(f"  ! unresolved template: {url}")
            worst = 1
            print()
            continue
        req = urllib.request.Request(url, method="HEAD",
                                     headers={"User-Agent": "workstation-verify-repos"})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                code = r.status
        except urllib.error.HTTPError as e:
            code = e.code
        except Exception as e:  # network blocked, DNS, TLS -- cannot conclude
            print(f"  ? {url}")
            print(f"    could not be checked ({type(e).__name__}) -- not a failure")
            worst = max(worst, 2) if worst != 1 else 1
            print()
            continue

        if code == 200:
            print(f"  ✓ {url}")
        else:
            # A pinned release that 404s is definitively wrong: the version was
            # withdrawn or re-tagged, and the next build will fail on it.
            print(f"  ✗ {url}")
            print(f"    HTTP {code} -- the pinned version is gone or moved")
            worst = 1

        if want_checksums and code == 200:
            import hashlib
            try:
                with urllib.request.urlopen(
                        urllib.request.Request(
                            url, headers={"User-Agent": "workstation-verify-repos"}),
                        timeout=600) as r:
                    digest = hashlib.sha256(r.read()).hexdigest()
            except Exception as e:
                print(f"    checksum not checked ({type(e).__name__})")
                worst = max(worst, 2) if worst != 1 else 1
            else:
                if digest == sha:
                    print("    ✓ sha256 matches the pinned value")
                else:
                    print(f"    ✗ sha256 MISMATCH")
                    print(f"      declared {sha}")
                    print(f"      actual   {digest}")
                    worst = 1
        print()
    return worst


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--codename", default=None,
                    help="Ubuntu codename to substitute (default: from packer variables)")
    ap.add_argument("--only", help="check just this repository by name")
    ap.add_argument("--checksums", action="store_true",
                    help="also download pinned artifacts and verify their sha256 "
                         "(slow: BalenaEtcher alone is ~150MB)")
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
        # Matched by shape rather than by exact spelling. This used to look for
        # the literal "{{ ansible_distribution_release }}", and when group_vars
        # moved to ansible_facts['distribution_release'] the substitution
        # silently stopped matching: the suite became "{{", and the check
        # reported it as unreachable -- a warning -- rather than as broken.
        repo_line = re.sub(r"\{\{[^}]*distribution_release[^}]*\}\}", codename, repo_line)
        if "{{" in repo_line:
            # Anything left is a template this script does not understand.
            # Checking the URL anyway would test a nonsense suite and report
            # a network problem, which is how the above went unnoticed.
            print(f"  {name}: unresolved template in repo line -- {repo_line}")
            print("    teach scripts/verify-repos.py how to substitute it")
            worst = 1
            continue
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

    if not a.only:
        rc = check_pinned_downloads(data, a.checksums)
        worst = 1 if 1 in (worst, rc) else max(worst, rc)

    verdict = {0: "all repositories, key ids and pinned downloads verified",
               1: "something is WRONG -- fix before building",
               2: "some checks could not run (network blocked) -- "
                  "nothing was found wrong"}.get(worst, f"unexpected status {worst}")
    print(verdict)
    return worst


if __name__ == "__main__":
    sys.exit(main())
