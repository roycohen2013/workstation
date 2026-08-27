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
| Assemble the declared package set | ansible.builtin.set_fact | False | --- Declared vs actual -------------------------------------------------------
The whole point of the manifest. Without this, a package that silently failed
to install ships in the image and nobody finds out until they go looking for
it on a running machine. |
| Identify declared packages missing from the image | ansible.builtin.set_fact | False | Compared against satisfied_names rather than real package names alone: a
declaration may legitimately name a virtual package, and comparing only
against installed package names would report it missing while it is plainly
there. See the Provides handling in capture-manifest.py. |
| Identify packages that were declared for removal but are still present | ansible.builtin.set_fact | False |  |
| Fail the build when a declared package is not installed | ansible.builtin.assert | False |  |
| Record the declared set alongside the manifest | ansible.builtin.copy | False | Written separately rather than merged into the manifest so the capture script
stays a pure inventory of the machine, with no notion of what was intended.
render-docs.py joins the two. |







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
