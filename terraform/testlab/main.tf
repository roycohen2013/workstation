# Ephemeral VM for verifying a freshly built image.
#
# `make image` proves the build completed; this proves the result actually
# boots. Those are different claims, and only the second one catches a broken
# bootloader, a missing initramfs module, or a firstboot script that fails on
# a disk it has never seen.
#
# Deliberately UEFI, matching packer/workstation.pkr.hcl: testing under a boot
# path the real hardware will never use would not be testing much.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8"
    }
  }
}

provider "libvirt" {
  uri = var.libvirt_uri
}

# A copy, not the artifact itself: the VM writes to its disk on boot (firstboot
# resizes the filesystem and regenerates identity), and the build output must
# stay pristine for publishing.
resource "libvirt_volume" "root" {
  name   = "workstation-testlab-${var.version}.qcow2"
  pool   = var.storage_pool
  source = var.image_path
  format = "qcow2"
}

resource "libvirt_domain" "workstation" {
  name      = "workstation-testlab"
  memory    = var.memory
  vcpu      = var.vcpus
  autostart = false

  # OVMF, so the image's ESP and GRUB install are exercised for real.
  firmware = var.ovmf_code
  nvram {
    file     = "/var/lib/libvirt/qemu/nvram/workstation-testlab_VARS.fd"
    template = var.ovmf_vars
  }

  cpu {
    mode = "host-passthrough"
  }

  disk {
    volume_id = libvirt_volume.root.id
  }

  network_interface {
    network_name   = var.network_name
    wait_for_lease = true
  }

  # Serial console is the only way to watch firstboot when the graphical
  # session has not come up yet -- which is exactly when it matters.
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}
