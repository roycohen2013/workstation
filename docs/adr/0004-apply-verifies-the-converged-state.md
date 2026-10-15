# The apply check verifies the converged state, and verification never warns

`apply.yml` converges a real machine twice (ADR-0002), which proves the playbook
runs and settles -- not that the machine ended up as `group_vars` declares. The
goss suite that asserts that ran only inside the Packer build, 30-60 minutes long
and not part of any pull request, so a regression check written for a live-phase
bug (localsearch #16, Chrome's apt source #17, 1Password #14) never ran where the
bug happened. And because the suite hand-copied today's flag values, flipping a
flag in `group_vars` linted green and failed the next image build.

So the suite is split in two. `tests/goss/shared.yaml` holds what is true after
any converge, and runs after `apply.yml`'s second converge, in `make verify`, and
-- included by `image.yaml` -- in the build. `tests/goss/image.yaml` adds only
what a sealed image alone can satisfy: firstboot armed, machine identity blank,
build residue gone. Most checks are generated from the declared set
`roles/manifest` records in `/etc/workstation-declared.json`, so they follow
`group_vars` without anyone editing goss.

Two rules hold this together.

**A failed check fails the job.** ADR-0002 reports second-run *changes* as a
warning, because a few tasks re-run legitimately and a job that goes red for an
expected reason gets muted. A failed assertion is never expected: it means the
machine does not match what is declared. Warning on it would let a broken
converge merge.

**Every check is shared or image-only, with no per-machine skipping.** A check
that cannot hold on a GitHub runner, or on a lived-in laptop, belongs in
`image.yaml`. A check guarded by "skip this here" turns a pass into "passed, or
was skipped", and nothing downstream can tell which. The only guards allowed are
the feature flags in the declared set (`features.goss.tmpl`): turning a feature
off removes its checks because the machine is not meant to have that behaviour,
not because the check is inconvenient there.

## Considered Options

**Warn on verification failures, like second-run changes** -- rejected, for the
reason above: the warning in ADR-0002 exists because some changes are expected,
and no failed assertion is.

**One suite with `when`-style conditions on the phase or machine** -- rejected.
It keeps one file, but every condition is a place a check can stop running
without anyone noticing, which is the failure this decision exists to prevent.

**Keep verification only in the image build** -- rejected. That is what was
happening, and it is why live-phase fixes had no regression check on the path
where they broke.

## Consequences

The required `apply` check grows by the few seconds goss takes, and fails on a
mismatch where it previously passed. A check that turns out not to hold on the
runner is moved to `image.yaml` deliberately, with a reason, rather than
weakened.

The suite reads the declared set the last converge recorded, never one generated
on the spot, so `make verify` checks a machine against what it was converged to.
After editing `group_vars`, run `make apply` before `make verify`.
