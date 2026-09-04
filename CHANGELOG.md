# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Nothing has been tagged yet — `build.yml` cuts a release from a `v*` tag, and no such
tag exists — so everything the project has ever done is still unreleased. Entries below
are reconstructed from git history up to the point this changelog was introduced; from
here on they are written one commit at a time, by the `commit` skill.

Only user-facing changes get an entry. Refactors, tests, documentation, CI, and
agent/skill configuration do not — see [CONTRIBUTING.md](CONTRIBUTING.md).

## [Unreleased]

### Added

- Claude Desktop, Claude Code and Nimbalyst, from their vendors' signed apt
  repositories.
- Google Chrome, installed from Google's apt repository.
- 1Password, installed from its apt repository with the vendor's debsig policy.
- Wireshark, configured so packet capture works without running it as root.
- Visual Studio Code, installed from Microsoft's apt repository.
- The GitHub CLI, from GitHub's own apt repository.
- LibreOffice Writer, Calc, Impress and Draw.
- Obsidian, from Flathub.
- Déjà Dup Backups.
- krdc, KDE's remote desktop client.
- BalenaEtcher, pinned to a GitHub release and always launched with `--no-sandbox`
  so it can write removable drives.
- fastfetch.
- The desktop wallpaper is stamped with the machine's hostname and IP address.
- A colour prompt and a larger shell history in the image's `bashrc`.
- `make doctor` checks whether this machine still matches what the repo assumes —
  KVM access, which `sudo` implementation is active, whether the pinned Ansible
  collections are the ones loading, and whether apt's sources are readable.
- `TROUBLESHOOTING.md`, organised by the exact error text a failure prints.
- Every build now records a manifest of what it actually contains, and fails if an
  installed package drifts from what the configuration declared.
- Each built image ships a self-contained `docs.html` describing its contents, with
  `make docs-diff FROM=… TO=…` to compare two builds.
- `make verify-repos` checks that every declared third-party apt repository and
  pinned download still resolves before a build depends on it.
- A guide for publishing images to a real AWS S3 bucket instead of the default
  Cloudflare R2 one.

### Changed

- Image compression level is now the `compression_level` build variable, defaulting
  to 12 instead of a hard-coded 19. Level 19 took roughly nine times longer for a
  2.9-percentage-point smaller image; override it with
  `make image ARGS='-var compression_level=19'` when size matters more than time.
- Visual Studio Code comes from Microsoft's apt repository rather than as a snap, so
  it updates with the rest of the system and integrates with the shell `code` command.
- Repeated `make apply` runs no longer re-download things that are already installed,
  and settle without reporting changes on a second pass.

### Removed

- conky, which never worked on this desktop.

### Fixed

- `make apply` no longer times out on Ubuntu 26.04, whose `sudo-rs` does not present
  the password prompt Ansible's become plugin expects.
- `make apply` no longer fails on a machine with no SSH server installed, and no
  longer fails on a fresh install where the mise configuration directory did not yet
  exist.
- GNOME desktop defaults actually apply: the dconf database is compiled after it is
  written.
- apt no longer refuses to read its sources because of a duplicate HashiCorp
  repository entry.
- `make image` now retries cleanly after an interrupted build instead of failing on
  the output directory the previous attempt left behind.
- `make iso` no longer corrupts the installer ISO's boot arguments, and finds the
  source ISO regardless of the directory the build runs from.
- `make test` works at all: the testlab Terraform module declared a variable named
  `version`, which Terraform reserves, so it could never initialise.
- Ansible output is readable again on current `community.general` releases, which
  removed the callback plugin this repo was configured to use.
- `make check-tools` reports missing `kvm` group membership up front, rather than
  letting the build fail 45 minutes later with a generic QEMU error.
- `make lint` survives a CRLF checkout and no longer crashes on unexpected exit codes.
