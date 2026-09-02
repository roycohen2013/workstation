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
| Fail early if the base wallpaper is missing | ansible.builtin.stat | True | --- Flatpak ------------------------------------------------------------------
--- Hostname and IP on the desktop -------------------------------------------
Stamped onto the wallpaper rather than drawn by a widget. See the note in
group_vars for why not conky and why not a GNOME extension. |
| Assert the base wallpaper exists | ansible.builtin.assert | True | Loud rather than silent: if a future Ubuntu drops this file, the converge
stops here with the path in the message, instead of installing a timer that
quietly renders nothing on every machine. |
| Install the desktop info renderer | ansible.builtin.copy | True |  |
| Install the desktop info user units | ansible.builtin.copy | True | A USER unit, not a system one: it needs the session's D-Bus to call gsettings,
and the wallpaper is a per-user setting. Installed to /etc/systemd/user and
enabled with `systemctl --global enable`, so every user who logs in gets it
without anyone running a per-user command -- which matters for an image that
is flashed onto machines other people log into. |
| Enable the desktop info timer for every user | ansible.builtin.systemd_service | True | scope: global rather than `command: systemctl --global enable` -- the module
does exactly this and is idempotent without a `creates:` guard pointing at an
implementation detail. ansible-lint's command-instead-of-module caught the
first version, which is the rule earning its place. |
| Install flatpak | ansible.builtin.apt | True |  |
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
