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
- fastfetch, which also prints a system-info banner when you log in and is
  available as the `sysinfo` alias in any interactive shell. The banner comes
  from `/etc/profile.d`, so it fires on a TTY, over ssh and in `bash -l`, but
  not in every terminal tab; turn it off with `base_fastfetch_on_login`. Other
  aliases can be added as data in `base_bash_aliases`.
- The desktop wallpaper is stamped with the machine's hostname and IP address, in
  the top right in bold, and rendered at the screen's own resolution so GNOME's
  zoom-to-fill does not crop the text off the edge of the display.
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

- The image build now fails when a declared flatpak or snap is missing, not
  only an apt package, and its image tests check every declared package
  rather than a hand-picked sample.
- A malformed `apps_apt_repos` entry now stops `make apply` and the image build
  before anything is installed, naming the entry: an unknown or misspelt field,
  `key_armoured` without `key_path`, or a `signed-by` that is not the entry's
  own keyring. Previously these surfaced mid-run as a signature error.
- BalenaEtcher is updated to 2.1.7.
- Image compression level is now the `compression_level` build variable, defaulting
  to 12 instead of a hard-coded 19. Level 19 took roughly nine times longer for a
  2.9-percentage-point smaller image; override it with
  `make image ARGS='-var compression_level=19'` when size matters more than time.
- Visual Studio Code comes from Microsoft's apt repository rather than as a snap, so
  it updates with the rest of the system and integrates with the shell `code` command.
- Repeated `make apply` runs no longer re-download things that are already installed,
  and settle without reporting changes on a second pass.
- Scrolling is natural on both the touchpad and a mouse: scrolling up moves the
  content up, the way a touchscreen does. Both directions are declared in
  `desktop_dconf`, so the two devices agree. It stays changeable in GNOME
  Settings, and a machine where it was already set by hand keeps that value
  until `dconf reset /org/gnome/desktop/peripherals/touchpad/natural-scroll`.

### Removed

- conky, which never worked on this desktop.

### Fixed

- `make verify-repos` now checks Nimbalyst's pinned AppImage, which it had
  never covered, and `--checksums` verifies its sha512 rather than assuming
  every pin is sha256.
- BalenaEtcher runs the new release after its pinned version is bumped. Before,
  `make apply` left the previous release's binary behind its `--no-sandbox`
  wrapper and overwrote the new one, so the upgrade never took effect.
- `make apply` no longer times out on Ubuntu 26.04, whose `sudo-rs` does not present
  the password prompt Ansible's become plugin expects.
- `make apply` no longer fails on a machine with no SSH server installed, or with
  one installed but not running -- which includes every freshly flashed machine,
  since the image ships the server disabled. It also no longer fails on a fresh
  install where the mise configuration directory did not yet exist.
- GNOME desktop defaults actually apply: the dconf database is compiled after it is
  written.
- apt no longer refuses to read its sources because of a duplicate HashiCorp
  repository entry.
- `make apply` now installs a vendor's rotated apt signing key. When HashiCorp
  replaced its key on 9 September 2026, machines converged before then failed
  every `apt update` with `NO_PUBKEY FC9CA96ACA026560`, and re-running
  `make apply` did not repair them.
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
- `make image` now reports failure when the build fails. A packer error was
  swallowed, so a run that produced no image at all could still be recorded as a
  success, and CI only went red because a later step tripped over the missing
  output directory.
- `make` targets no longer report success when a command fails partway through a
  recipe. `lint-packer` was ignoring `packer fmt -check` violations entirely,
  because a passing `packer validate` ran after it and only the last command's
  result was read.
- `make apply` no longer fails when a single package host blinks. apt was
  configured with no retries at all, so one refused connection or DNS blip
  anywhere in `sources.list.d` failed the whole converge; it now retries a
  failed download, configurable with `base_apt_retries`. Fetching the vendor
  signing keys retries too, since that step contacts every vendor on every
  run.
- `make publish` no longer deletes the image a channel still points at.
  Retention protected only the version being published, so a channel parked on
  an older build could be pruned out from under it and `make fetch` on that
  channel would stop resolving. Every channel's current image is now kept
  however old it is, and a publish that cannot read the channel pointers prunes
  nothing rather than guess.
- Editors and bundlers keep their raised file-watcher limit after a localsearch
  update. localsearch re-applied its own setting on every upgrade, dropping
  `fs.inotify.max_user_watches` from 524288 to 65536 until the next reboot,
  which is when "System limit for number of file watchers reached" appeared.
- The image build produces its artifacts again. Its post-processor ran under
  dash, which has no `pipefail`, so it aborted on its own first line before
  converting, compressing, rendering docs or writing checksums -- leaving an
  uncompressed qcow2 and no release artifacts at all.
- `apt update` no longer warns that every Claude Desktop target "is configured
  multiple times". On a machine where `claude-desktop.list` already held the
  vendor's line, `make apply` appended its own slightly different one; it now
  declares the vendor's exact line and removes the one it used to add.
- Images no longer ship packages that nothing depends on. The final
  clean-up step asked apt to autoclean and autoremove in one task, and the
  Ansible module only ever does the first, so the autoremove never ran.
