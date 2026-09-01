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
| Install the SSH server | ansible.builtin.apt | True | --- SSH server ---------------------------------------------------------------
A laptop image usually wants sshd off. It is force-enabled during the build
because that is Packer's only way in; the seal role turns it back off.

Nothing here can assume an SSH server exists. Ubuntu Desktop ships only the
client, which creates /etc/ssh/ssh_config.d -- note the missing "d" -- and
not the /etc/ssh/sshd_config.d that the drop-in below writes into, nor the
sshd binary its validate step runs, nor the ssh unit the task after it
manages. The image never hit this because Packer's autoinstall installs the
server for its own use, so `make apply` on a stock desktop install was the
first thing to try configuring a server that was not there, and died with
"Destination directory /etc/ssh/sshd_config.d does not exist". |
| Check whether an SSH server is installed | ansible.builtin.stat | True | Distinguishes "switched off on a machine that has one" -- where the hardening
drop-in and an explicit stop are both still wanted -- from "switched off on a
machine that never had one", where there is nothing to configure or stop. |
| Configure SSH server | ansible.builtin.copy | True |  |
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
