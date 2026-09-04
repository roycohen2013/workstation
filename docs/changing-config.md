<!-- Moved out of README.md so the entry point stays short. Hand-written;
     not generated, unlike configuration.md / roles.md / packer.md /
     terraform.md, which `make docs-config` produces. -->

# Changing the configuration

Almost everything lives in **`ansible/group_vars/all.yml`** — it is data, not code:

```yaml
apps_apt_base:    [ripgrep, jq, tmux, ...]   # add a line, rebuild
apps_snap:        [{ name: code, classic: true }]
apps_flatpak:     [com.spotify.Client]
dev_mise_runtimes: { node: lts, python: "3.13" }
desktop_dconf:    [{ key: /org/gnome/..., value: "'prefer-dark'" }]
```

Then either `make apply` (this machine, now) or `make image` (a new artifact).

There are two ways to make that edit. If you have Claude Code, use the first one.

### Ask Claude (recommended, especially at first)

This repo ships a Claude Code skill at **`.claude/skills/config-change/`**. Open
Claude Code in the repo and say what you want in plain language — no need to know
which file or which list:

```
add duf and hyperfine, I keep apt installing them by hand
I want Tailscale, but from their repo not the Ubuntu archive
make the dock auto-hide and move it to the bottom
stop installing gimp
pin node to 22
```

It triggers on its own from phrasing like that. You can also invoke it explicitly
with `/config-change`.

It then walks a fixed path:

1. **Works out where the change belongs** — which list, or whether it needs a role.
2. **Traces what else it touches.** Adding a daemon is rarely just a package: this
   repo builds *one* image flashed onto *many* machines, so anything a package
   writes at install time gets shared by all of them. Installing Tailscale, for
   instance, starts `tailscaled`, which bakes a node key into the image — so
   `roles/seal` has to strip it.
3. **Asks a follow-up** only when the answer changes the edit (e.g. VS Code exists
   as a snap, a flatpak, *and* a Microsoft apt repo — those are not equivalent).
4. **Shows you a short plan and waits.** Nothing is edited before you approve, and
   the plan names anything from step 2 so a one-liner cannot quietly become a
   change to a role.
5. **Makes the edit**, matching the file's existing style.
6. **Verifies**, then runs `make lint`.
7. **Commits and pushes**, with a message explaining *why*, not just what.

**What step 5 is really for.** The expensive mistake in this repo is a name that
does not exist. Nothing catches it at edit time — `apt install` dies deep inside a
Packer run, 30–60 minutes in, after the base install and most of the provisioning.
So the skill checks first, using `scripts/verify-change.sh`, which you can also run
yourself:

```bash
.claude/skills/config-change/scripts/verify-change.sh apt      ripgrep neovim
.claude/skills/config-change/scripts/verify-change.sh snap     code
.claude/skills/config-change/scripts/verify-change.sh flatpak  com.spotify.Client
.claude/skills/config-change/scripts/verify-change.sh repo <key-url> <base-url> <suite> [component]
```

apt names are checked against the same `Packages` indexes apt itself reads, so the
answer is authoritative rather than a guess. It reports three outcomes, not two:

| Exit | Meaning |
|---|---|
| 0 | verified to exist |
| 1 | definitively does not exist (near-misses suggested) |
| 2 | could not check — offline or host blocked |

Exit 2 is deliberately **not** a pass. A checker that reports success when it
reached nothing launders a guess into a green tick, so the skill reports that case
as unverified rather than quietly proceeding.

The skill does **not** build an image. `make image` needs KVM and takes 30–60
minutes, so it stays your call — the skill offers it when a change looks risky and
tells you plainly what it did and did not prove.

### By hand

Nothing about the skill is load-bearing — it is a shortcut, not a gate. Edit
`ansible/group_vars/all.yml` directly, then `make lint`, then commit as usual.

Worth knowing if you go this route, because all three lint clean and fail later:

- **dconf values are GVariant literals.** A string needs its own inner quotes
  (`"'prefer-dark'"`), a uint needs its type prefix (`"uint32 300"`), a boolean is
  bare (`"true"`). Drop the inner quotes on a string and the dconf file fails to load.
- **A vendor repo's packages go in that repo entry's own `packages:` list**, never
  in `apps_apt_base` — otherwise apt tries to install them before the repo exists.
- **The keyring filename is derived from the entry's `name:`.** An entry named
  `tailscale` must say `signed-by=/etc/apt/keyrings/tailscale.gpg`. A mismatch
  produces a signature error that reads like a network fault.

Adding a third-party APT repo is data too — name, key URL, repo line, packages.
Keys are dearmoured into `/etc/apt/keyrings` and referenced with `signed-by`, so
no vendor key is trusted to sign anything outside its own repo.
