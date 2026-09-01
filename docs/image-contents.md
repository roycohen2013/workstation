<!-- Moved out of README.md so the entry point stays short. Hand-written;
     not generated, unlike configuration.md / roles.md / packer.md /
     terraform.md, which `make docs-config` produces. -->

# Knowing what is in an image

Every build records what actually got installed and renders it beside the image:

| Output | What it answers |
|---|---|
| `docs.html` | Every package, version, size and **which repository it came from**, with search and filters. Published alongside the image. |
| `workstation-manifest.json` | The same data as JSON, also kept at `/etc/workstation-manifest.json` *inside* the image, so a running machine can answer "what am I?" |

```bash
make docs                                  # open this build's report
make docs-diff FROM=2026.08.20-a1b2 TO=2026.08.27-c3d4   # what changed between builds
```

**The build fails if the image does not match what you declared.** `roles/manifest`
compares `group_vars/all.yml` against what `dpkg` actually reports and stops the build
when something declared is missing — a package that silently failed to install used to
ship unnoticed. The comparison is one-way on purpose: undeclared packages are reported,
never failed, since that set is mostly `Recommends`.

That report is also where image growth becomes attributable. Enabling Cowork pulls in
`qemu-system-x86`, `ovmf` and `virtiofsd` through `claude-desktop`'s recommends; none of
them are declared anywhere, and the "installed but never declared" section is where they
show up.

Reference documentation for the configuration itself lives in [`docs/`](.), generated
from source by `make docs-config` and checked for staleness by CI. Each Ansible role also
carries its own generated `README.md`.
