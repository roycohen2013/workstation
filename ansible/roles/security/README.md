<!-- DOCSIBLE START -->

# 📃 Role overview

## security



Description: Firewall policy, SSH hardening and unattended upgrades.
















### Tasks


#### File: tasks/main.yml

| Name | Module | Has Conditions | Comments |
| ---- | ------ | -------------- | -------- |
| Refuse to build an image with the SSH server on | ansible.builtin.assert | True | An image cannot ship the SSH server on safely. Its hardening drop-in sets
PasswordAuthentication no, and Packer is connected to the build VM over SSH
with a password: writing it mid-build would lock Packer out partway through,
and leaving it out would ship a running sshd on stock settings to every
machine flashed from the image. So the flag is live-only, and refused here in
the first minutes of a build rather than discovered on a laptop. |
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
| Ensure sshd's privilege separation directory exists | ansible.builtin.file | True | `sshd -t`, the validate step below, refuses to run without /run/sshd:
"Missing privilege separation directory: /run/sshd". Nothing creates that
directory at boot -- openssh-server ships no tmpfiles.d entry; it exists only
while ssh.service runs, via RuntimeDirectory=sshd, and goes again when it
stops. So wherever the server is installed but not running, the first
converge that writes the drop-in failed: a fresh CI runner, and a freshly
flashed machine, whose image ships the server disabled and gets this drop-in
only at `make apply`. /run is tmpfs, so nothing here outlives a reboot, and a
running service simply adopts the directory. |
| Configure SSH server | ansible.builtin.copy | True |  |
| Set SSH server run state | ansible.builtin.systemd | True |  |
| Configure unattended upgrades | ansible.builtin.copy | True | --- Automatic updates -------------------------------------------------------- |
| Enable periodic apt activity | ansible.builtin.copy | True |  |

#### File: tasks/seal.yml

| Name | Module | Has Conditions | Comments |
| ---- | ------ | -------------- | -------- |
| Leave the SSH server disabled in the image | ansible.builtin.systemd | False | Disabled rather than stopped: Packer is connected over this very service,
and stopping it would cut the build off before seal finishes. It takes
effect at the next boot, which is the target machine's first.
roles/security refuses to build an image with workstation_ssh_server_enabled
set, so here it is always off. |
| Remove SSH host keys | ansible.builtin.shell | False | Every machine flashed from the image would otherwise present the same host
keys, which defeats host verification across all of them. |
| Regenerate SSH host keys on the target machine's first boot | ansible.builtin.copy | False |  |







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
