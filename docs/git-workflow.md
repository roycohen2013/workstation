<!-- Hand-written; not generated, unlike configuration.md / roles.md /
     packer.md / terraform.md, which `make docs-config` produces. -->

# Git workflow

Trunk is `main`. Nothing is committed to it directly: every change goes on a
branch and reaches `main` through a pull request that CI has passed.

## Branches

| Prefix | For |
|---|---|
| `change/<slug>` | anything that alters the image — a package, a repository, a setting |
| `fix/<slug>` | repo and CI bugs that do not change what lands on a machine |

One logical change per branch. Branches are squash-merged, so a branch becomes a
single commit on `main`; anything worth remembering from the work — a bug found
on the way, an alternative rejected — belongs in the squash body.

## Working on several at once

Use a worktree per branch rather than switching one checkout back and forth:

```bash
git worktree add ../workstation-add-slack -b change/add-slack
cd ../workstation-add-slack
```

Each worktree has its own `build/`, so one branch's `make image` cannot disturb
another's. Large downloads are shared rather than duplicated: Packer caches in
`~/.cache/packer` and `scripts/build-iso.sh` caches in
`~/.cache/workstation/iso`, both outside the tree.

When finished:

```bash
git worktree remove ../workstation-add-slack
```

## Shipping a change

```bash
git push -u origin change/add-slack
gh pr create --fill
gh pr merge --squash --auto
```

`--auto` merges the PR when the required checks go green rather than making you
wait. `apply` converges a real machine twice and takes twelve to fifteen
minutes, so waiting interactively wastes the session.

## What gates a merge

Two required checks on `main`:

| Check | Time | Catches |
|---|---|---|
| `lint` | ~1 min | YAML, Ansible syntax, `packer validate`, `terraform validate`, shellcheck |
| `apply` | 12–15 min | whether the playbook actually converges, and whether it settles on a second pass |

Both are required because both have earned it. `lint` was green for a Terraform
module that could not initialise and for a task pointing at a file that no longer
existed; `apply` is what caught them. A fast check that passes on broken config
is not a gate.

`apply` always reports on a pull request, even one touching no Ansible: a
required check that never reports blocks its PR forever, so the job runs and
short-circuits internally, passing in seconds when there is nothing to converge.

## Generated docs and parallel branches

`docs/configuration.md` and the role READMEs are generated from `group_vars` and
the roles. Two branches that both touch a variable therefore conflict twice —
once in the config, once in its derived output.

`lint-docs` is **advisory on pull requests and enforcing on `main`**. Do not
fight the generated files on a branch; regenerate after merging:

```bash
make docs-config && git commit -am "Regenerate docs"
```

## Escape hatch

Branch protection does not apply to the repository owner, so a genuine emergency
can still be pushed straight to `main`. That is deliberate, and it is not the
normal path — everything routine, including everything an agent does, goes
through a pull request.

Be clear-eyed about what that means: an agent working in this repository pushes
with the owner's credentials, so protection does **not** stop it either. The
workflow holds because the agent is instructed to follow it — in
`.claude/skills/config-change/SKILL.md` and here — not because a rule blocks the
alternative. If that turns out to be too weak a guarantee, the fix is to enforce
protection on administrators too and accept that a one-character typo fix then
needs a pull request and a fifteen-minute wait.
