<!-- DOCSIBLE START -->

# 📃 Role overview

## hardware



Description: Laptop firmware, power and thermal packages, installed into every image.
















### Tasks


#### File: tasks/main.yml

| Name | Module | Has Conditions | Comments |
| ---- | ------ | -------------- | -------- |
| Install hardware support packages | ansible.builtin.apt | False |  |
| Detect virtualisation | ansible.builtin.set_fact | False |  |
| Set power management service state | ansible.builtin.systemd | True |  |
| Leave power services disabled in the image | ansible.builtin.systemd | True | Leave them disabled in the artifact; firstboot enables them if it finds
itself on real hardware. |







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
