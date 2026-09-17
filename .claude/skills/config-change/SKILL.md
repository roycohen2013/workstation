---
name: config-change
description: >-
  Make a configuration change to this workstation image repo — add or remove a package
  (apt, snap, or flatpak), add a third-party apt repository, change a GNOME/dconf setting,
  toggle a feature, open a firewall port, pin a language runtime, or adjust a kernel tunable.
  Handles the whole path: clarify the request, present a short plan for approval, make the
  edit, verify the thing actually exists, lint, then commit and push. Use this skill whenever
  the user asks to add, remove, install, enable, disable, or change anything that ends up on
  the workstation image — including casual phrasings like "add htop", "I want Slack on there",
  "stop installing gimp", "make the dock auto-hide", "pin node to 22", or "add the Tailscale
  repo" — even when they never mention the image, Ansible, YAML, or a filename.
---

# Making a configuration change

This repo builds a workstation image from a declarative config. Almost every change
a user asks for is **one or two lines of data** in `ansible/group_vars/all.yml` — the
roles are machinery that consumes that data and rarely need touching.

Work in seven steps: locate → trace → ask → plan → edit → verify → ship. The plan gets explicit
approval before any file is edited; verification runs before anything is committed.

## Why verification comes before the commit

The expensive failure mode here is a misspelled package name. Nothing catches it at
edit time — `apt install nonexistent-thing` fails deep inside a Packer run, after the
base install and most of the provisioning, 30–60 minutes in. Checking that the thing
exists takes two seconds and turns that into an instant fix.

That is what `scripts/verify-change.sh` is for. Run it on every change that names an
external artifact.

## Run steps 1 and 2 in a subagent

Locating the key and tracing the consequences is **read-only research**. It reads
`ansible/group_vars/all.yml` end to end, several roles, `tests/goss/workstation.yaml`
and sometimes the ISO templates — and almost none of that is needed again once it has
produced an answer. Done inline, "add htop" spends most of a context window before the
first character is edited. Done in a subagent, this session keeps the answer instead of
the search.

Send both steps to **one** agent in **one** call. They read the same files, so splitting
them reads `all.yml` twice and doubles the cost the split was meant to avoid.

Prefer the `Explore` agent type where the environment offers it: it has no edit tools,
so it cannot change the tree while you are still deciding what the change should be.
`general-purpose` is a fine second choice. **If no subagent is available, do steps 1 and
2 inline exactly as they are written below.** This is an optimisation, not a new
requirement — a missing agent type must never become a skipped trace.

Never give the research agent an isolated worktree. It is reading the tree the change
will land in, and a throwaway copy makes its line numbers wrong the moment you edit.

Give it the request in the user's own words, and ask for the answer in the shape Step 4
will need:

```
Research a configuration change for this workstation image repo. Read only —
do not edit, stage or commit anything.

The user asked for, verbatim: "<their exact words>"

Answer these five, in this order, and nothing else:

1. PLACEMENT — which key in ansible/group_vars/all.yml does this belong under,
   and why that one rather than the neighbouring candidates? Quote the
   surrounding lines so the edit can match the file's style. Say so explicitly
   if it needs a role rather than data.
2. MACHINE-SPECIFIC STATE — would installing this start a daemon or write
   identity (node keys, host keys, instance IDs, licence activation) that gets
   baked into the image and then shared by every machine flashed from it? Read
   roles/seal and roles/firstboot for how comparable state is handled today.
3. PHASE — does this need to be true in the image, or only on a running
   machine? Check for `workstation_phase == 'live'` on anything related.
4. EXISTING ASSERTIONS — does tests/goss/workstation.yaml assert the old
   behaviour, and so turn this into a red build? Quote the assertion if it does.
5. EXISTENCE — for anything external this names, run
   .claude/skills/config-change/scripts/verify-change.sh and report the exact
   exit code: 0 verified, 1 does not exist, 2 could not check. Report a 2 as
   "could not check" — never as verified.

At most 15 lines. Cite file paths with line numbers. Where a question has no
consequence, answer "nothing" rather than padding it.
```

### The report is evidence, not a decision

What comes back is prose from a model that read the repo once. Every load-bearing claim
in it — a path, a line number, an exit code — is checkable here in seconds, and the
decision stays yours. Check anything that would change the plan.

If the report is thin, vague, or answers a question you did not ask, do the trace
yourself rather than passing its gaps into the plan. A plan whose **Also touches** line
came from an agent that never opened `roles/seal` is worse than one that says nothing,
because it reads as though someone checked.

### What never leaves this session

| Step | Why |
|---|---|
| 3 — ask | the user answers, and a subagent cannot reach them |
| 4 — plan and approval | the approval is the user's, and an agent's report is never shown to them |
| 5 — edit | the edit belongs in this checkout, as one reviewable diff |
| 6 — verify | an exit code has to be read by whoever reports it, not relayed |
| 7 — commit | the `commit` skill shows a message and waits; a subagent cannot be waited on |

## Step 1 — Locate where the change belongs

Delegated to the research agent above, together with Step 2. What follows is what that
agent is looking for — and what you do yourself when there is no agent to ask.

Find the right key first. Guessing wrong here means a change that lints clean and
silently does nothing.

| The user wants… | Goes in `ansible/group_vars/all.yml` under |
|---|---|
| a CLI tool or system utility | `apps_apt_base` |
| a compiler, library, or dev tool | `apps_apt_dev` |
| a GUI application from the Ubuntu archive | `apps_apt_desktop` |
| a package *gone* | `apps_apt_absent` |
| software from a vendor's own apt repo | `apps_apt_repos` (a new entry, packages included) |
| a snap | `apps_snap` |
| a flatpak | `apps_flatpak` |
| a language runtime or version pin | `dev_mise_runtimes` |
| a GNOME/desktop setting | `desktop_dconf` |
| a whole subsystem on or off | `workstation_*_enabled` |
| an inbound firewall port | `security_ufw_allow` |
| a kernel tunable | `base_sysctl` |
| laptop firmware/power packages | `hardware_packages` |

**Prefer data over code.** If it fits a list above, it belongs there — not in a role.
Roles are only for changes that need *logic*: writing a config file, enabling a
systemd unit, running a command, creating a directory. When a request genuinely needs
that, say so in the plan and name the role you'll touch, because it is a bigger change
than the user probably expects.

Two placements deserve a second thought:

- **Third-party repo packages** go in that repo's own `packages:` list, never in
  `apps_apt_base`. Listing them separately means apt tries to install them before the
  repo exists.
- **`hardware_packages` installs into every image**, VM builds included. That is
  deliberate — the image gets flashed onto metal, and a VM-built image missing
  `linux-firmware` is a laptop with no Wi-Fi. Don't "optimise" it away.

## Step 2 — Trace what else the change touches

Delegated with Step 1, in the same call. The three questions below are questions 2 to 4
of that prompt; what follows is the reasoning behind them, and the fallback when no
subagent is available.

Routing a change to the right list is the easy half. What bites is the
consequence that lands somewhere the placement table never points.

The frame that generates the right questions: **this repo builds one image that
gets flashed onto many machines.** Anything a package writes at install time is
baked into the artifact and then shared by every machine built from it. On a
single laptop that would be harmless; here it is a defect.

Three questions. Each has a real failure behind it.

**1. Does installing this create machine-specific state?**

Daemons generate identity the first time they start — node keys, host keys,
instance IDs, licence activations — and systemd presets mean most packages start
their service at install time, inside the build VM. That state then ships.

> Adding `tailscale` starts `tailscaled`, which writes a node key to
> `/var/lib/tailscale`. Every laptop flashed from that image claims the *same*
> tailnet node. The fix belongs in `roles/seal` (strip it), and sometimes
> `roles/firstboot` (regenerate it) — exactly how machine-id and SSH host keys
> are already handled.

**2. Does this need to be true in the image, or only on a running machine?**

Roles run in both phases, but a task gated `when: workstation_phase == 'live'`
never reaches the artifact. A flashed machine boots with whatever the image
contains, long before anything runs `make apply`.

> Enabling sshd while its hardening config is written live-only means a freshly
> flashed laptop boots sshd with stock configuration.

**3. Does anything already assert the old behaviour?**

`tests/goss/workstation.yaml` runs inside the build and fails it. A change that
contradicts an assertion turns a working config into a red build.

> `ssh-disabled-in-image` asserts sshd is disabled. Enabling it fails the build
> until that assertion moves too.

Two more worth carrying:

- **`ufw allow` is additive.** Narrowing an existing rule leaves the wider one in
  place unless it is explicitly removed — the port keeps answering everyone.
- **The ISO path is not the golden-image path.** `iso/nocloud/user-data.tmpl`
  sets `install-server: false`, so it inherits nothing the Packer build set up.

Most changes genuinely are just a line in a list. When all three answers are
"nothing", say so in the plan in a few words and move on — the value is in having
asked, not in manufacturing work.

## Step 3 — Ask only what changes the diff

Ask a follow-up when different answers produce genuinely different edits. Otherwise
pick the sensible default, state it in the plan, and move on — the plan is where the
user corrects you, so a question that the plan would answer anyway is just friction.

Worth asking:

- **The same app exists in several sources.** VS Code is a snap, a flatpak, and a
  Microsoft apt repo; these differ in sandboxing, update cadence, and CLI integration.
- **A vendor repo when the archive already has the package.** `docker.io` from Ubuntu
  and `docker-ce` from Docker are different packages with different lifecycles.
- **A GUI app when `workstation_desktop_enabled` might be false.**
- **Removing something that other config depends on** — e.g. dropping `zsh` while
  `workstation_user_shell` still points at it.

Not worth asking: which of `apps_apt_base` vs `apps_apt_dev` a tool belongs in, whether
to alphabetise, or whether to rebuild afterwards. Decide, and note it in the plan.

## Step 4 — Present the plan, then wait

Keep it short enough to read in one glance. The user is approving a diff, not a design
document.

```
## Plan: add Tailscale

**Change** — one new entry in `apps_apt_repos` (ansible/group_vars/all.yml):
  name: tailscale, key from pkgs.tailscale.com, package: tailscale

**Why a repo, not apt** — Ubuntu's archive tailscale lags upstream by months.

**Also touches** — `roles/seal`: installing the deb starts tailscaled, which
  writes a node key to /var/lib/tailscale. Left in, every machine flashed from
  this image claims the same tailnet node, so seal has to strip it.

**Verify** — verify-change.sh repo + make lint. No image build (needs KVM, ~45 min).

OK to proceed?
```

The **Also touches** line carries the Step 2 answers. It is the part most worth
getting right: it is where a one-line data change reveals itself as something
bigger, at the point the user can still redirect it. When Step 2 found nothing,
say so in a few words ("**Also touches** — nothing; pure data, no daemon, no
assertion affected") rather than dropping the line, so its absence never has to be
guessed at.

Always state what verification will and will not cover. "Verified" must never be heard
as "built and booted" — see Step 6.

Then stop and wait for approval. If the user asked for several things at once and some
need clarification, propose the parts that are clear and flag the rest rather than
blocking the whole batch.

## Step 5 — Make the edit

Match the file's existing style: same list, same indentation, grouped with related
entries rather than appended to the end.

Gotchas that pass lint and fail at build time:

- **dconf values are GVariant literals, not plain strings.** A string needs its own
  inner quotes and a uint needs its type prefix:
  ```yaml
  - { key: /org/gnome/desktop/interface/color-scheme, value: "'prefer-dark'" }
  - { key: /org/gnome/desktop/session/idle-delay, value: "uint32 300" }
  - { key: /org/gnome/mutter/dynamic-workspaces, value: "false" }
  ```
  Dropping the inner quotes on a string yields a dconf file that fails to load.

- **A repo's `enabled:` is consumed with `| bool`.** A literal `true`/`false` or a
  template that renders to one is fine. This matters: without `| bool`, the string
  `"False"` is truthy, which would silently enable a repo the user switched off.

- **The keyring filename is derived from `name:`.** An entry named `tailscale` must
  reference `signed-by=/etc/apt/keyrings/tailscale.gpg`. A mismatch produces a
  signature error that reads like a network fault.

- **Keep lines under 120 characters** (yamllint). Repo lines almost always exceed it —
  use a folded scalar, as the existing entries do:
  ```yaml
  repo: >-
    deb [arch=amd64 signed-by=/etc/apt/keyrings/tailscale.gpg]
    https://pkgs.tailscale.com/stable/ubuntu
    {{ ansible_distribution_release }} main
  ```
  **Check which suite the vendor actually publishes before templating it.**
  `{{ ansible_distribution_release }}` is right for vendors that ship per-codename
  suites (Docker, HashiCorp) and survives the next Ubuntu upgrade. But some
  publish a *single* suite for every release — Anthropic's `claude-desktop` repo
  uses `stable` — and templating the codename there produces a 404 at
  `apt update`. `verify-change.sh repo` settles it in two seconds; the failure
  looks identical either way, so guessing costs a build.

- **Debian renames some binaries.** `fd` ships as `fdfind`, `bat` as `batcat`. If a new
  package does this, add a symlink alongside the existing ones in `roles/dev`.

## Step 6 — Verify

Two tiers always run. The third is the user's call.

**Tier 1 — does it exist?**

```bash
.claude/skills/config-change/scripts/verify-change.sh apt      ripgrep neovim
.claude/skills/config-change/scripts/verify-change.sh snap     code
.claude/skills/config-change/scripts/verify-change.sh flatpak  com.spotify.Client
.claude/skills/config-change/scripts/verify-change.sh repo \
    <key-url> <base-url> <suite> [component]
```

Read the exit code, because the three outcomes are not interchangeable:

| Exit | Meaning | What to do |
|---|---|---|
| 0 | verified to exist | proceed |
| 1 | definitively does not exist | fix it — the output suggests near-misses |
| 2 | could not check (host unreachable) | proceed, but **say it is unverified** |

Exit 2 is not a pass. Reporting an unreachable check as "verified" launders a guess
into a green tick, which is worse than having run no check at all.

**Run these here even if the research agent already ran them.** Tier 1 does not depend
on the edit, so re-running costs two seconds, and it is the whole difference between
reporting an exit code you read and one you were told about. If the two disagree, the
one you ran is the one that counts.

**Tier 2 — does the repo still lint?**

```bash
make lint
```

Runs yamllint, ansible-lint, playbook syntax check, `packer validate`, `terraform fmt`,
and shellcheck. It catches YAML damage and broken templating, but it cannot tell whether
a package installs.

**Tier 3 — does the image still build?** `make image` takes 30–60 minutes and needs
`/dev/kvm`. Don't run it by default. Offer it when a change is risky — a new repo, a
package with heavy dependencies, anything touching a role — and let the user decide.

Whatever ran, report it plainly. If only tiers 1 and 2 ran, say the change is
lint-clean and the package exists, and that no image was built.

## Step 7 — Commit and push

Commit only after verification passes, then **use the `commit` skill** — it owns the
message format, the changelog, staging, validation and the push. Do not hand-write a
`git commit` here; a second commit convention living in this file is exactly how the
two drift apart.

Two things to carry into it from the work above:

- **A package added or removed is user-facing**, so it earns a `CHANGELOG.md` entry
  under `Added`, `Changed` or `Removed`. Scope it `image` — that is what the reader
  cares about:

  ```
  feat(image): add Tailscale from the upstream apt repository
  ```

- **Say what was rejected and why** in the body, briefly. Which source was chosen over
  which alternative is the only thing that explains an odd-looking entry six months
  later:

  ```
  Ubuntu's archive package lags upstream by months, and Tailscale expects
  to self-update against its own repo.
  ```

The Step 6 verification report goes to the user in chat, not into the commit body. Tell
them what was verified, what was not, and specifically whether an image was built —
"verified" must never be heard as "built and booted".

### Where it goes

**Never commit to `main`.** Every change goes on its own branch and reaches
`main` through a pull request, which is what lets several changes be worked on at
once and what puts CI between a change and the trunk. Branch protection enforces
this, but do not rely on the rule to catch you.

```bash
git switch -c "change/<slug>"          # fix/<slug> for repo or CI bugs, not the image
# then hand off to the `commit` skill: it stages the specific files, writes the
# conventional message, updates CHANGELOG.md and pushes
gh pr create --fill
gh pr merge --squash --auto            # lands itself once lint and apply are green
```

**The PR title becomes the commit on `main`,** because branches are squash-merged.
`--fill` takes that title from the branch's single commit, so a conventional commit
subject carries through by itself — but check it, since a branch with several commits
gets a title from the first one only.

`--auto` rather than merging directly: `apply` converges a real machine twice and
takes twelve to fifteen minutes, so waiting on it interactively wastes the
session. The PR merges itself when both required checks pass, and stays open with
a red check if they do not.

One logical change per branch. Squash-merging means the branch becomes a single
commit on `main`, so if the work uncovered something worth recording -- a bug
found on the way, an alternative rejected -- it belongs in the squash body, not
in a commit that will be collapsed. Keep that body to the convention too: the
squash body is the commit body once it lands.

Working on several changes at once means a worktree each, so the branches do not
fight over one checkout:

```bash
git worktree add ../workstation-<slug> -b change/<slug>
```

`docs/` is generated from `group_vars`, so parallel branches will conflict there.
`lint-docs` is advisory on pull requests for exactly that reason: regenerate with
`make docs-config` after merging rather than fighting it on the branch.

On a network failure retry up to four times with backoff (2s, 4s, 8s, 16s).

Then tell the user what landed, what was verified, and what was not.
