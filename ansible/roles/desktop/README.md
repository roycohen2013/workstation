<!-- DOCSIBLE START -->

# 📃 Role overview

## desktop



Description: GNOME desktop, fonts, dconf system defaults and Flatpak support.
















### Tasks


#### File: tasks/main.yml

| Name | Module | Has Conditions | Comments |
| ---- | ------ | -------------- | -------- |
| Install debconf tooling | ansible.builtin.apt | True | Must run BEFORE the package installs: debconf is consulted by the postinst,
so preseeding afterwards would need a dpkg-reconfigure to take effect. |
| Preseed Wireshark to allow non-root packet capture | ansible.builtin.debconf | True |  |
| Install desktop packages | ansible.builtin.apt | False |  |
| Add the workstation user to the wireshark group | ansible.builtin.user | True | The group is created by wireshark-common's postinst, and only when the
preseed above enabled it -- so this has to come after the install. |
| Boot to the graphical target | ansible.builtin.file | False |  |
| Ensure dconf profile directory exists | ansible.builtin.file | False | --- GNOME settings -----------------------------------------------------------
Applied as system-wide dconf defaults rather than per-user `dconf write`.

This is not a stylistic choice: `dconf write` needs a live D-Bus session bus,
and there is no logged-in session inside a Packer build VM. System defaults
in /etc/dconf/db/local.d apply without one, survive a new user being created,
and still leave every setting overridable by the user afterwards. |
| Install dconf user profile | ansible.builtin.copy | False |  |
| Ensure dconf local db directory exists | ansible.builtin.file | False |  |
| Write GNOME defaults | ansible.builtin.template | False |  |
| Configure GDM | ansible.builtin.copy | False | --- Login manager ------------------------------------------------------------ |
| Install flatpak | ansible.builtin.apt | True | --- Flatpak ------------------------------------------------------------------ |
| Add flathub remote | community.general.flatpak_remote | True |  |







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
