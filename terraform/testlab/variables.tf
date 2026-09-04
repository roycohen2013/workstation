variable "image_path" {
  type        = string
  description = "Absolute path to the qcow2 produced by `make image`."
}

# NOT "version": Terraform reserves that name for its special meaning inside
# module blocks, and a module that declares it cannot even initialise --
# `terraform init` fails before validate or apply is reached, so `make test`
# could never have worked. Local `make lint` did not catch it because
# lint-terraform only runs `fmt -check`; CI runs `validate`, which is what
# found it.
variable "image_version" {
  type        = string
  default     = "dev"
  description = "Build version, used to name the test volume."
}

variable "libvirt_uri" {
  type    = string
  default = "qemu:///system"
}

variable "storage_pool" {
  type    = string
  default = "default"
}

variable "network_name" {
  type        = string
  default     = "default"
  description = "libvirt network. Must hand out DHCP leases, since the test waits for one."
}

variable "memory" {
  type    = number
  default = 4096
}

variable "vcpus" {
  type    = number
  default = 2
}

variable "ovmf_code" {
  type    = string
  default = "/usr/share/OVMF/OVMF_CODE_4M.fd"
}

variable "ovmf_vars" {
  type    = string
  default = "/usr/share/OVMF/OVMF_VARS_4M.fd"
}
