<!-- Moved out of README.md so the entry point stays short. Hand-written;
     not generated, unlike configuration.md / roles.md / packer.md /
     terraform.md, which `make docs-config` produces. -->

# Secrets

**Nothing personal is ever baked into an image.** No SSH private keys, no
tokens, no shell history, no machine-id. Images get uploaded to buckets and
written onto disks; treat every one as public.

Dotfiles are handled with [chezmoi](https://chezmoi.io): the image ships only
the binary, and your repo is pulled on first login. Set `dotfiles_repo` in
`group_vars/all.yml`.

The build account (`packer`/`packer`, hash committed in
`packer/http/user-data`) exists only inside the build VM and is deleted by
`roles/seal` before export. `tests/goss/workstation.yaml` asserts the machine
identity is blank in the finished artifact.
