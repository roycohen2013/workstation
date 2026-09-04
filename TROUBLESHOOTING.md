# Troubleshooting

Organised by the **error text you will actually see**, because that is what you
will search for months from now. Run `make doctor` first -- it checks most of
the environment assumptions below in a couple of seconds.

Nearly everything here was environment drift rather than broken config: Ubuntu
replaced a core tool, a vendor moved a keyring, an upstream release removed a
flag. Expect the same class of thing after a long gap, and expect the repo
itself to be fine.

---

## `Timed out waiting for become success or become password prompt`

`make apply` sits at the password prompt, then fails -- with the correct
password. Plain `sudo` works fine.

**Cause.** Ubuntu 26.04 points `/usr/bin/sudo` at `sudo-rs`, the Rust
reimplementation. It treats a caller-supplied `-p` prompt as untrusted text:
rather than displaying it, it echoes it inside a `[sudo: ...]` annotation and
prompts with its own generic `Password:`. Ansible waits for the exact
key-tagged prompt it asked for and never sees it, so it never submits the
password at all.

You can see it directly:

```
$ sudo -H -S -p '[sudo via ansible, key=probe] password:' -u root /bin/true
[sudo: [sudo via ansible, key=probe] password:] Password:      # sudo-rs
[sudo via ansible, key=probe] password:                        # classic sudo
```

**Fix.** Already handled: `make apply` passes
`-e ansible_become_exe=/usr/bin/sudo.ws` when Ubuntu's classic binary is
present. Invoking `ansible-playbook` by hand needs the same flag. If `sudo.ws`
does not exist on a future release, `apt install sudo` restores it -- or set
the alternative system-wide with
`update-alternatives --set sudo /usr/bin/sudo.ws`.

---

## `Destination directory /etc/ssh/sshd_config.d does not exist`

Fails in `roles/security` during `make apply` on a fresh desktop install.

**Cause.** Ubuntu Desktop ships only the SSH *client*. That creates
`/etc/ssh/ssh_config.d` -- note the missing `d` -- but not the
`sshd_config.d` the hardening drop-in writes into, nor the `sshd` binary its
`validate` step runs, nor the `ssh` unit the next task manages. The golden
image never hit this because Packer's autoinstall installs the server for its
own access.

**Fix.** Already handled: the role installs `openssh-server` when
`workstation_ssh_server_enabled` is true, and gates the config and unit tasks
on a server actually being present. `dpkg -l openssh-server` confirms which
case you are in.

---

## `E:Conflicting values set for option Signed-By` / `The list of sources could not be read`

Every apt operation fails, not just the offending repository.

**Cause.** One origin declared twice with different `signed-by` paths. It
happens when a vendor's documented install and this repo disagree on where the
keyring lives -- and since Packer and Terraform are requirements of this
project, HashiCorp's own instructions had usually already written
`/etc/apt/sources.list.d/hashicorp.list` before `make apply` ever ran.

**Fix.** Already handled for HashiCorp: `group_vars` uses the vendor's
documented `key_path`, so the two declarations are byte-identical and collapse
into one. `make doctor` reports any origin with more than one `signed-by`. To
clear one by hand:

```bash
grep -rn signed-by /etc/apt/sources.list.d/<name>.list   # find the duplicate
sudo sed -i '\|signed-by=/wrong/path.gpg|d' /etc/apt/sources.list.d/<name>.list
sudo apt-get update
```

When adding a repo, prefer the vendor's documented keyring path over this
repo's default whenever their install instructions write a sources file too.

---

## `Qemu failed to start` (after a long ISO download and a boot timeout)

**Cause.** Almost always `/dev/kvm` permissions. Packer reports the generic
message; the real error is `Permission denied` opening the device.

**Fix.** `sudo usermod -aG kvm $USER`, then **log out and back in** -- a new
group only applies to a new login session, not the current shell. `make doctor`
checks real read/write access rather than mere existence, which is the
distinction that matters.

---

## `Output directory ... already exists`

`make image` fails instantly on a retry after an interrupted build.

**Cause.** The QEMU builder refuses to reuse an output directory, and any build
that dies partway -- crash, Ctrl-C, a reboot during compression -- leaves one
behind.

**Fix.** Already handled: `make image` passes `-force`. Invoking `packer build`
directly needs the same flag, or remove `build/workstation-<version>/` by hand.

---

## `make image` spends an hour "compressing"

**Cause.** Not a hang. zstd level 19 is roughly **9.4x slower** than level 12
for about 2.9 percentage points of ratio -- measured, not estimated -- and the
level does not parallelise well regardless of core count.

**Fix.** Level 12 is the default. Override deliberately when you want a smaller
artifact and have the time:

```bash
make image ARGS='-var compression_level=19'
```

---

## `Not an ECMA-119 time string` / `libisofs: Cannot open local file ... interval reading`

Both come from `make iso`.

**Cause.** The first was xorriso's own boot-layout report being shell-quoted
text that got re-expanded without stripping the quotes, so xorriso received
`'2026083121063400'` with the quote marks as data. The second was that same
report embedding a *relative* path to the source ISO, which resolved against
the wrong directory once the final build ran from inside the extracted tree.

**Fix.** Both are fixed in `scripts/build-iso.sh` -- tokenising with `xargs`
into an array, and resolving the ISO to an absolute path once. Recorded here
because the errors are cryptic and will look new if you ever see them again on
an older checkout.

---

## Ansible fails before any task runs, complaining about a callback plugin

**Cause.** `community.general` 12.0.0 removed the `community.general.yaml`
callback plugin that `ansible.cfg` used.

**Fix.** `ansible.cfg` now uses ansible-core's own `default` callback with
`callback_result_format = yaml`, which no collection release can remove, and
`requirements.yml` caps the collection below 12.0.0.

**The cap only helps if the capped copy is the one that loads.** A system-wide
copy in `/usr/lib/python3/dist-packages/ansible_collections` can sit alongside
the repo's `ansible/.collections`, and only the first on the search path is
used -- this machine currently has 12.1.0 installed system-wide, shadowed by
11.4.9. `make doctor` reports the version that actually loads, which is the
only one that matters. `make deps` restores it.

---

## `_terraform-docs produced no output._` in `docs/terraform.md`

**Cause.** A flag changed upstream. `gen-config-docs.py` used
`--no-header`, which no longer exists; terraform-docs exits non-zero on the
unknown flag and the script turned an empty result into a placeholder. The
committed docs blamed a missing tool for a broken invocation for a long time.

**Fix.** The script now uses `--hide header --indent 3`, and **exits non-zero**
when terraform-docs is installed but returns nothing, so the same silent
degradation cannot recur. If you see the new error, run the command by hand to
see what changed:

```bash
terraform-docs markdown table --hide header --indent 3 terraform/artifacts
```

Then fix the flags, run `make docs-config`, and commit the regenerated output
in the same change -- `make lint-docs` fails until the committed docs match.

---

## `Docs are stale -- run 'make docs-config' and commit the result`

**Cause.** You changed a role, a variable, or a comment, and the generated docs
no longer match. Working as designed.

**Fix.** `make docs-config`, then commit what changed. It needs `docsible` and
`terraform-docs`; `make doctor` reports both. Note that the **terraform-docs
version is pinned** in `group_vars` and CI reads that same pin -- different
versions format tables differently, which surfaces as permanently stale docs.

---

## `push declined due to email privacy restrictions`

**Cause.** GitHub is set to block pushes that expose your email, and the
commits carry a real address.

**Fix.** Either set the repo to your noreply address and re-author:

```bash
git config user.email "<id>+<user>@users.noreply.github.com"
git rebase <last-good-sha> --exec 'git commit --amend --no-edit --reset-author'
```

or turn the setting off at <https://github.com/settings/emails>.

---

## Something else

1. `make doctor` -- environment drift is the most likely cause.
2. `make apply-check` -- shows what would change without changing it.
3. `make verify-repos` -- confirms every declared third-party repo still
   resolves, which catches vendors moving keys or suites.
4. `ansible-playbook ... -vvv` -- when a failure is about *how* Ansible talks
   to the system rather than what it does, the raw exchange is usually the only
   thing that explains it. That is how the `sudo-rs` issue above was found.
