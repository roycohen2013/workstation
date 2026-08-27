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

Output lands in `build/workstation-<version>/`:

| File | Use |
|---|---|
| `*.qcow2.zst` | VMs — libvirt, QEMU, convertible to VMDK/VDI |
| `*.raw.zst` | `dd` straight onto a laptop's NVMe/SSD |
| `SHA256SUMS` | verify before writing to any disk |

## Everyday commands

```
make image      build the golden image (qcow2 + raw)
make iso        build an unattended installer ISO
make test       boot the built image in libvirt and verify
make apply      converge THIS machine to the config, no reimage
make apply-check  show what apply would change, without changing it
make publish    upload to the artifact bucket, move the channel pointer
make fetch      download the latest published image
make flash DEV=/dev/sdX   write an image to a disk
make lint       run every linter
```

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

Almost everything lives in **`ansible/group_vars/all.yml`**:

```yaml
apps_apt_base:    [ripgrep, jq, tmux, ...]   # add a line, rebuild
apps_snap:        [{ name: code, classic: true }]
apps_flatpak:     [com.spotify.Client]
dev_mise_runtimes: { node: lts, python: "3.13" }
desktop_dconf:    [{ key: /org/gnome/..., value: "'prefer-dark'" }]
```

Then either `make apply` (this machine, now) or `make image` (a new artifact).

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
the scripts use the plain `aws` CLI.

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
