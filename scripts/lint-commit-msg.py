#!/usr/bin/env python3
"""Validate commit messages against this repo's Conventional Commits convention.

Deliberately stdlib-only. commitlint would be the obvious choice, but it needs a
Node toolchain and a package.json, and this repo has neither -- every other check
here (verify-repos.py, gen-config-docs.py, render-docs.py) is a stdlib Python or
shell script, and a lint step that forces a second language runtime onto every
contributor is a lint step people delete.

Three modes:

    lint-commit-msg.py                   validate HEAD
    lint-commit-msg.py --range A..B      validate every commit in a span
    lint-commit-msg.py --file PATH       validate one message file

The default is HEAD rather than origin/main..HEAD on purpose: every commit made
before this convention was adopted predates it and would fail. CONTRIBUTING.md
names the adoption commit as the boundary; history is grandfathered, not rewritten.

Exit codes match scripts/verify-change.sh, the convention already set in this repo:

    0  every message conforms
    1  at least one violation
    2  could not check (bad range, not a git repo)
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys

# The six from the reference convention, plus two this repo demonstrably needs:
# `ci` for .github/workflows, and `perf` for changes like the zstd compression
# level. Keeping the list short is the point -- a type nobody can define is a
# type nobody applies consistently.
TYPES = {
    "feat": "a capability the image or tooling did not have before",
    "fix": "corrects broken behaviour",
    "refactor": "restructures without changing behaviour",
    "docs": "documentation only",
    "test": "goss assertions, evals, test tooling",
    "chore": "maintenance with no behaviour change",
    "ci": "GitHub Actions workflows",
    "perf": "same behaviour, measurably faster or smaller",
}

# Optional, but checked against this list when present. Free-text scopes decay
# into noise within a dozen commits; an allowlist keeps them worth reading.
SCOPES = {
    "ansible": "roles, group_vars, playbooks",
    "packer": "the image build definition",
    "terraform": "testlab or artifact-store modules",
    "iso": "the unattended installer ISO",
    "scripts": "scripts/",
    "docs": "docs/, README, generated reference",
    "ci": ".github/workflows",
    "make": "the Makefile",
    "skill": ".claude/ skills and commands",
    "goss": "tests/goss",
    "image": "what ends up on the built image",
}

SUBJECT_LIMIT = 72
BODY_LIMIT = 72

# The separator is captured rather than baked in as ": " so that "feat:" with no
# description, and "feat:no space", each report what is actually wrong instead of
# falling through to the generic "does not match the format" message.
SUBJECT_RE = re.compile(
    r"^(?P<type>[a-z]+)"
    r"(?:\((?P<scope>[^()]*)\))?"
    r"(?P<bang>!)?"
    r":(?P<sep>[ ]*)"
    r"(?P<desc>.*)$"
)

# A subject git wrote itself. Rewriting these to fit a convention is not worth
# the friction, and `git revert` in particular generates a subject no rule here
# could accept without special-casing it anyway.
GENERATED_SUBJECT_RE = re.compile(r"^(Merge|Revert|fixup!|squash!|amend!)\b")

# Trailers are exempt from the length limit: a session URL or a long
# Co-Authored-By line cannot be wrapped without breaking the trailer.
TRAILER_RE = re.compile(
    r"^(?:BREAKING[ -]CHANGE: "
    r"|[A-Za-z][A-Za-z0-9-]*: \S"
    r"|(?:Fixes|Closes|Resolves|Refs|See-also)\b)"
)

BREAKING_RE = re.compile(r"^BREAKING[ -]CHANGE: \S")
# Caught so a lowercase footer fails loudly rather than silently not registering
# as a breaking change.
BREAKING_MISCASED_RE = re.compile(r"^breaking[ -]change\s*:", re.IGNORECASE)

# Ranges chosen to catch emoji without catching the punctuation this repo
# actually uses -- em dash (U+2014) and curly quotes sit below 0x2600 and are
# deliberately outside every range here.
EMOJI_RANGES = (
    (0x1F000, 0x1FAFF),
    (0x2600, 0x27BF),
    (0x2B00, 0x2BFF),
    (0xFE0F, 0xFE0F),
)


def has_emoji(text: str) -> str | None:
    """Return the first emoji found, or None."""
    for ch in text:
        code = ord(ch)
        if any(lo <= code <= hi for lo, hi in EMOJI_RANGES):
            return ch
    return None


def is_length_exempt(line: str, in_fence: bool) -> bool:
    """Lines that cannot reasonably be wrapped to the limit."""
    if in_fence:
        return True
    if line.startswith(("    ", "\t")):  # indented code block
        return True
    if "http://" in line or "https://" in line:
        return True
    return bool(TRAILER_RE.match(line))


def strip_comments(raw: str) -> str:
    """Drop what git itself would drop from a message file.

    COMMIT_EDITMSG carries `#` comment lines, and `commit --verbose` appends the
    whole staged diff below a scissors line. Neither is part of the message.
    """
    out = []
    for line in raw.splitlines():
        if line.startswith("# ------------------------ >8"):
            break
        if line.startswith("#"):
            continue
        out.append(line)
    return "\n".join(out)


def check(message: str) -> list[str]:
    """Return a list of violations. Empty means the message conforms."""
    lines = message.rstrip().split("\n")
    if not lines or not lines[0].strip():
        return ["subject: message is empty"]

    subject = lines[0]
    if GENERATED_SUBJECT_RE.match(subject):
        return []

    problems: list[str] = []

    match = SUBJECT_RE.match(subject)
    if not match:
        problems.append(
            'subject: not "type(scope): description" -- expected e.g. '
            '"fix(ansible): mise config written before its directory exists"'
        )
    else:
        ctype = match.group("type")
        scope = match.group("scope")
        desc = match.group("desc")

        if ctype not in TYPES:
            problems.append(
                f'subject: unknown type "{ctype}" (expected one of: '
                f"{', '.join(sorted(TYPES))})"
            )

        if scope is not None:
            if not scope:
                problems.append("subject: empty scope -- write the type alone instead")
            elif scope not in SCOPES:
                problems.append(
                    f'subject: unknown scope "{scope}" (expected one of: '
                    f"{', '.join(sorted(SCOPES))})"
                )

        desc = desc.strip()
        if not desc:
            problems.append("subject: no description after the colon")
        else:
            if match.group("sep") != " ":
                problems.append("subject: put exactly one space after the colon")
            if desc.endswith("."):
                problems.append("subject: drop the trailing period")
            if desc.split()[0].lower() in TYPES and desc[0].isupper():
                problems.append(
                    "subject: description repeats the type -- say what changed instead"
                )

    if len(subject) > SUBJECT_LIMIT:
        problems.append(
            f"subject: {len(subject)} characters, limit is {SUBJECT_LIMIT}"
        )

    emoji = has_emoji(subject)
    if emoji:
        problems.append(f"subject: contains emoji ({emoji!r})")

    if len(lines) > 1:
        if lines[1].strip():
            problems.append("body: needs a blank line between subject and body")

        in_fence = False
        for offset, line in enumerate(lines[1:], start=2):
            if line.lstrip().startswith("```"):
                in_fence = not in_fence
                continue

            if BREAKING_MISCASED_RE.match(line) and not BREAKING_RE.match(line):
                problems.append(
                    f"line {offset}: breaking-change footer must read "
                    f'"BREAKING CHANGE: " in capitals'
                )

            if len(line) > BODY_LIMIT and not is_length_exempt(line, in_fence):
                problems.append(
                    f"line {offset}: {len(line)} characters, limit is {BODY_LIMIT}"
                )

            emoji = has_emoji(line)
            if emoji:
                problems.append(f"line {offset}: contains emoji ({emoji!r})")

    return problems


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args],
        capture_output=True,
        text=True,
        check=True,
    ).stdout


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate commit messages against the Conventional Commits "
        "convention documented in CONTRIBUTING.md.",
    )
    source = parser.add_mutually_exclusive_group()
    source.add_argument(
        "--file",
        metavar="PATH",
        help="validate a single message file (what a commit-msg hook passes)",
    )
    source.add_argument(
        "--range",
        metavar="A..B",
        help="validate every commit in a range (default: HEAD alone)",
    )
    args = parser.parse_args()

    messages: list[tuple[str, str]] = []

    if args.file:
        try:
            with open(args.file, encoding="utf-8") as handle:
                raw = handle.read()
        except OSError as exc:
            print(f"lint-commit-msg: cannot read {args.file}: {exc}", file=sys.stderr)
            return 2
        messages.append((args.file, strip_comments(raw)))
    else:
        try:
            if args.range:
                shas = git("rev-list", args.range).split()
            else:
                shas = [git("rev-parse", "HEAD").strip()]
            for sha in shas:
                messages.append((sha[:7], git("show", "-s", "--format=%B", sha)))
        except subprocess.CalledProcessError as exc:
            detail = (exc.stderr or "").strip() or "git failed"
            print(f"lint-commit-msg: {detail}", file=sys.stderr)
            return 2
        except FileNotFoundError:
            print("lint-commit-msg: git is not installed", file=sys.stderr)
            return 2

    if not messages:
        print("lint-commit-msg: no commits in range, nothing to check")
        return 0

    failed = 0
    for label, message in messages:
        problems = check(message)
        if not problems:
            continue
        failed += 1
        subject = message.strip().split("\n")[0] if message.strip() else "(empty)"
        print(f"\n{label}  {subject}")
        for problem in problems:
            print(f"    {problem}")

    if failed:
        print(
            f"\n{failed} of {len(messages)} message(s) do not conform. "
            "See CONTRIBUTING.md.",
        )
        return 1

    print(f"lint-commit-msg: {len(messages)} message(s) OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
