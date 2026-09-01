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
| Install docsible | ansible.builtin.command | False | --- Repo tooling -------------------------------------------------------------
The rest of what `make lint` needs is apt data in apps_apt_dev. docsible is
not: it generates the per-role README files that `make lint-docs` checks for
staleness, and it is published on PyPI only. Ubuntu's Python is externally
managed (PEP 668), so a plain `pip install` refuses to run at all -- hence
pipx, which builds it an isolated venv.

--global is the part that matters. Without it pipx installs into the calling
user's ~/.local/bin, and this image is flashed onto machines rather than
built per-user: a tool in one home directory is off PATH for everyone else,
and disappears with that home if the user is recreated. --global puts the
venv in /opt/pipx and links the app into /usr/local/bin instead -- confirmed
against pipx 1.8.0's own --help, the version resolute ships, rather than
assumed from current docs. |
| Download terraform-docs | ansible.builtin.get_url | False | terraform-docs is neither in the Ubuntu archive nor on PyPI, so it is
fetched as a pinned release tarball. checksum: makes a tampered or truncated
download fail the task outright rather than unpacking something unverified. |
| Install terraform-docs | ansible.builtin.unarchive | False | The tarball holds the bare binary at its root, so extra=... would scatter
LICENSE and README into /usr/local/bin alongside it. |
| Remove the downloaded terraform-docs archive | ansible.builtin.file | False |  |
| Add user to the docker group | ansible.builtin.user | True | --- Docker ------------------------------------------------------------------- |
| Enable docker | ansible.builtin.systemd | True |  |
| Install mise | ansible.builtin.get_url | True | --- Language runtimes --------------------------------------------------------
mise keeps toolchains in the user's home rather than the system, so runtime
versions can be bumped without a rebuild -- and so the image stays generic. |
| Run mise installer | ansible.builtin.command | True |  |
| Ensure mise config directory exists | ansible.builtin.file | True | Must run BEFORE the copy below: ansible.builtin.copy does not create missing
parent directories, and mise's installer does not create ~/.config/mise
until it is actually invoked -- which "Run mise installer" above does not
do. Copying config.toml first fails with "Destination directory ... does
not exist" on exactly the fresh install this role is meant for. |
| Declare global runtime versions | ansible.builtin.copy | True |  |
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
