<!-- DOCSIBLE START -->

# 📃 Role overview

## apps



Description: Snaps, flatpaks, and the setup individual apps need once installed.
















### Tasks


#### File: tasks/main.yml

| Name | Module | Has Conditions | Comments |
| ---- | ------ | -------------- | -------- |
| Add the workstation user to the kvm group for Cowork | ansible.builtin.user | True | Claude Desktop's Cowork tab runs agentic work in a QEMU/KVM virtual machine.
It needs /dev/kvm and /dev/vhost-vsock, and only kvm group members can open
the latter -- so joining the group is required even where /dev/kvm alone is
already accessible.

This lives here, not in workstation_user_groups, because roles/base creates
the user long before these packages exist: the kvm group is created by the
qemu recommends pulled in just above, so joining it any earlier fails. |
| Find BalenaEtcher's desktop launcher | ansible.builtin.shell | True | --- BalenaEtcher ---------------------------------------------------------
Downloaded and installed by roles/pinned_downloads, which runs before this
role; what follows only makes it launch.

BalenaEtcher's Chromium sandbox routinely fails to initialise for reasons
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
| Install snaps | community.general.snap | True | --- Snaps -------------------------------------------------------------------- |
| Install the AppImage runtime dependency | ansible.builtin.apt | True | --- Nimbalyst ----------------------------------------------------------------
The AppImage itself is installed by roles/pinned_downloads, which runs before
this role; what follows integrates it with the desktop. |
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
