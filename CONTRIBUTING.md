# Contributing

## Commit messages

Every commit follows [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):

```
<type>[(<scope>)][!]: <description>

[body]

[footers]
```

### Types

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

### Scopes

Optional, but when present it must be one of `ansible`, `packer`, `terraform`, `iso`,
`scripts`, `docs`, `ci`, `make`, `skill`, `goss`, `image`. Omit it rather than inventing
one. Use `image` for a change to what lands on the built image — a package added or
removed — since that is the scope a reader cares about most here.

### Rules

- **The subject states the outcome, not the technique.**
  `fix(iso): stop mangling xorriso's own quoted arguments`, not
  `fix(scripts): use mapfile instead of unquoted expansion`.
- **72 characters per line**, subject and body alike. URLs, indented code blocks and
  git trailers are exempt.
- No trailing period on the subject. No emoji anywhere.
- Bullets (`- `) only when there are genuinely distinct changes; one change is a sentence.
- **No attribution lines** — no `Co-Authored-By`, no generated-by taglines or links.
- A breaking change gets `!` before the colon and/or a `BREAKING CHANGE:` footer. Here
  that means a change where `make apply` is not enough and the machine needs reflashing.
  Say so explicitly.
- Closing references go on their own footer line: `Fixes #123`. Use `Refs #123` when the
  commit advances an issue without finishing it.

### Checking

```bash
make lint-commits                          # HEAD
make lint-commits RANGE=origin/main..HEAD  # a span
```

Exit codes match `verify-change.sh`: `0` conforms, `1` violations, `2` could not check.

This is **not** enforced in CI — no workflow inspects commit messages. It is a linter you
run, plus a convention the tooling below writes for you.

### Grandfathered history

Commits before `feat: standardize commits on Conventional Commits and a changelog`
predate this convention and are not being rewritten. That is why `make lint-commits`
checks `HEAD` alone by default; running it across older history reports dozens of
failures nobody should act on.

## The changelog

`CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

**Edit it only while preparing a commit, never during implementation.** One sentence in
the right subsection under `[Unreleased]`, written for someone running the image rather
than someone reading the diff.

Most commits get no entry, and that is correct. Refactors, tests, documentation, CI,
skill/`.claude` configuration, dependency bumps with no behaviour change, and bugs both
introduced and fixed within the same unreleased cycle all get nothing.

Editing an existing bullet beats adding a second one for the same feature. Never sweep in
bullets another session left behind.

## Working with Claude in this repo

Two skills cover the common paths, and both are shortcuts rather than gates — nothing
here is load-bearing:

| Skill | Covers |
|---|---|
| `config-change` | adding or removing anything that lands on the image, end to end |
| `commit` | committing: changelog, message, staging, validation, push |

`/commit` invokes the second directly. `CLAUDE.md` points any Claude session at both.

## Linting

```bash
make lint           # yaml, ansible, packer, terraform, shell, docs
make lint-commits   # commit messages (separate: lint runs before a commit exists)
```

`make lint-docs` regenerates every committed doc and fails if anything moved, so
`docs/` cannot silently drift from the source it describes. If you change
`scripts/gen-config-docs.py`, run `make docs-config` and commit the result.
