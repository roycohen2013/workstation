# workstation

Infrastructure as code for a personal Ubuntu workstation image.

One declarative configuration produces a bootable system that runs **either as
a virtual machine or directly on laptop hardware**. Edit a YAML file, rebuild,
pull the image down wherever you need it.

---

## The idea

Most "dotfiles + setup script" repos drift: the script that built the machine
and the machine itself slowly diverge, and nobody dares re-run the script.

This repo avoids that by running **one Ansible playbook in two phases**:

| Phase | Where | Invoked by |
|---|---|---|
| `image` | inside a Packer build VM | `make image` |
| `live`  | against the machine you are on | `make apply` |

Same roles, same variables, same result. The image is a *cached snapshot* of
the state your live machine converges to — so a rebuild is for a clean slate or
a new machine, not for routine changes.

```
ansible/group_vars/all.yml     <- you edit this
        |
        v
   ansible/site.yml            <- one playbook, two phases
        |
   +----+--------------------------------+
   |                                     |
   v (phase=image)                       v (phase=live)
Packer -> qcow2 + raw               this running machine
   |                                  (make apply)
   +-> VM  (import qcow2)
   +-> laptop (dd the raw image)
   +-> installer ISO (make iso)
```

## Tools, and what each is for

- **Packer** drives an unattended Ubuntu install into a virtual disk, hands it
  to Ansible, then seals and exports the result.
- **Ansible** is the configuration itself — packages, desktop, services. This
  is the layer you touch regularly.
- **Terraform** provisions the artifact bucket, and boots each fresh image in a
  throwaway libvirt VM to prove it actually starts.

## Quickstart

```bash
# Ubuntu host
sudo apt install qemu-system-x86 qemu-utils ovmf xorriso zstd ansible make
# plus Packer: https://developer.hashicorp.com/packer/install

git clone https://github.com/roycohen2013/workstation.git
cd workstation

$EDITOR ansible/group_vars/all.yml   # set workstation_user, pick your apps
make image                           # ~30-60 min
make test                            # boot it in libvirt and check it comes up
```

New here and using Claude Code? You do not have to learn the layout of
`group_vars/all.yml` first. Open Claude Code in the repo and say what you want —
*"add ripgrep and fzf"*, *"make the dock auto-hide"* — and the bundled
[config-change skill](#ask-claude-recommended-especially-at-first) works out where
it goes, shows you a plan before touching anything, checks the packages exist, and
lints before it commits.

Output lands in `build/workstation-<version>/`:

| File | Use |
|---|---|
| `*.qcow2.zst` | VMs — libvirt, QEMU, convertible to VMDK/VDI |
| `*.raw.zst` | `dd` straight onto a laptop's NVMe/SSD |
| `SHA256SUMS` | verify before writing to any disk |

Compression defaults to zstd level 12, not the more extreme levels the `zstd`
CLI supports. Measured on real binary content: level 19 took 9.4x as long as
level 12 for a 2.9-percentage-point smaller file — on a real ~16GB image,
roughly an hour versus a few minutes, and it does not get meaningfully faster
with more CPU cores (higher zstd levels do not scale with thread count the
way lower ones do). Override for a one-off publish where the smaller download is worth the wait:
`make image ARGS='-var compression_level=19'` — or edit
`compression_level`'s default in `packer/variables.pkr.hcl`.

If a build is interrupted — a crash, Ctrl-C, a reboot mid-compression — the
next `make image` retries cleanly rather than failing with "Output directory
... already exists." Nothing from the failed attempt needs manual cleanup.

## Everyday commands

**Coming back to this after a while, run `make doctor` first.** It checks in a
couple of seconds whether the machine still matches what the repo assumes --
KVM access, which `sudo` implementation is active, whether the pinned Ansible
collections are the ones actually loading, and whether apt's sources are
readable. Nearly every failure this repo has hit was environment drift of that
kind rather than broken config, and each one otherwise surfaced deep inside a
40-minute build. When something does break, `TROUBLESHOOTING.md` is organised
by the exact error text.

```
make doctor     check this machine still matches what the repo assumes
make image      build the golden image (qcow2 + raw)
make iso        build an unattended installer ISO
make test       boot the built image in libvirt and verify
make apply      converge THIS machine to the config, no reimage
make apply-check  show what apply would change, without changing it
make publish    upload to the artifact bucket, move the channel pointer
make fetch      download the latest published image
make flash DEV=/dev/sdX   write an image to a disk
make docs       render this build's contents as a browsable HTML report
make docs-config  regenerate the committed reference docs under docs/
make lint       run every linter
```

### If `make apply` hangs on the password and then times out

On Ubuntu 26.04, `/usr/bin/sudo` is `sudo-rs` rather than the classic
implementation. It deliberately refuses to display a caller-supplied `-p`
prompt verbatim, echoing it inside a `[sudo: ...]` annotation and prompting
with its own generic `Password:` instead. Ansible watches for the exact
key-tagged prompt it asked for, never sees it, and fails with:

```
Timed out waiting for become success or become password prompt.
```

The password is not the problem, and neither is anything in this repo -- plain
`sudo` works fine on such a machine. `make apply` handles this already: where
Ubuntu's classic `sudo.ws` binary is present it points Ansible at it via
`ansible_become_exe`, and where it is not, nothing changes. If you invoke
`ansible-playbook` by hand rather than through `make`, add the same flag:

```
-e ansible_become_exe=/usr/bin/sudo.ws
```

## Knowing what is in an image

Every build records what actually got installed and renders it beside the image:

| Output | What it answers |
|---|---|
| `docs.html` | Every package, version, size and **which repository it came from**, with search and filters. Published alongside the image. |
| `workstation-manifest.json` | The same data as JSON, also kept at `/etc/workstation-manifest.json` *inside* the image, so a running machine can answer "what am I?" |

```bash
make docs                                  # open this build's report
make docs-diff FROM=2026.08.20-a1b2 TO=2026.08.27-c3d4   # what changed between builds
```

**The build fails if the image does not match what you declared.** `roles/manifest`
compares `group_vars/all.yml` against what `dpkg` actually reports and stops the build
when something declared is missing — a package that silently failed to install used to
ship unnoticed. The comparison is one-way on purpose: undeclared packages are reported,
never failed, since that set is mostly `Recommends`.

That report is also where image growth becomes attributable. Enabling Cowork pulls in
`qemu-system-x86`, `ovmf` and `virtiofsd` through `claude-desktop`'s recommends; none of
them are declared anywhere, and the "installed but never declared" section is where they
show up.

Reference documentation for the configuration itself lives in [`docs/`](docs/), generated
from source by `make docs-config` and checked for staleness by CI. Each Ansible role also
carries its own generated `README.md`.

## Getting it onto a laptop

Two supported paths, both ending in the same configuration:

**Flash the golden image** — fastest, byte-identical to what you tested.

```bash
make fetch                                  # or use a local build
make flash DEV=/dev/nvme0n1
```

**Install from the ISO** — when the target disk layout is unknown, or you want
the real installer to handle drivers and partitioning.

```bash
make iso
scripts/flash.sh --device /dev/sdX --image build/workstation-<version>-installer.iso
```

> The ISO installs **unattended and wipes the target disk with no prompting**.
> Don't leave it in a machine you care about.

### What happens on first boot

A generic image cannot know what machine it landed on, so
`workstation-firstboot.service` runs once and adapts it:

1. Grows the root partition to fill the actual disk.
2. Generates a fresh machine-id and SSH host keys.
3. Reinstalls GRUB for this machine's firmware.
4. Sets the hostname.
5. Enables power management — only on real hardware, not in a VM.

Then it disables itself.

### Two details that make bare-metal boot work

These are the non-obvious parts, and both are easy to lose in a refactor:

- **`grub-install --removable`** writes the bootloader to
  `/EFI/BOOT/BOOTX64.EFI`, the UEFI fallback path. A normal install writes an
  NVRAM entry instead — and NVRAM lives in the motherboard, not on the disk, so
  it does not survive `dd` onto a different machine.
- **`MODULES=most`** in `/etc/initramfs-tools/initramfs.conf`. Ubuntu's default
  ships only the storage drivers the *build* machine needed. On unfamiliar
  hardware the kernel then cannot find its own root filesystem.

Both are asserted in `tests/goss/workstation.yaml`, so a regression fails the
build rather than a laptop.

## Changing the configuration

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

## Secrets

**Nothing personal is ever baked into an image.** No SSH private keys, no
tokens, no shell history, no machine-id. Images get uploaded to buckets and
written onto disks; treat every one as public.

Dotfiles are handled with [chezmoi](https://chezmoi.io): the image ships only
the binary, and your repo is pulled on first login. Set `dotfiles_repo` in
`group_vars/all.yml`.

The build account (`packer`/`packer`, hash committed in
`packer/http/user-data`) exists only inside the build VM and is deleted by
`roles/seal` before export. `tests/goss/workstation.yaml` asserts the machine
identity is blank in the finished artifact.

## Publishing

```bash
cd terraform/artifacts
terraform init && terraform apply     # creates the R2 bucket
eval "$(terraform output -raw usage)" # exports the env the scripts want
cd ../..

make publish     # upload + move the 'stable' channel pointer
make fetch       # on another machine
```

R2 rather than S3 because egress is free — pulling a multi-GB image down a few
times a month is the dominant cost otherwise. Any S3-compatible store works;
the scripts use the plain `aws` CLI, only adding a custom endpoint when
`AWS_ENDPOINT_URL` is set.

Want a real AWS S3 bucket instead — no Cloudflare account, or an existing AWS
setup? See [`docs/aws-s3-setup.md`](docs/aws-s3-setup.md).

## Repository layout

```
ansible/group_vars/all.yml   the config surface -- start here
ansible/site.yml             one playbook, both phases
ansible/roles/               base, security, desktop, apps, dev, dotfiles,
                             hardware, firstboot, seal
packer/                      build template + autoinstall seed
iso/                         autoinstall seed for the installer ISO
terraform/artifacts/         image bucket
terraform/testlab/           throwaway VM for verifying a build
tests/goss/                  assertions run inside the image during the build
scripts/                     flash, fetch, publish, build-iso
.claude/skills/config-change/  Claude Code skill for making a config change:
                             SKILL.md, scripts/verify-change.sh, evals/
```

## Requirements

- A Linux host with **KVM** (`/dev/kvm`) — image builds need hardware
  virtualisation.
- ~40 GB free disk for a build.
- Packer 1.11+, Terraform 1.6+, Ansible 2.15+, QEMU, OVMF, zstd, xorriso.

`make image` checks these before starting.

## CI

- **`lint.yml`** runs on every push: yamllint, ansible-lint, playbook syntax
  check in both phases, `packer validate`, `terraform validate`, shellcheck.
- **`build.yml`** runs on a tag, on demand, or weekly. It is not run per-commit
  on purpose — a full build is 30-60 minutes and several GB of upload.

Bare-metal boot is the one thing CI cannot verify. That needs your hardware and
a USB stick.
