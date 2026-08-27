<!-- DOCSIBLE START -->

# 📃 Role overview

## apps



Description: Third-party APT repositories, snaps and flatpaks, all declared as data.










### Defaults

**These are static variables with lower priority**

#### File: defaults/main.yml

| Var          | Type         | Value       |
|--------------|--------------|-------------|
| [apps_repos_enabled](defaults/main.yml#L3)   | list | `[]` |    





### Tasks


#### File: tasks/main.yml

| Name | Module | Has Conditions | Comments |
| ---- | ------ | -------------- | -------- |
| Ensure keyring directories exist | ansible.builtin.file | False | --- Third-party APT repositories --------------------------------------------- |
| Select enabled repositories | ansible.builtin.set_fact | True | `enabled` is usually a template referencing a feature switch, which renders
to a string. selectattr() would truth-test that string, and a non-empty
"False" is truthy -- silently enabling a repository that is switched off.
An explicit `| bool` is the only reliable test here. |
| Fetch repository signing keys | ansible.builtin.get_url | False | Keys are dearmoured into /etc/apt/keyrings and referenced per-repo with
signed-by, rather than added to the deprecated global trusted keyring where
any one vendor key would be trusted to sign any package. |
| Install repository signing keys (dearmoured) | ansible.builtin.command | True | Key handling is two independent choices, because vendors differ on both:
key_path     where the keyring lands (default: /etc/apt/keyrings/<name>.gpg)
key_armoured whether to copy the .asc verbatim or dearmour it first

It matters because several vendors' packages register their own
sources.list.d entry naming a keyring path of their choosing -- if that file
does not exist, every later apt update fails with NO_PUBKEY. Matching the
vendor's documented layout keeps apt working whichever entry wins.
docker/hashicorp: defaults (dearmoured, our path)
claude-desktop:   armoured, vendor path
1password:        dearmoured, vendor path |
| Install repository signing keys (armoured, verbatim) | ansible.builtin.copy | True |  |
| Set keyring permissions | ansible.builtin.file | False |  |
| Add repositories | ansible.builtin.apt_repository | False |  |
| Create 1Password debsig directories | ansible.builtin.file | True | 1Password's debsig-verify policy. This verifies the .deb's own signature, in
addition to apt verifying the repository -- so it has to be in place before
the package installs, not after.

If apps_1password_debsig_key_id is wrong, these files land in a directory
dpkg never consults and the policy is silently inert. apt install still
succeeds, which is why goss asserts the paths rather than trusting them. |
| Record the debsig key id used | ansible.builtin.copy | True | Recorded so the image test asserts against the id actually used, rather than
duplicating the constant into the test suite where the two could drift. |
| Install 1Password debsig policy | ansible.builtin.get_url | True |  |
| Install 1Password debsig keyring | ansible.builtin.command | True |  |
| Stop Google Chrome managing its own apt source | ansible.builtin.copy | True | Chrome re-adds its own apt source and keyring -- from postinst and from a
daily cron job -- writing the same sources.list.d filename this role manages.
If its version wins and names a keyring we never created, every later apt
update fails with NO_PUBKEY. Chrome reads this file to decide whether to do
that, so it has to exist BEFORE the package installs. |
| Install packages from third-party repositories | ansible.builtin.apt | True |  |
| Remove downloaded key material | ansible.builtin.file | False |  |
| Add the workstation user to the kvm group for Cowork | ansible.builtin.user | True | Claude Desktop's Cowork tab runs agentic work in a QEMU/KVM virtual machine.
It needs /dev/kvm and /dev/vhost-vsock, and only kvm group members can open
the latter -- so joining the group is required even where /dev/kvm alone is
already accessible.

This lives here, not in workstation_user_groups, because roles/base creates
the user long before these packages exist: the kvm group is created by the
qemu recommends pulled in just above, so joining it any earlier fails. |
| Install snaps | community.general.snap | True | --- Snaps -------------------------------------------------------------------- |
| Install flatpaks | community.general.flatpak | True | --- Flatpaks ----------------------------------------------------------------- |







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
