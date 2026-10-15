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
| Make apt retry a failed download | ansible.builtin.copy | False | Before the first apt task, and before the apps role adds any repository:
apt's own retry is what makes every later fetch survive a blip, rather than
each Ansible task having to grow its own retry loop. |
| Install base packages | ansible.builtin.apt | False |  |
| Remove unwanted packages | ansible.builtin.apt | True |  |
| Upgrade all packages | ansible.builtin.apt | False | No autoclean here: the apt module ends the task after the upgrade, so it
never ran. The cache is cleared by apt's periodic autoclean on a running
machine (AutocleanInterval, security role) and by roles/seal in the image. |
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
| Set shell aliases in bashrc | ansible.builtin.blockinfile | False | One managed block rather than a line per alias: blockinfile owns the region
between its markers, so an alias dropped from base_bash_aliases is gone from
the file on the next converge. Appending at EOF puts these below Ubuntu's
`case $- in *i*) ;; *) return;; esac` guard, so they are defined for
interactive shells only -- which is all an alias is ever useful in. |
| Install the fastfetch login banner | ansible.builtin.template | True | /etc/profile.d, following the pattern roles/dotfiles already uses for its own
login hook: installed when enabled, removed when not, so switching the flag
off actually takes the banner away instead of leaving a stale file behind. |
| Remove the fastfetch login banner when disabled | ansible.builtin.file | True |  |
| Grant passwordless sudo | ansible.builtin.copy | False |  |
| Install authorized SSH keys | ansible.posix.authorized_key | True |  |
| Remove the superseded sysctl file | ansible.builtin.file | False | --- Kernel tuning ------------------------------------------------------------
99-, the conventional slot for local overrides. At boot systemd-sysctl applies
every sysctl.d file in lexicographic order, so a 99- file wins against the
distribution's own entries for the same keys -- 30-localsearch.conf for
fs.inotify.max_user_watches, 55-map-count.conf for vm.max_map_count. File
order only decides the boot-time result, though; it does nothing against a
package that applies one file by name at runtime. See the localsearch mask
below for the case that does exactly that. |
| Apply sysctl settings | ansible.posix.sysctl | False |  |
| Mask localsearch's inotify limit with ours | ansible.builtin.copy | True | localsearch's postinst runs `systemd-sysctl 30-localsearch.conf` on every
install and every upgrade. That applies its file alone -- no ordering against
ours -- and its file sets fs.inotify.max_user_watches to 65536, an eighth of
ours. So each localsearch update quietly dropped the limit until the next
reboot or converge, and editors watching large trees hit "System limit for
number of file watchers reached". It is also why the CI idempotence pass
reported this key changed on every run: the desktop role installs localsearch
after the task above, and the second converge put the value back.

systemd resolves a bare sysctl.d filename through its search path, where
/etc/sysctl.d shadows /usr/lib/sysctl.d. A file of the same name here carrying
our value turns their postinst's reset into a no-op, and changes nothing at
boot, where 99-workstation.conf already wins. It is written in base, before
the desktop role installs localsearch, so the very first install respects it. |
| Remove the localsearch mask when no watcher limit is set | ansible.builtin.file | True |  |
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
