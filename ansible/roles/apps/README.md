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
| Ensure the key cache exists | ansible.builtin.file | False | Keys are dearmoured into /etc/apt/keyrings and referenced per-repo with
signed-by, rather than added to the deprecated global trusted keyring where
any one vendor key would be trusted to sign any package.
Kept, not deleted afterwards, and out of /tmp. get_url compares an existing
file against what it fetches and reports ok when they match -- but only if
the file is still there. Deleting it made this task, and the dearmour and
apt_repository tasks below it, report changed on every single converge; the
CI idempotence pass is what surfaced that. /var/cache rather than /tmp so it
also survives a reboot. This is public key material, a few KB per vendor. |
| Fetch repository signing keys | ansible.builtin.get_url | False |  |
| Install repository signing keys (dearmoured) | ansible.builtin.command | True | Key handling is two independent choices, because vendors differ on both:
key_path     where the keyring lands (default: /etc/apt/keyrings/<name>.gpg)
key_armoured whether to copy the .asc verbatim or dearmour it first

It matters because several vendors' packages register their own
sources.list.d entry naming a keyring path of their choosing -- if that file
does not exist, every later apt update fails with NO_PUBKEY. Matching the
vendor's documented layout keeps apt working whichever entry wins.
docker:           defaults (dearmoured, our path)
claude-desktop:   armoured, vendor path
1password:        dearmoured, vendor path
hashicorp:        dearmoured, vendor path -- see the note in group_vars |
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
| Add the workstation user to the kvm group for Cowork | ansible.builtin.user | True | Claude Desktop's Cowork tab runs agentic work in a QEMU/KVM virtual machine.
It needs /dev/kvm and /dev/vhost-vsock, and only kvm group members can open
the latter -- so joining the group is required even where /dev/kvm alone is
already accessible.

This lives here, not in workstation_user_groups, because roles/base creates
the user long before these packages exist: the kvm group is created by the
qemu recommends pulled in just above, so joining it any earlier fails. |
| Check the installed BalenaEtcher version | ansible.builtin.command | True | --- BalenaEtcher ---------------------------------------------------------
No apt repository exists in current vendor docs -- only a versioned .deb
from GitHub releases, installed the way the vendor itself documents:
`apt install ./balena-etcher_*_amd64.deb`. ansible.builtin.apt's deb: param
is exactly that -- apt, not raw dpkg, so dependencies resolve against the
configured archive automatically.
Gated on what is already installed. The .deb is ~150MB and is deleted after
installing, so without this it was re-downloaded on every converge and this
task, the install and the cleanup all reported changed forever -- which is
what the CI idempotence pass reports. Deleting it is still right: keeping
150MB of installer in the image to gain idempotence would be a bad trade,
so the version check provides it instead. |
| Download BalenaEtcher | ansible.builtin.get_url | True |  |
| Install BalenaEtcher | ansible.builtin.apt | True |  |
| Find BalenaEtcher's desktop launcher | ansible.builtin.shell | True | BalenaEtcher's Chromium sandbox routinely fails to initialise for reasons
that have nothing to do with security here -- a setuid helper with the
wrong permissions, a restrictive kernel, running inside a VM -- and when it
does, the app refuses to launch at all rather than degrading. --no-sandbox
is upstream's own documented workaround. It is forced unconditionally,
rather than left to whoever launches it to remember, because the failure
mode without it is Etcher not starting at the exact moment you are trying
to flash a drive.

The binary to wrap is discovered from the package's own .desktop file
rather than a hardcoded path: electron-builder's install layout has varied
across releases, and a guessed path that turns out wrong would silently
skip the wrapper instead of failing loudly. |
| Read its Exec line | ansible.builtin.shell | True |  |
| Resolve the real binary the launcher points at | ansible.builtin.shell | True |  |
| Fail loudly if the real binary could not be resolved | ansible.builtin.assert | True |  |
| Move the real binary aside | ansible.builtin.command | True |  |
| Install the --no-sandbox wrapper in its place | ansible.builtin.copy | True |  |
| Remove the downloaded BalenaEtcher package | ansible.builtin.file | True |  |
| Install snaps | community.general.snap | True | --- Snaps -------------------------------------------------------------------- |
| Install the AppImage runtime dependency | ansible.builtin.apt | True | --- Flatpaks -----------------------------------------------------------------
--- Nimbalyst ----------------------------------------------------------------
Distributed as an AppImage and nothing else on Linux. Unlike BalenaEtcher
below, the file is kept in place rather than downloaded and deleted: get_url
with a checksum re-verifies an existing file and reports ok, so a converge
does not re-fetch 470MB. The download/delete pairs elsewhere in this role are
why the CI idempotence pass reports changes on every run. |
| Create the Nimbalyst directory | ansible.builtin.file | True |  |
| Install Nimbalyst | ansible.builtin.get_url | True |  |
| Extract and install the Nimbalyst icon | ansible.builtin.shell | True | The AppImage carries its own icon, so it is taken from there rather than
committed as a binary blob. Extracting a single path costs 36KB, not the
~1GB a full --appimage-extract would; guarded on the INSTALLED icon rather
than on the extraction directory, so cleaning up the temporary tree does not
make this re-run forever. |
| Install the Nimbalyst desktop entry | ansible.builtin.copy | True | Mirrors the entry inside the AppImage, with an absolute Exec. --no-sandbox is
not this repo being cautious: it is what the vendor's own desktop entry ships,
and Ubuntu sets kernel.apparmor_restrict_unprivileged_userns=1, which stops an
unpackaged Electron app from creating its sandbox at all. |
| Link Nimbalyst onto PATH | ansible.builtin.copy | True |  |
| Install flatpaks | community.general.flatpak | True |  |







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
