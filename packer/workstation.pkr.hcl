# Builds the golden workstation image.
#
# Flow: QEMU boots the Ubuntu installer -> subiquity runs unattended from
# http/user-data -> Packer connects over SSH -> Ansible provisions everything
# -> the seal role strips machine identity -> qcow2 + raw are exported.
#
# The same Ansible playbook runs against a live machine via `make apply`, so
# the image is a cached snapshot of the desired state, not a separate one.

packer {
  required_version = ">= 1.11.0"

  required_plugins {
    qemu = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/qemu"
    }
    ansible = {
      version = ">= 1.1.1"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

locals {
  artifact_name = "${var.image_name}-${var.version}"
  build_date    = formatdate("YYYY-MM-DD'T'hh:mm:ssZ", timestamp())

  # Derived from ubuntu_release so the release is written down once. A
  # variable default cannot reference another variable, which is why these
  # are locals and why the corresponding variables default to empty rather
  # than to a URL with the release baked into it.
  iso_url = var.iso_url != "" ? var.iso_url : (
    "https://releases.ubuntu.com/${var.ubuntu_release}/ubuntu-${var.ubuntu_release}-live-server-amd64.iso"
  )
  iso_checksum = var.iso_checksum != "" ? var.iso_checksum : (
    "file:https://releases.ubuntu.com/${var.ubuntu_release}/SHA256SUMS"
  )
}

source "qemu" "workstation" {
  vm_name = "${local.artifact_name}.qcow2"

  iso_url      = local.iso_url
  iso_checksum = local.iso_checksum

  # --- Firmware -------------------------------------------------------------
  # UEFI with a q35 machine type, matching modern laptop firmware.
  efi_boot          = true
  efi_firmware_code = var.ovmf_code
  efi_firmware_vars = var.ovmf_vars
  machine_type      = "q35"

  # --- Resources ------------------------------------------------------------
  accelerator    = "kvm"
  cpus           = var.cpus
  memory         = var.memory
  disk_size      = var.disk_size
  disk_interface = "virtio-scsi"
  disk_cache     = "unsafe" # throwaway build VM; durability is irrelevant here
  # Lets the seal role's fstrim punch holes in the qcow2, so the exported
  # artifact reflects what is installed rather than every byte ever written.
  disk_discard       = "unmap"
  disk_detect_zeroes = "unmap"
  format             = "qcow2"
  net_device         = "virtio-net"
  headless           = var.headless

  output_directory = "${var.output_dir}/${local.artifact_name}"

  # --- Autoinstall seed -----------------------------------------------------
  # Packer serves http/ over HTTP; the kernel cmdline points cloud-init at it.
  http_directory = "${path.root}/http"

  # Drop to the GRUB console and boot the installer by hand. This is more
  # robust across Ubuntu releases than editing the preset menu entry, which
  # shifts position between point releases.
  #
  # If a future release fails to pick up the seed, the fallback spelling is
  # the older `ds=nocloud-net;s=...` -- still accepted, but deprecated.
  boot_wait = "5s"
  boot_command = [
    "c<wait3>",
    "linux /casper/vmlinuz autoinstall 'ds=nocloud;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/' ---<enter><wait3>",
    "initrd /casper/initrd<enter><wait3>",
    "boot<enter>",
  ]

  # --- Connection -----------------------------------------------------------
  # The installer runs unattended for a while before sshd is up; a long
  # timeout here is normal, not a hang.
  communicator           = "ssh"
  ssh_username           = var.build_username
  ssh_password           = var.build_password
  ssh_timeout            = "45m"
  ssh_handshake_attempts = 100

  # Detached, because the first thing it does is delete the account this SSH
  # session belongs to. --no-block hands it to systemd as a transient unit so
  # it outlives the connection Packer is about to lose.
  shutdown_command = "sudo systemd-run --no-block /usr/local/sbin/workstation-seal-final"
  shutdown_timeout = "10m"
}

build {
  name    = "workstation"
  sources = ["source.qemu.workstation"]

  # Wait out any cloud-init/apt activity still running from the install, so
  # the first Ansible task does not collide with a held dpkg lock.
  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to settle...'",
      "cloud-init status --wait || true",
      "sudo systemd-run --property=After=apt-daily.service --wait /bin/true || true",
    ]
  }

  # The whole configuration surface. Roles are idempotent and phase-aware:
  # workstation_phase=image here, =live when run by `make apply`.
  provisioner "ansible" {
    playbook_file = "${path.root}/../ansible/site.yml"
    galaxy_file   = "${path.root}/../ansible/requirements.yml"
    user          = var.build_username

    extra_arguments = concat(
      [
        "--extra-vars", "workstation_phase=image",
        "--extra-vars", "workstation_image_version=${var.version}",
        "--extra-vars", "workstation_build_date=${local.build_date}",
        "--extra-vars", "workstation_build_user=${var.build_username}",
        "--extra-vars", "ansible_sudo_pass=${var.build_password}",
        "--scp-extra-args", "'-O'",
      ],
      [for k, v in var.ansible_extra_vars : "--extra-vars=${k}=${v}"]
    )

    ansible_env_vars = [
      "ANSIBLE_HOST_KEY_CHECKING=False",
      "ANSIBLE_PIPELINING=True",
      "ANSIBLE_ROLES_PATH=${path.root}/../ansible/roles",
    ]
  }

  # Pull the inventory out of the VM. roles/manifest wrote these inside the
  # image (before seal, so package origins are still resolvable); these copies
  # are what the HTML report is rendered from, without needing to boot anything.
  provisioner "file" {
    source      = "/etc/workstation-manifest.json"
    destination = "${var.output_dir}/${local.artifact_name}/workstation-manifest.json"
    direction   = "download"
  }

  provisioner "file" {
    source      = "/etc/workstation-declared.json"
    destination = "${var.output_dir}/${local.artifact_name}/workstation-declared.json"
    direction   = "download"
  }

  provisioner "shell" {
    inline = ["mkdir -p /tmp/goss"]
  }

  provisioner "file" {
    source      = "${path.root}/../tests/goss/"
    destination = "/tmp/goss/"
  }

  # Assert the image is what we think it is, from inside it. This runs after
  # the seal role, so it also verifies the sealing itself -- blanked
  # machine-id, no host keys, firstboot armed.
  provisioner "shell" {
    script          = "${path.root}/../tests/goss/run-goss.sh"
    execute_command = "chmod +x {{ .Path }}; sudo -E {{ .Vars }} {{ .Path }}"
    environment_vars = [
      "GOSS_FILE=/tmp/goss/workstation.yaml",
    ]
  }

  # Export raw alongside qcow2 and record checksums.
  #   qcow2 -> VMs (libvirt/QEMU; convertible to vmdk/vdi)
  #   raw   -> dd straight onto a laptop's NVMe
  post-processor "shell-local" {
    inline = [
      "set -euo pipefail",
      "OUT='${var.output_dir}/${local.artifact_name}'",
      "echo '==> Converting to raw'",
      "qemu-img convert -p -f qcow2 -O raw \"$OUT/${local.artifact_name}.qcow2\" \"$OUT/${local.artifact_name}.raw\"",
      "echo '==> Compressing'",
      "zstd -${var.compression_level} -T0 --rm -f \"$OUT/${local.artifact_name}.raw\" -o \"$OUT/${local.artifact_name}.raw.zst\"",
      "zstd -${var.compression_level} -T0 -f \"$OUT/${local.artifact_name}.qcow2\" -o \"$OUT/${local.artifact_name}.qcow2.zst\"",
      "echo '==> Rendering documentation'",
      "python3 scripts/render-docs.py --manifest \"$OUT/workstation-manifest.json\" --declared \"$OUT/workstation-declared.json\" -o \"$OUT/docs.html\"",
      "echo '==> Checksums'",
      "(cd \"$OUT\" && sha256sum ${local.artifact_name}.* > SHA256SUMS)",
      "cat \"$OUT/SHA256SUMS\"",
    ]
  }

  post-processor "manifest" {
    output     = "${var.output_dir}/${local.artifact_name}/manifest.json"
    strip_path = true
    custom_data = {
      version        = var.version
      ubuntu_release = var.ubuntu_release
      build_date     = local.build_date
    }
  }
}
