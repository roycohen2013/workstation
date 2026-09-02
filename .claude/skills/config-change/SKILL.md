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

## Step 1 — Locate where the change belongs

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

Commit only after verification passes. Stage the specific files changed, not `-A`.

Write a subject line naming the actual change, and a body explaining *why* — which
source was chosen and what was rejected. Six months later that reasoning is the only
thing that explains an odd-looking entry.

```
Add Tailscale from the upstream apt repository

Ubuntu's archive package lags upstream by several months, and Tailscale
expects to self-update against its own repo.

Verified: repo key, suite and component resolve for resolute; make lint
passes. No image build.
```

Push to the branch already checked out:

```bash
git push -u origin "$(git branch --show-current)"
```

Never switch branches or push somewhere else without asking first. On a network
failure retry up to four times with backoff (2s, 4s, 8s, 16s). If the repo has a
default branch other than this one and no open PR exists for it, open a draft PR.

Then tell the user what landed, what was verified, and what was not.
