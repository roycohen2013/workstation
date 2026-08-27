<!-- DOCSIBLE START -->

# 📃 Role overview

## dotfiles



Description: Installs chezmoi and applies dotfiles at first login, never baking them in.
















### Tasks


#### File: tasks/main.yml

| Name | Module | Has Conditions | Comments |
| ---- | ------ | -------------- | -------- |
| Install chezmoi | ansible.builtin.shell | True |  |
| Install first-login dotfiles hook | ansible.builtin.template | True |  |
| Remove first-login hook when dotfiles are disabled | ansible.builtin.file | True |  |
| Apply dotfiles now (live phase only) | ansible.builtin.command | True | On an already-running machine there is no reason to wait for a login. |







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
