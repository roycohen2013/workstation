# Inputs for the workstation image build.
#
# Nothing here is secret. Override on the command line with -var, or in a
# .pkrvars.hcl file:  packer build -var-file=local.pkrvars.hcl packer/

# The single place the Ubuntu release is written down. The ISO URL and the
# checksum manifest are derived from it in locals (see workstation.pkr.hcl),
# and scripts/build-iso.sh reads this value rather than keeping its own copy,
# so bumping a release is a one-line change instead of four edits across two
# files that must all be found.
variable "ubuntu_release" {
  type        = string
  default     = "26.04"
  description = "Ubuntu LTS release to build from. The single source for the release everywhere."
}

# Both default to empty, meaning "derive from ubuntu_release". They exist only
# so a one-off build can point at a daily image or a local mirror without
# editing the release above.
variable "iso_url" {
  type        = string
  default     = ""
  description = "Override the installer ISO URL. Empty derives it from ubuntu_release."
}

variable "iso_checksum" {
  type = string
  # Derived as a file: URL to the published SHA256SUMS rather than a literal
  # hash, so a point release (26.04.1, .2, ...) needs no edit here at all.
  default     = ""
  description = "Override the ISO checksum. Empty derives a file: URL to the release's SHA256SUMS."
}

variable "image_name" {
  type        = string
  default     = "workstation"
  description = "Base name for output artifacts."
}

variable "version" {
  type        = string
  default     = "dev"
  description = "Build version stamp, e.g. 2026.08.27-a1b2c3d. Set by the Makefile."
}

variable "output_dir" {
  type        = string
  default     = "build"
  description = "Directory for build artifacts."
}

variable "disk_size" {
  type        = string
  default     = "24G"
  description = "Virtual disk size. firstboot grows the root partition to fill the real disk, so this only needs to hold the installed system."
}

variable "compression_level" {
  type        = number
  default     = 12
  description = <<-EOT
    zstd level for the exported artifacts. Measured on real binary content
    (not zeros or random data, which distort any level equally): level 19,
    the previous default, took 9.4x as long as level 12 for a 2.9-percentage-
    point smaller file -- on a real ~16GB image, roughly an hour versus a few
    minutes. zstd's higher levels do not scale with thread count the way
    lower ones do, so more CPU cores does not fix this; the level itself is
    the lever. Override with -var compression_level=19 for a one-off
    publish build where the smaller download is worth the wait.
  EOT
}

variable "cpus" {
  type    = number
  default = 4
}

variable "memory" {
  type        = number
  default     = 4096
  description = "Build VM memory in MB."
}

variable "headless" {
  type        = bool
  default     = true
  description = "Set false to watch the installer in a QEMU window while debugging."
}

# UEFI firmware. Laptops are UEFI-only, so the build VM is too -- the image is
# never exercised under a boot path it will not see on real hardware.
# Defaults are Ubuntu/Debian host paths (ovmf package).
# Fedora hosts: /usr/share/edk2/ovmf/OVMF_CODE.fd and OVMF_VARS.fd
variable "ovmf_code" {
  type    = string
  default = "/usr/share/OVMF/OVMF_CODE_4M.fd"
}

variable "ovmf_vars" {
  type    = string
  default = "/usr/share/OVMF/OVMF_VARS_4M.fd"
}

variable "build_username" {
  type        = string
  default     = "packer"
  description = "Throwaway account used only during the build. The seal role deletes it."
}

variable "build_password" {
  type        = string
  default     = "packer"
  description = "Throwaway build password. Never present in the finished image -- see roles/seal."
}

variable "ansible_extra_vars" {
  type        = map(string)
  default     = {}
  description = "Extra vars passed through to the playbook."
}
