<!-- Moved out of README.md so the entry point stays short. Hand-written;
     not generated, unlike configuration.md / roles.md / packer.md /
     terraform.md, which `make docs-config` produces. -->

# Getting it onto a laptop

Two supported paths, both ending in the same configuration:

**Flash the image** — fastest, byte-identical to what you tested.

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
