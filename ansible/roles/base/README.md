<!-- DOCSIBLE START -->

# 📃 Role overview

## base



Description: Locale, timezone, user account, kernel tuning and a portable initramfs.
















### Tasks


#### File: tasks/main.yml

| Name | Module | Has Conditions | Comments |
| ---- | ------ | -------------- | -------- |
| Set timezone | community.general.timezone | False |  |
| Ensure locale is generated | community.general.locale_gen | False |  |
| Set system locale | ansible.builtin.copy | False |  |
| Configure console keyboard layout | ansible.builtin.lineinfile | False |  |
| Install base packages | ansible.builtin.apt | False |  |
| Remove unwanted packages | ansible.builtin.apt | True |  |
| Upgrade all packages | ansible.builtin.apt | False |  |
| Ensure login shell is installed | ansible.builtin.apt | True | --- Account ------------------------------------------------------------------ |
| Create the workstation user | ansible.builtin.user | False |  |
| Grant passwordless sudo | ansible.builtin.copy | False |  |
| Install authorized SSH keys | ansible.posix.authorized_key | True |  |
| Apply sysctl settings | ansible.posix.sysctl | False | --- Kernel tuning ------------------------------------------------------------ |
| Install zram-tools | ansible.builtin.apt | True |  |
| Configure zram | ansible.builtin.copy | True |  |
| Build a portable initramfs (MODULES=most) | ansible.builtin.lineinfile | False | --- Boot ---------------------------------------------------------------------
The single most important line in this repo for bare-metal portability.

Ubuntu's default initramfs (MODULES=dep) contains only the storage drivers
the BUILD machine needed. Flash that onto a laptop with a different NVMe or
SATA controller and the kernel cannot find its own root filesystem -- an
unbootable image, with no obvious cause. MODULES=most ships the full driver
set and costs a few tens of MB. |
| Configure GRUB | ansible.builtin.template | False |  |







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
