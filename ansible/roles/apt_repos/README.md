<!-- DOCSIBLE START -->

# 📃 Role overview

## apt_repos



Description: Third-party APT repositories, their signing keys, and the packages installed from them.










### Defaults

**These are static variables with lower priority**

#### File: defaults/main.yml

| Var          | Type         | Value       |
|--------------|--------------|-------------|
| [apt_repos_enabled](defaults/main.yml#L2)   | list | `[]` |    


### Vars

**These are variables with higher priority**
#### File: vars/main.yml

| Var          | Type         | Value       |
|--------------|--------------|-------------|
| [apt_repos_fields](vars/main.yml#L4)   | list | `[]` |    
| [apt_repos_fields.**0**](vars/main.yml#L5)   | str | `name` |    
| [apt_repos_fields.**1**](vars/main.yml#L6)   | str | `enabled` |    
| [apt_repos_fields.**2**](vars/main.yml#L7)   | str | `key_url` |    
| [apt_repos_fields.**3**](vars/main.yml#L8)   | str | `key_path` |    
| [apt_repos_fields.**4**](vars/main.yml#L9)   | str | `key_armoured` |    
| [apt_repos_fields.**5**](vars/main.yml#L10)   | str | `repo` |    
| [apt_repos_fields.**6**](vars/main.yml#L11)   | str | `vendor_sources` |    
| [apt_repos_fields.**7**](vars/main.yml#L12)   | str | `vendor_opt_out` |    
| [apt_repos_fields.**8**](vars/main.yml#L13)   | str | `debsig_key_id` |    
| [apt_repos_fields.**9**](vars/main.yml#L14)   | str | `debsig_policy_url` |    
| [apt_repos_fields.**10**](vars/main.yml#L15)   | str | `packages` |    


### Tasks


#### File: tasks/main.yml

| Name | Module | Has Conditions | Comments |
| ---- | ------ | -------------- | -------- |
| Check each repository entry is complete | ansible.builtin.assert | False | Checked up front, for every entry including disabled ones, so a malformed
entry fails here with its name -- not as a NO_PUBKEY or a signature error
halfway through a run, or not at all until someone switches it on.

The signed-by check is the one that matters most. The keyring path is
derived from the entry (key_path, else /etc/apt/keyrings/<name>.gpg), and a
repo line pointing anywhere else produces a signature error that reads like
a network fault. |
| Ensure keyring directories exist | ansible.builtin.file | False |  |
| Select enabled repositories | ansible.builtin.set_fact | True | `enabled` is usually a template referencing a feature switch, which renders
to a string. selectattr() would truth-test that string, and a non-empty
"False" is truthy -- silently enabling a repository that is switched off.
An explicit `| bool` is the only reliable test here. |
| Note which enabled repositories carry a debsig policy | ansible.builtin.set_fact | False |  |
| Ensure the key cache exists | ansible.builtin.file | False | Keys are dearmoured into /etc/apt/keyrings and referenced per-repo with
signed-by, rather than added to the deprecated global trusted keyring where
any one vendor key would be trusted to sign any package.
Kept, not deleted afterwards, and out of /tmp. get_url compares an existing
file against what it fetches and reports ok when they match -- but only if
the file is still there. Deleting it made this task, and the dearmour and
source tasks below it, report changed on every single converge; the
CI idempotence pass is what surfaced that. /var/cache rather than /tmp so it
also survives a reboot. This is public key material, a few KB per vendor. |
| Fetch repository signing keys | ansible.builtin.get_url | False | Retried rather than left to fail: get_url contacts every one of these URLs
on every converge to compare against the cached copy, so a single vendor
host blinking -- one DNS EAI_AGAIN out of eight -- failed the whole run.
Deliberately NOT falling back to the cached key when a host stays
unreachable: that would silently keep using a key the vendor may have
rotated or revoked, which is the one failure here worth being loud about. |
| Dearmour repository signing keys into the cache | ansible.builtin.command | True | Key handling is two independent choices, because vendors differ on both:
key_path     where the keyring lands (default: /etc/apt/keyrings/<name>.gpg)
key_armoured whether to copy the .asc verbatim or dearmour it first

It matters because several vendors' packages register their own
sources.list.d entry naming a keyring path of their choosing -- if that file
does not exist, every later apt update fails with NO_PUBKEY. Matching the
vendor's documented layout keeps apt working whichever entry wins.
docker:           defaults (dearmoured, our path)
claude-desktop:   armoured, vendor path
1password:        dearmoured, vendor path
hashicorp:        dearmoured, vendor path -- see the note in group_vars

Dearmoured into the cache on every converge, then copied into place, so the
installed keyring follows the fetched key. This used to dearmour straight to
the keyring with `creates:`, which skipped it whenever the keyring existed:
when HashiCorp rotated its signing key, get_url refreshed the cached .asc but
the keyring stayed on the old key, and every apt update on machines
converged before the rotation failed with NO_PUBKEY. Dearmouring is
deterministic, so the copy reports a change only when the key really did. |
| Install repository signing keys (dearmoured) | ansible.builtin.copy | True |  |
| Install repository signing keys (armoured, verbatim) | ansible.builtin.copy | True |  |
| Set keyring permissions | ansible.builtin.file | False |  |
| Check which vendors already manage their own apt source | ansible.builtin.stat | False | Some vendors' postinst writes its own deb822 source,
/etc/apt/sources.list.d/<name>.sources, on every install and upgrade:
1Password and Chrome both do. Declaring ours as well, on every converge,
would leave each origin declared twice for good.

Our entry is only needed to bootstrap: once the vendor's .sources exists it
is authoritative and ours is redundant. So entries marked vendor_sources in
group_vars stop being declared here once that file exists, and our leftover
bootstrap source is removed after the packages install, below -- leaving
exactly one declaration of each origin. |
| Note which vendors own their apt source | ansible.builtin.set_fact | False |  |
| Install the deb822 sources library | ansible.builtin.apt | False | deb822_repository parses and writes sources through python3-debian.
Installed before the old .list files go, so a failure here leaves the
machine with the sources it had rather than with none. |
| Note that sources cannot be previewed yet | ansible.builtin.debug | True | `make apply-check` installs nothing, and deb822_repository cannot even
preview a change without the library -- so on the one check run before it
is installed, the source tasks are skipped rather than failed. |
| Remove one-line sources an older version of this role wrote | ansible.builtin.file | False | Older versions of this role wrote each source with apt_repository, as a
one-line sources.list.d/<name>.list. That module is deprecated in favour of
deb822_repository, so sources are now deb822 files -- and the .list is
removed first, or apt would read every repository twice and warn about it
on each update. A <name>.list someone wrote by hand from the vendor's
install docs (HashiCorp's, for one) goes too: it declares the same origin. |
| Translate repository lines into deb822 fields | ansible.builtin.set_fact | False | The one-line `repo` in group_vars stays the single source of truth -- it is
what vendors document and what scripts/verify-repos.py checks -- and is split
into deb822 fields here. The assert above has already checked its shape. |
| Add repositories | ansible.builtin.deb822_repository | True | Named workstation-<name>, never plain <name>, for two reasons:
- <name>.sources is exactly where vendor_sources vendors write their own
file, and the stat above tells the two apart by that path. Sharing it
would hand the file back and forth between us and their postinst.
- deb822_repository derives a keyring path from the same name, and with
state=absent deletes /etc/apt/keyrings/<name>.gpg -- the very keyring
this role installs for the default key_path. |
| Refresh the package lists after a source changed | ansible.builtin.apt | True | Refreshed here rather than by a handler: the packages below install from
these repositories, and a handler would not run until the end of the play.
deb822_repository, unlike apt_repository, never refreshes the cache itself. |
| Create debsig directories | ansible.builtin.file | False | debsig-verify policies, for entries that declare debsig_key_id. Where apt
verifies the repository, debsig verifies the .deb's own signature -- so the
policy has to be in place before the package installs, not after.

If debsig_key_id is wrong, these files land in a directory dpkg never
consults and the policy is silently inert. apt install still succeeds, which
is why goss asserts the paths (from the declared set roles/manifest records)
and `make verify-repos` checks the id against the published key, rather than
trusting either. |
| Install debsig policies | ansible.builtin.get_url | False |  |
| Install debsig keyrings | ansible.builtin.command | False | The repository's own signing key, from the cache filled above. |
| Tell vendor packages not to add an apt source of their own | ansible.builtin.lineinfile | False | Some vendors' postinst adds a source of its own unless told not to.
Claude Desktop writes claude-desktop.list whenever that path is free, which
it is now that ours is deb822: the same origin declared twice, a warning on
every apt update, and the list removed again by the next converge. Its
documented opt-out is a setting in /etc/default/claude-desktop, read by the
postinst -- so it has to be in place before the package installs. |
| Install packages from third-party repositories | ansible.builtin.apt | True | latest, not present: base upgrades everything before these repositories
are added, so a package already installed from elsewhere -- a .deb fetched
by hand, or the GitHub runner's preinstalled docker-ce and Chrome -- would
count as present at its old version and only catch up on the next converge.
CI's idempotence pass reported exactly that as base's upgrade changing every
run. Where the package is new or already current this is the same as present.
package-latest guards against unpinned drift; base's dist-upgrade already
takes every package to latest on every converge, so this adds none. |
| Check again which vendors now manage their own apt source | ansible.builtin.stat | False | Checked again now, not reused from the check above. On a first converge --
every image build, and every CI runner -- that check ran before the vendor's
package was installed, so it was false: our .list was written to bootstrap,
then the postinst wrote .sources. Reusing that stale answer skipped the
cleanup, shipped the dead bootstrap source in every image, and left it for
the second converge to delete, which made CI's idempotence pass report a
change on every run. If a future postinst ever stops writing .sources, this
stays false and ours is kept: apt still has a working source. |
| Remove our bootstrap apt source where the vendor's has replaced it | ansible.builtin.file | False |  |







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
