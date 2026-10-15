<!-- DOCSIBLE START -->

# 📃 Role overview

## manifest



Description: Records what was actually installed and fails the build on drift from group_vars.
















### Tasks


#### File: tasks/main.yml

| Name | Module | Has Conditions | Comments |
| ---- | ------ | -------------- | -------- |
| Capture the installed inventory | ansible.builtin.script | False |  |
| Report what was captured | ansible.builtin.debug | False |  |
| Read the manifest back | ansible.builtin.slurp | False |  |
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
| Identify declared packages missing from the image | ansible.builtin.set_fact | False | Compared against satisfied_names rather than real package names alone: a
declaration may legitimately name a virtual package, and comparing only
against installed package names would report it missing while it is plainly
there. See the Provides handling in capture-manifest.py. |
| Identify packages that were declared for removal but are still present | ansible.builtin.set_fact | False |  |
| Fail the build when a declared package is not installed | ansible.builtin.assert | False |  |
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
