<!-- DOCSIBLE START -->

# 📃 Role overview

## seal



Description: Strips machine identity and build residue so the artifact is a clean template.
















### Tasks


#### File: tasks/hooks.yml

| Name | Module | Has Conditions | Comments |
| ---- | ------ | -------------- | -------- |
| Find each role's image-phase hook | ansible.builtin.set_fact | False | Every roles/<role>/tasks/seal.yml, found rather than listed, so a role adds
its image-phase cleanup -- and the first-boot step that undoes it on the
target machine -- without editing this file. A hook runs whether or not its
role did (the desktop can be switched off), so each must be safe either way.
Sorted, so the order is the same on every build.

filetree, not fileglob: fileglob expands a wildcard only in the file name,
never in a directory, so roles/*/tasks/seal.yml silently matches nothing and
every hook is skipped. Both read the controller, where Packer's roles live. |
| Refuse to seal without finding any hooks | ansible.builtin.assert | False | An empty list would make every role's cleanup silently stop happening, which
is exactly how the fileglob version above failed; it must never pass quietly. |
| Run each role's image-phase hook | ansible.builtin.include_role | False |  |

#### File: tasks/main.yml

| Name | Module | Has Conditions | Comments |
| ---- | ------ | -------------- | -------- |
| Confirm this is a build image | ansible.builtin.stat | False |  |
| Refuse to seal anything that is not a build image | ansible.builtin.assert | False |  |
| Record image metadata | ansible.builtin.copy | False |  |
| Run each role's image-phase hook | ansible.builtin.import_tasks | False | --- Each role's own image-phase half ----------------------------------------- |
| Remove packages nothing depends on | ansible.builtin.apt | False | --- Package caches -----------------------------------------------------------
autoremove only. The apt module runs one cleanup per task and then exits, so
this used to say `autoclean: true` as well and never autoremoved anything:
packages orphaned after base's upgrade shipped in every image. autoclean is
not needed -- the task below deletes the downloaded .debs outright. |
| Remove apt lists | ansible.builtin.shell | False |  |
| Blank machine-id | ansible.builtin.copy | False | --- Machine identity ---------------------------------------------------------
Every machine written from this image must generate its own. Sharing a
machine-id means colliding DHCP leases and indistinguishable journal
identities across every laptop and VM built from the same artifact. |
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
