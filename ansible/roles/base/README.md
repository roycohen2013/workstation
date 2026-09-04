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
| Set the colour prompt in bashrc | ansible.builtin.lineinfile | False | --- Interactive shell defaults -----------------------------------------------
Both files, or the change only half-lands: /etc/skel is the template for
users created later, and workstation_user's copy was taken from skel when the
task above created them, so editing skel alone leaves the existing user
untouched.

backrefs: true on the colour prompt is load-bearing. Without it lineinfile
APPENDS when the regexp does not match, and an appended
force_color_prompt=yes is inert: Ubuntu's .bashrc reads the variable at the
prompt block and then `unset`s it a few lines later, so anything set after
that point has no effect. With backrefs the task edits in place or does
nothing, which is the only correct behaviour here. |
| Set history sizes in bashrc | ansible.builtin.lineinfile | False | No backrefs here, deliberately: appending is a correct fallback for these
two. They are plain assignments that nothing unsets, so a later line wins if
a future Ubuntu stops shipping the defaults. |
| Grant passwordless sudo | ansible.builtin.copy | False |  |
| Install authorized SSH keys | ansible.posix.authorized_key | True |  |
| Remove the superseded sysctl file | ansible.builtin.file | False | --- Kernel tuning ------------------------------------------------------------
99-, not 60-. sysctl.d files apply in lexicographic order across
/usr/lib/sysctl.d and /etc/sysctl.d, and the distribution already ships
entries that set values this repo also sets -- 30-localsearch.conf claims
fs.inotify.max_user_watches, 55-map-count.conf claims vm.max_map_count. At
60- this file happens to win against those, but it loses to anything in the
90s, which is where images and provisioning tools conventionally put their
own overrides. The CI idempotence pass showed exactly that: on a runner,
fs.inotify.max_user_watches was reported changed on every converge because
something applied after us put it back. 99- is the conventional slot for
local overrides and is what this file should always have used. |
| Apply sysctl settings | ansible.posix.sysctl | False |  |
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
