# Working in this repo

This repo builds a personal Ubuntu workstation image (Packer + Ansible + Terraform) that
runs both as a VM and flashed onto laptop hardware. Almost every change a user asks for
is one or two lines of data in `ansible/group_vars/all.yml` — the roles consume that data
and rarely need touching.

## Committing

**Use the `commit` skill for every commit. Do not hand-write `git commit` messages.**

It owns the whole path: the `CHANGELOG.md` entry, the Conventional Commits message,
staging specific paths, validation, and the push. The full convention is in
[CONTRIBUTING.md](CONTRIBUTING.md); the short version:

- `<type>[(<scope>)][!]: <description>` — types are `feat` `fix` `refactor` `docs` `test`
  `chore` `ci` `perf`; scopes are `ansible` `packer` `terraform` `iso` `scripts` `docs`
  `ci` `make` `skill` `goss` `image`.
- The subject states the outcome, not the technique.
- 72 characters per line. No trailing period. No emoji. No attribution lines.
- `CHANGELOG.md` is edited **only** while preparing a commit, never during
  implementation, and only for user-facing changes.
- Validate with `make lint-commits` before pushing.

Commits before `feat: standardize commits on Conventional Commits and a changelog`
predate this convention and are not being rewritten.

## Changing the image configuration

Use the `config-change` skill. It routes the change to the right key, traces what else it
touches, verifies the package or repository actually exists before a 45-minute build
discovers it does not, lints, and then hands off to `commit`.

## Verifying

```bash
make lint           # yaml, ansible, packer, terraform, shell, docs
make lint-commits   # commit messages
make verify-repos   # every declared third-party apt repo still resolves
make image          # full build: needs /dev/kvm, takes 30-60 minutes
```

`make lint-docs` (part of `make lint`) regenerates every committed doc and fails if
anything moved. **If you edit `scripts/gen-config-docs.py`, run `make docs-config` and
commit the result**, or CI's `docs` job goes red.

## Things that cost a build if you get them wrong

- **A misspelled package name** fails deep inside a Packer run, 30–60 minutes in.
  `.claude/skills/config-change/scripts/verify-change.sh` settles it in two seconds.
- **Exit code 2 from any verify script means "could not check", not "passed".** Reporting
  an unreachable check as verified launders a guess into a green tick.
- **dconf values are GVariant literals** — a string needs its own inner quotes.
- **A vendor repo's suite is not always the Ubuntu codename.** Some publish a single
  `stable` suite for every release; templating the codename there 404s at `apt update`.
