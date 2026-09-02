# Workstation

One declarative configuration, rendered into a bootable Ubuntu system that runs
either as a virtual machine or on laptop hardware. This glossary fixes the words
this project uses for its own concepts, so a cold return months later does not
have to re-derive them from the code.

## Language

**Image**:
The bootable artifact a build produces — a qcow2 and a raw disk, each compressed.
Never used bare for the phase (write "the image phase") or for the installer ISO.
_Avoid_: golden image, bootable image, disk image

**The image phase**:
The mode the playbook runs in when it is provisioning a build VM rather than a
running machine (`workstation_phase=image`). A mode, not a thing you can flash.
_Avoid_: image (bare), build phase

**Installer ISO**:
A remastered Ubuntu installer that installs unattended onto hardware whose disk
layout is not known in advance. A separate output from the image, not a form of it.
_Avoid_: image, ISO image

**Artifact**:
One published output of a build: either compressed disk file, the manifest, the
declared set, `docs.html`, or `SHA256SUMS`. A single file, never the directory
holding them.
_Avoid_: using it for the output directory (the Makefile's `ARTIFACT_DIR` names
that, and is named for what it holds)

**Build output directory**:
The per-version directory a build's artifacts land in,
`build/<image name>-<version>/`.
_Avoid_: artifact, the artifact directory (as a concept — `ARTIFACT_DIR` is only
the variable's name)

**Build**:
Producing an image. Bare "build" always means this one, because it is the
expensive, CI-gated operation everything else is scheduled around.
_Avoid_: using it bare for the installer ISO

**ISO build**:
Producing the installer ISO. Always qualified, never bare "build".

**The live phase**:
The mode the playbook runs in when converging a running machine rather than
provisioning a build VM (`workstation_phase=live`).
_Avoid_: live (bare)

**Running machine**:
A machine already booted and in use, which `make apply` converges. The thing the
live phase acts on, as distinct from the mode itself.
_Avoid_: live machine

**Machine identity**:
The per-machine state that must never be shared between machines flashed from
one image — machine-id, SSH host keys, and anything a daemon generates the first
time it starts. `seal` strips it; `firstboot` regenerates it. The question to ask
of any new package is whether installing it creates some.

**Seal**:
To strip machine identity from a build VM before export, so the image is a clean
template rather than a copy of one machine. Runs only in the image phase.

**Firstboot**:
The regeneration of machine identity the first time a flashed machine boots. The
counterpart to seal; armed during the image phase, runs once on the target.

**Drift**:
Declared no longer matching installed. Caught by the manifest check, which fails
the build; fixed by converging or rebuilding.
_Avoid_: using it bare for environment drift, which needs the opposite remedy

**Environment drift**:
The host or its upstreams changing underneath the repo — a distribution
replacing a core tool, a vendor moving a keyring, a release dropping a flag.
Caught by `make doctor`; fixed by changing the repo, not the machine.

**Channel**:
A named, movable pointer to one published version, followed by `make fetch`.
`stable` is the default and currently the only one.
_Avoid_: channel pointer (the pointer is the channel)

**Converge**:
To bring a running machine to the state `group_vars` declares. Idempotent by
definition: converging an already-converged machine changes nothing, which is
what the CI job verifies by doing it twice.
_Avoid_: apply (as a concept — `make apply` is the command that converges)

**Declared**:
What `ansible/group_vars/all.yml` says should be on a machine.
_Avoid_: intended, wanted, specified

**Installed**:
What `dpkg` reports is actually on a machine.
_Avoid_: actual, present

**Missing**:
Declared but not installed. Fails the build — this is the condition the drift
check exists to catch.
_Avoid_: absent, not found

**Undeclared**:
Installed but not declared. Reported, never failed: the set is mostly
dependencies and recommends, and failing on it would make builds unusable.
_Avoid_: extra, unexpected
