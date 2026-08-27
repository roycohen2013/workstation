<!-- DOCSIBLE START -->

# 📃 Role overview

## dev



Description: Development tooling, Docker group membership and mise-managed runtimes.
















### Tasks


#### File: tasks/main.yml

| Name | Module | Has Conditions | Comments |
| ---- | ------ | -------------- | -------- |
| Install development packages | ansible.builtin.apt | False |  |
| Link Debian-renamed binaries to their upstream names | ansible.builtin.file | False | fd and bat ship under alternate binary names on Debian/Ubuntu to avoid
clashes; link them to the names everyone actually types. |
| Add user to the docker group | ansible.builtin.user | True | --- Docker ------------------------------------------------------------------- |
| Enable docker | ansible.builtin.systemd | True |  |
| Install mise | ansible.builtin.get_url | True | --- Language runtimes --------------------------------------------------------
mise keeps toolchains in the user's home rather than the system, so runtime
versions can be bumped without a rebuild -- and so the image stays generic. |
| Run mise installer | ansible.builtin.command | True |  |
| Declare global runtime versions | ansible.builtin.copy | True |  |
| Ensure mise config directory is owned correctly | ansible.builtin.file | True |  |
| Install runtimes now (live phase only) | ansible.builtin.command | True | Toolchain downloads are large and version-sensitive. Installing them at
first login instead of build time keeps the image smaller and means a stale
image still lands on current runtimes. |







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
