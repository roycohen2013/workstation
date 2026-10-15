<!-- DOCSIBLE START -->

# 📃 Role overview

## firstboot



Description: One-shot hook that adapts a generic image to the machine it was written to.
















### Tasks


#### File: tasks/main.yml

| Name | Module | Has Conditions | Comments |
| ---- | ------ | -------------- | -------- |
| Install first-boot dependencies | ansible.builtin.apt | False |  |
| Create the first-boot steps directory | ansible.builtin.file | False | Where roles drop their own first-boot steps, from their tasks/seal.yml. Made
here, before roles/seal runs those, so every step has somewhere to land. |
| Install first-boot script | ansible.builtin.template | False |  |
| Install first-boot service | ansible.builtin.copy | False |  |
| Create state directory | ansible.builtin.file | False |  |
| Arm the first-boot hook | ansible.builtin.file | False |  |
| Enable the first-boot service | ansible.builtin.systemd | False |  |







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
