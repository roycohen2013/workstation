# workstation

Infrastructure as code for a personal Ubuntu workstation image: one Ansible
playbook run in two phases (`image` inside a Packer build VM, `live` against
the machine you are on), producing an artifact that boots as a VM or on laptop
hardware.

Start with [README.md](README.md). When something breaks, go to
[TROUBLESHOOTING.md](TROUBLESHOOTING.md) — it is organised by the exact error
text — and run `make doctor`, which checks whether this machine still matches
what the repo assumes.

**The configuration surface is `ansible/group_vars/all.yml`.** Almost every
change is one or two lines of data there; the roles are machinery that consumes
it. Prefer editing that file over editing a role.

## Agent skills

### Issue tracker

Issues live as markdown files under `.scratch/<feature-slug>/` in this repo,
not in GitHub Issues. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context: one `CONTEXT.md` and one `docs/adr/` at the repo root, both
created lazily rather than upfront. See `docs/agents/domain.md`.

## Making a configuration change

This repo has its own `config-change` skill (`.claude/skills/config-change/`),
and it takes precedence over general-purpose editing for anything that ends up
on the image — adding or removing a package, adding an apt repository, changing
a dconf setting, opening a firewall port, pinning a runtime. It exists because
the expensive failure here is a misspelled package name: nothing catches it at
edit time, and it surfaces 30–60 minutes into a Packer build. The skill checks
the thing actually exists before committing.

## Verification expectations

Changes to this repo are verified against reality rather than assumed:

- `make lint` before committing anything.
- `.claude/skills/config-change/scripts/verify-change.sh` for anything naming
  an external artifact. Exit 2 means "could not check", which is **not** a pass.
- `make verify-repos` when touching third-party repositories or pinned
  downloads.
- A check that has never been seen failing is not yet a check — exercise the
  failure path, not only the happy one.
