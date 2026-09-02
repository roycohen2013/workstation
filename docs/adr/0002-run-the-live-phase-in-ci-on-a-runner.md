# Run the live phase in CI on a runner, not in a container

Every other CI job here is static analysis, and static analysis passes on a task
that writes into a directory the OS never created — which is exactly how
"Destination directory /etc/ssh/sshd_config.d does not exist" reached a laptop
instead of a runner. `apply.yml` therefore converges a real machine: it runs the
playbook on a GitHub runner, then runs it a second time and reports what still
changed, because a playbook that succeeds once but never settles is broken in a
way a single run cannot reveal.

## Considered Options

**A container** (`docker run` on any runner) — rejected. The playbook enables
systemd units, configures zram, rebuilds the initramfs and writes GRUB config;
without a real init those fail for reasons that say nothing about whether the
configuration is correct. A job that fails for irrelevant reasons is one people
learn to ignore, which is worse than no job.

**`--check` mode instead of a real converge** — rejected. Check mode is a
prediction, and the bug class this exists to catch is precisely where the
prediction and reality differ.

**Nothing, and rely on `make apply` locally** — rejected. That is what was
happening, and the failure landed on hardware mid-session.

## Consequences

The job takes tens of minutes and installs a full desktop, so it runs on
`ansible/**` pushes and weekly rather than on every commit. Changes on the second
pass are reported as a warning rather than failing the job: a few tasks re-run
legitimately — the manifest role rewrites its inventory by design — and a job
that goes red for an expected reason gets muted, taking the real signal with it.
It does not cover the become-prompt path (see ADR-0001), because runners have
passwordless sudo.
