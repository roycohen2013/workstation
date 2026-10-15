<!-- DOCSIBLE START -->

# 📃 Role overview

## pinned_downloads



Description: Installs software fetched from a release URL, pinned by version and checksum.










### Defaults

**These are static variables with lower priority**

#### File: defaults/main.yml

| Var          | Type         | Value       |
|--------------|--------------|-------------|
| [pinned_downloads_enabled](defaults/main.yml#L2)   | list | `[]` |    





### Tasks


#### File: tasks/appimage.yml

| Name | Module | Has Conditions | Comments |
| ---- | ------ | -------------- | -------- |
| Create the directory for {{ pinned_downloads_item.name }} | ansible.builtin.file | False | Kept in place rather than downloaded and deleted: an AppImage is the
installed program, and get_url with a checksum re-verifies an existing file
and reports ok, so a converge does not re-fetch it. A version bump changes
the checksum, which is what makes get_url fetch the new release. |
| Install {{ pinned_downloads_item.name }} | ansible.builtin.get_url | False |  |

#### File: tasks/deb.yml

| Name | Module | Has Conditions | Comments |
| ---- | ------ | -------------- | -------- |
| Check the installed version of {{ pinned_downloads_item.name }} | ansible.builtin.command | False | Installed with apt rather than raw dpkg, so dependencies resolve against the
configured archive -- the `apt install ./<file>.deb` vendors document.

Gated on the installed version. The .deb is deleted after installing, because
keeping a 150MB installer in the image to gain idempotence is a bad trade --
but without the gate it was re-downloaded on every converge, and the
download, install and cleanup all reported changed forever, which is what
CI's idempotence pass reports. |
| Install {{ pinned_downloads_item.name }} | block | True |  |
| Download {{ pinned_downloads_item.name }} | ansible.builtin.get_url | False |  |
| Install the package for {{ pinned_downloads_item.name }} | ansible.builtin.apt | False |  |
| Remove the downloaded package for {{ pinned_downloads_item.name }} | ansible.builtin.file | False |  |

#### File: tasks/main.yml

| Name | Module | Has Conditions | Comments |
| ---- | ------ | -------------- | -------- |
| Check each pinned download is complete | ansible.builtin.assert | False | Checked up front, and for every entry including disabled ones, so a malformed
entry fails here with its name rather than halfway through a download -- or
not at all until someone switches it on.

'{version}' in url is the check that matters most: a URL with the version
written out would keep fetching the old release after a bump, whose checksum
no longer matches, and the failure would read as a tampered download. |
| Select enabled pinned downloads | ansible.builtin.set_fact | True | `enabled` is usually a template referencing a feature switch, which renders
to a string, and a non-empty "False" is truthy -- the same trap roles/apps
documents for apps_apt_repos. An explicit `| bool` is the only reliable test. |
| Install pinned downloads | ansible.builtin.include_tasks | False |  |

#### File: tasks/tarball.yml

| Name | Module | Has Conditions | Comments |
| ---- | ------ | -------------- | -------- |
| Check the installed version of {{ pinned_downloads_item.name }} | ansible.builtin.command | False | One binary out of a release archive, into /usr/local/bin. Gated on what the
installed binary reports, for the same reason as deb.yml: the archive is
deleted afterwards, so without the gate every converge re-fetched it.
Matched as a substring, because tools print their version inside a sentence
("terraform-docs version v0.24.0 <sha> linux/amd64") rather than alone. |
| Install {{ pinned_downloads_item.name }} | block | True |  |
| Download {{ pinned_downloads_item.name }} | ansible.builtin.get_url | False |  |
| Extract the binary for {{ pinned_downloads_item.name }} | ansible.builtin.unarchive | False | include, so only the binary lands: these archives carry LICENSE and
README at their root, which would otherwise scatter into /usr/local/bin. |
| Remove the downloaded archive for {{ pinned_downloads_item.name }} | ansible.builtin.file | False |  |







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
