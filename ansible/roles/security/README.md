<!-- DOCSIBLE START -->

# 📃 Role overview

## security



Description: Firewall policy, SSH hardening and unattended upgrades.
















### Tasks


#### File: tasks/main.yml

| Name | Module | Has Conditions | Comments |
| ---- | ------ | -------------- | -------- |
| Install security packages | ansible.builtin.apt | False |  |
| Set UFW default incoming policy | community.general.ufw | True | --- Firewall ----------------------------------------------------------------- |
| Set UFW default outgoing policy | community.general.ufw | True |  |
| Open configured ports | community.general.ufw | True |  |
| Enable UFW | community.general.ufw | True |  |
| Configure SSH server | ansible.builtin.copy | True | --- SSH server ---------------------------------------------------------------
A laptop image usually wants sshd off. It is force-enabled during the build
because that is Packer's only way in; the seal role turns it back off. |
| Set SSH server run state | ansible.builtin.systemd | True |  |
| Configure unattended upgrades | ansible.builtin.copy | True | --- Automatic updates -------------------------------------------------------- |
| Enable periodic apt activity | ansible.builtin.copy | True |  |







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
