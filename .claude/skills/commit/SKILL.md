---
name: commit
description: >-
  Commit staged or unstaged work in this repo, and keep CHANGELOG.md current as part of
  doing so. Handles the whole path: survey the diff, add the changelog entry if the change
  deserves one, draft a Conventional Commits message, show it for confirmation, stage the
  specific files, commit, validate the message, push, and open a draft PR when one is
  needed. Use this skill whenever the user asks to commit, check in, save, land, ship, or
  push work — including casual phrasings like "commit this", "commit and push", "save my
  progress", "write a commit message for this", or "/commit" — and whenever another skill
  or task reaches the point of committing. This is the only sanctioned way to commit here;
  do not hand-write `git commit` messages outside it.
---

# Making a commit

Every commit in this repo follows [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)
and, when it changes something a user would notice, carries one line in `CHANGELOG.md`.

Work in six steps: survey → changelog → draft → confirm → commit → push.

## Why the changelog is written here and nowhere else

A changelog written during implementation is written by someone who still has their head
in the code, and it reads that way — it describes the patch, not the change. Written at
commit time, against the finished diff, it describes what actually landed.

More practically: an entry added mid-implementation gets orphaned when the approach
changes, and nobody notices, because nothing rereads it. **`CHANGELOG.md` is edited at
exactly one moment — Step 2 of this skill — and never during implementation.**

## Step 1 — Survey what changed

```bash
git status
git diff              # unstaged
git diff --staged     # already staged, if anything is
git log --oneline -5
```

Read the diff properly. The commit message describes what the change *does for someone
using this*, and that is rarely legible from the filenames alone.

**Check whether the working tree holds work that is not yours.** If `git status` shows
changes you did not make this session — a half-finished edit, another session's
`CHANGELOG.md` bullets — do not sweep them in. Commit your own files, and say plainly
what you left behind.

## Step 2 — Update the changelog, or decide it needs none

`CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Add one
sentence to the right subsection under `[Unreleased]`: **Added**, **Changed**,
**Deprecated**, **Removed**, **Fixed**, or **Security**.

Write it for someone who runs this image, not for someone reading the diff:

> **Good** — `make apply no longer fails on a fresh install: the mise configuration
> directory is created before its config file is written into it.`
>
> **Bad** — `Reordered two tasks in roles/dev/tasks/main.yml.`

**Most commits get no entry, and that is correct.** These get nothing:

| No entry for | Because |
|---|---|
| refactors with no behaviour change | nobody using the image can tell |
| tests, goss assertions, evals | same |
| documentation, generated docs | same |
| CI workflow changes | same |
| skill and `.claude/` configuration | same |
| dependency bumps with no behaviour change | same |
| a bug introduced *and* fixed within the same unreleased cycle | it never reached anyone |

Two more rules that matter:

- **Editing an existing bullet beats adding a second one** for the same feature. Three
  commits building one capability produce one line, refined, not three.
- **Never sweep in bullets left by another session.** If `CHANGELOG.md` already carries
  entries you did not write, commit only your own line alongside your code, and say so.

## Step 3 — Draft the message

```
<type>[(<scope>)][!]: <description>

[body]

[footers]
```

**Types** — eight, no others:

| Type | For |
|---|---|
| `feat` | a capability the image or tooling did not have before |
| `fix` | corrects broken behaviour |
| `refactor` | restructures without changing behaviour |
| `docs` | documentation only |
| `test` | goss assertions, evals, test tooling |
| `chore` | maintenance with no behaviour change |
| `ci` | `.github/workflows` |
| `perf` | same behaviour, measurably faster or smaller |

**Scopes** — optional, but when present it must be one of: `ansible`, `packer`,
`terraform`, `iso`, `scripts`, `docs`, `ci`, `make`, `skill`, `goss`, `image`. Omit it
rather than inventing one. Use `image` for a change to what lands on the built image —
a package added or removed — since that is the scope a reader cares about most here.

**Breaking changes** get `!` before the colon, a `BREAKING CHANGE:` footer, or both. In
this repo that means: *a change where `make apply` is not enough and the machine needs
reflashing.* Say that explicitly in the footer.

### The subject states the outcome, not the technique

This is the rule the reference convention leans hardest on, and the one most often got
wrong:

> **Bad** — `refactor: extract helper function for validation`
> **Good** — `fix: prevent crash when user input is empty`
>
> **Bad** — `fix(scripts): use mapfile instead of unquoted expansion`
> **Good** — `fix(iso): stop mangling xorriso's own quoted arguments`

The first of each pair describes what you typed. The second describes what stopped being
broken. The body is where *how* belongs, if how is non-obvious.

### Mechanics

- **72 characters per line**, subject and body alike. URLs, indented code blocks and
  trailers are exempt — the linter knows this, so do not mangle a URL to fit.
- **No trailing period** on the subject.
- **No emoji**, anywhere.
- **Bullets (`- `) only for genuinely distinct changes.** One change is a sentence.
- **No attribution lines.** No `Co-Authored-By`, no `Claude-Session`, no generated-by
  taglines or links. *Exception:* if your harness mandates attribution trailers, add them
  and say plainly that you did and why — the linter tolerates trailers precisely so that
  this conflict is visible rather than silently resolved either way.

### Issue linking

If the commit finishes a tracked item, put its closing reference on its own line in the
footer — `Fixes #123`, `Closes ABC-123`. Use a neutral `Refs #123` when the commit
advances the item without finishing it; a work-in-progress commit must not close it.

## Step 4 — Show it, then wait

Show the user the exact message and the exact list of files that will be staged:

```
## Commit

fix(ansible): mise config written before its directory exists

`make apply` failed on a fresh install because ansible.builtin.copy
never creates missing parent directories.

**Files** — ansible/roles/dev/tasks/main.yml, CHANGELOG.md

OK to commit?
```

Then stop and wait. This is the step that replaces a commit-proposal widget: the user is
approving both the wording and the file list, and the file list is the half that silently
goes wrong.

## Step 5 — Stage and commit

**Stage the specific paths, never `git add -A` or `git add .`.** A blanket add is how an
unrelated file, a local experiment, or a credential ends up in history.

```bash
git add ansible/roles/dev/tasks/main.yml CHANGELOG.md
git status                       # confirm exactly what is staged
git commit -F - <<'MSG'
fix(ansible): mise config written before its directory exists

`make apply` failed on a fresh install because ansible.builtin.copy
never creates missing parent directories.
MSG
```

Use `-F -` with a heredoc rather than repeated `-m` flags: `-m` makes the blank-line
structure between subject, body and footers easy to get wrong, and that structure is
what the convention is made of.

Then validate what you actually wrote:

```bash
make lint-commits
```

| Exit | Meaning | What to do |
|---|---|---|
| 0 | the message conforms | push |
| 1 | violations, each reported with its line | `git commit --amend` and re-run |
| 2 | could not check | say so; do not claim it passed |

Amending is correct here — the commit has not been pushed yet, so nothing downstream
depends on it.

## Step 6 — Push, and open a PR if one is needed

```bash
git push -u origin "$(git branch --show-current)"
```

Never switch branches or push somewhere else without asking. On a network failure retry
up to four times with backoff (2s, 4s, 8s, 16s).

If the repo's default branch is not the one checked out and no **open** PR exists for
this branch, open a draft PR. A merged or closed PR does not count — that work is
finished and cannot track new commits.

Then tell the user what landed: the subject line, whether a changelog entry was added or
deliberately skipped and why, what was verified, and anything left uncommitted in the
working tree.

## Grandfathered history

Commits made before this convention was adopted do not follow it and are not being
rewritten. That is why `make lint-commits` checks `HEAD` alone by default rather than
the whole branch — running it across old history reports dozens of failures that nobody
should act on. Pass `--range` deliberately when you want a span checked.
