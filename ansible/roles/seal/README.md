<!-- DOCSIBLE START -->

# 📃 Role overview

## seal



Description: Strips machine identity and build residue so the artifact is a clean template.
















### Tasks


#### File: tasks/main.yml

| Name | Module | Has Conditions | Comments |
| ---- | ------ | -------------- | -------- |
| Confirm this is a build image | ansible.builtin.stat | False |  |
| Refuse to seal anything that is not a build image | ansible.builtin.assert | False |  |
| Record image metadata | ansible.builtin.copy | False |  |
| Clean apt caches | ansible.builtin.apt | False | --- Package caches ----------------------------------------------------------- |
| Remove apt lists | ansible.builtin.shell | False |  |
| Blank machine-id | ansible.builtin.copy | False | --- Machine identity ---------------------------------------------------------
Every machine written from this image must generate its own. Sharing a
machine-id means colliding DHCP leases and indistinguishable journal
identities across every laptop and VM built from the same artifact. |
| Disable the SSH server in the image | ansible.builtin.systemd | False | The security role cannot do this during a build -- Packer is connected over
the very service it would be stopping -- so it lands here instead. Disabling
(not stopping) keeps the current session alive until shutdown. |
| Remove SSH host keys | ansible.builtin.shell | False |  |
| Clean cloud-init state | ansible.builtin.command | False | --- cloud-init ---------------------------------------------------------------
cloud-init did its job during the install. Left enabled, it would try to
reconfigure networking and users on the target machine at every boot. |
| Disable cloud-init | ansible.builtin.file | False |  |
| Rotate away the journal | ansible.builtin.command | False | --- Logs and history --------------------------------------------------------- |
| Truncate log files | ansible.builtin.shell | False |  |
| Remove shell history | ansible.builtin.shell | False |  |
| Remove build marker | ansible.builtin.file | False |  |
| Discard unused blocks | ansible.builtin.command | False | --- Free space ---------------------------------------------------------------
fstrim punches holes in the qcow2 for deleted blocks (the builder sets
discard=unmap), so the exported artifact reflects real usage rather than
every byte ever written during the build. |
| Install the final teardown script | ansible.builtin.template | False | --- Final teardown, executed at shutdown ------------------------------------ |







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
