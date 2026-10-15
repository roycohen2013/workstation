<!-- DOCSIBLE START -->

# 📃 Role overview

## hardware



Description: Laptop firmware, power and thermal packages, installed into every image.
















### Tasks


#### File: tasks/main.yml

| Name | Module | Has Conditions |
| ---- | ------ | -------------- |
| Install hardware support packages | ansible.builtin.apt | False |
| Detect virtualisation | ansible.builtin.set_fact | False |
| Set power management service state | ansible.builtin.systemd | True |

#### File: tasks/seal.yml

| Name | Module | Has Conditions | Comments |
| ---- | ------ | -------------- | -------- |
| Leave power services disabled in the image | ansible.builtin.systemd | False | Disabled in the artifact: tlp on a VM throttles a machine that has no battery
to save, and the image is built in one. On a live machine
tasks/main.yml decides from Ansible's virtualisation fact; on a flashed one
the first-boot step below decides, because Ansible is not there to. |
| Enable power management on the target machine's first boot, on metal only | ansible.builtin.copy | False |  |







## Author Information
workstation

#### License

MIT

#### Minimum Ansible Version

2.15

#### Platforms

No platforms specified.

#### Dependencies

No dependencies specified.
<!-- DOCSIBLE END -->
