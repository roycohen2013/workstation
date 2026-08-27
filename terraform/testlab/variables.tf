variable "image_path" {
  type        = string
  description = "Absolute path to the qcow2 produced by `make image`."
}

variable "version" {
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
