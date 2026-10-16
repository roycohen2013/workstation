<!-- DOCSIBLE START -->

# 📃 Role overview

## manifest



Description: Records what was actually installed and fails the build on drift from group_vars.













### Vars

**These are variables with higher priority**
#### File: vars/main.yml

| Var          | Type         | Value       |
|--------------|--------------|-------------|
| [manifest_check_path](vars/main.yml#L5)   | str | `/tmp/workstation-manifest.check.json` |    


### Tasks


#### File: tasks/main.yml

| Name | Module | Has Conditions | Comments |
| ---- | ------ | -------------- | -------- |
| Capture the installed inventory | ansible.builtin.script | False | The capture only reads the machine, so it also runs under `make apply-check`
-- into a scratch file, leaving the real manifest alone. Skipped there, as
script tasks are by default, this role went on to judge whatever manifest
the last converge left behind, or failed outright on a machine without one. |
| Report what was captured | ansible.builtin.debug | False |  |
| Read the manifest back | ansible.builtin.slurp | False |  |
| Remove the check-mode inventory | ansible.builtin.file | True |  |
| Parse the manifest | ansible.builtin.set_fact | False |  |
| Collect the packages pinned downloads install | ansible.builtin.set_fact | False | A pinned download of kind deb is an apt package once installed, so it is
declared like one -- under its package name, which may differ from its name. |
| Collect the keyrings and debsig policies the enabled repositories install | ansible.builtin.set_fact | False | The keyring path defaults per entry (key_path, else /etc/apt/keyrings/<name>.gpg),
which map() cannot express, so it is resolved here the way roles/apt_repos
resolves it. |
| Assemble the declared set | ansible.builtin.set_fact | False | Each entry mirrors the gate its producing role applies -- desktop packages and
dconf keys only with the desktop, flatpaks only where roles/apps installs them
-- so the record states what this machine should have, already resolved.
tests/goss turns it into checks without re-deriving any of it: the templates
there only switch on `features` and loop over lists. |
| Identify declared packages missing from the image | ansible.builtin.set_fact | False | Compared against satisfied_names rather than real package names alone, so a
declared name that only another package Provides is not misreported as
missing -- it is reported below as what it is instead. See the Provides
handling in capture-manifest.py. |
| Identify declared packages that only another package provides | ansible.builtin.set_fact | False | A declared name must be a real package. One that only exists because another
package Provides it -- a transitional name a release dropped, as p7zip-full
and dnsutils were in 26.04 -- still installs, since apt resolves it, but
nothing that asks dpkg about the name itself can see it: the image tests in
tests/goss fail on it, after a converge that reported success. Failing here
names the package to declare instead. |
| Identify packages that were declared for removal but are still present | ansible.builtin.set_fact | False |  |
| Report what this run would install or remove | ansible.builtin.debug | True | In check mode the inventory is the machine before this run, so what is
missing is what `make apply` would install: reported, not failed on. |
| Fail the build when a declared package is not installed | ansible.builtin.assert | True |  |
| Record the declared set alongside the manifest | ansible.builtin.copy | False | Written separately rather than merged into the manifest so the capture script
stays a pure inventory of the machine, with no notion of what was intended.
render-docs.py joins the two, and run-goss.sh feeds this file to goss as its
vars, so the image tests assert the same set this role checked. |







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
