output "ip_address" {
  value       = try(libvirt_domain.workstation.network_interface[0].addresses[0], "no lease yet")
  description = "Address the test VM picked up. A lease at all is the primary signal that the image booted and brought up networking."
}

output "console_command" {
  value       = "virsh --connect ${var.libvirt_uri} console workstation-testlab"
  description = "Watch the boot, including firstboot output."
}
