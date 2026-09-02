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
the state your running machine converges to — so a rebuild is for a clean slate or
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
[config-change skill](docs/changing-config.md#ask-claude-recommended-especially-at-first) works out where
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
make image      build the image (qcow2 + raw)
make iso        build an unattended installer ISO
make test       boot the built image in libvirt and verify
make apply      converge THIS machine to the config, no reimage
make apply-check  show what apply would change, without changing it
make publish    upload to the artifact bucket, move the channel
make fetch      download the latest published image
make flash DEV=/dev/sdX   write an image to a disk
make docs       render this build's contents as a browsable HTML report
make docs-config  regenerate the committed reference docs under docs/
make lint       run every linter
```

## Where the rest is documented

This file stays short on purpose. Everything else lives in `docs/`, and
`make docs-config` regenerates the reference half of it from source.

| Document | Covers |
|---|---|
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | **Start here when something breaks** -- organised by the exact error text |
| [docs/changing-config.md](docs/changing-config.md) | Adding software, changing settings, and the Claude skill that does it for you |
| [docs/hardware-install.md](docs/hardware-install.md) | Getting an image onto a laptop, and what happens on first boot |
| [docs/image-contents.md](docs/image-contents.md) | Knowing what is actually inside a built image |
| [docs/publishing.md](docs/publishing.md) | Uploading artifacts and moving the channel |
| [docs/secrets.md](docs/secrets.md) | What is deliberately not in this repo, and where it goes instead |
| [docs/configuration.md](docs/configuration.md) | Generated: every setting in `group_vars/all.yml` |
| [docs/roles.md](docs/roles.md) | Generated: index of the Ansible roles |

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
scripts/doctor.sh            `make doctor` -- environment preflight
docs/                        reference docs; the generated half is rebuilt by
                             `make docs-config` and CI fails if it drifts
TROUBLESHOOTING.md           failures by error text
versions.env                 tool versions CI installs
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
- **`apply.yml`** runs the live half of the playbook for real, on a runner,
  whenever `ansible/` changes and weekly. It then runs it a *second* time and
  reports how much changed — a playbook that never settles is broken in a way
  a single run cannot show. This is the only CI job that executes the config
  rather than analysing it.
- **`build.yml`** runs on a tag, on demand, or weekly. It is not run per-commit
  on purpose — a full build is 30-60 minutes and several GB of upload.

Bare-metal boot is the one thing CI cannot verify. That needs your hardware and
a USB stick.
