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
| [apt_repos_fields.**6**](vars/main.yml#L11)   | str | `repo_replaces` |    
| [apt_repos_fields.**7**](vars/main.yml#L12)   | str | `vendor_sources` |    
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
apt_repository tasks below it, report changed on every single converge; the
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
| Check which vendors already manage their own apt source | ansible.builtin.stat | False | Some vendors' postinst replaces the source this role declares with its own
deb822 file, /etc/apt/sources.list.d/<name>.sources, and then disables ours:
1Password comments out our .list, Chrome deletes it. Either way, re-adding
ours on the next converge only restarts the fight, and CI's idempotence pass
reported "Add repositories" changed on every run because of it.

Our entry is only needed to bootstrap: once the vendor's .sources exists it
is authoritative and ours is redundant. So entries marked vendor_sources in
group_vars stop being declared here once that file exists, and our leftover
.list is removed after the packages install, below -- leaving exactly one
declaration of each origin. |
| Note which vendors own their apt source | ansible.builtin.set_fact | False |  |
| Remove repository lines an entry no longer declares | ansible.builtin.apt_repository | False | Before adding: apt_repository matches lines exactly, so a changed `repo`
would otherwise be appended next to the line it replaces. |
| Add repositories | ansible.builtin.apt_repository | True |  |
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
cleanup, shipped the dead .list in every image, and left it for the second
converge to delete, which made CI's idempotence pass report a change on
every run. If a future postinst ever stops writing .sources, this stays
false and our .list is kept: apt still has a working source. |
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
