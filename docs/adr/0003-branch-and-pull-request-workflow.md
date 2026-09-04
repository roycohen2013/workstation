# Every change reaches main through a pull request

`main` is protected and requires two checks — `lint` and `apply` — before a
branch can merge. Work happens on `change/<slug>` or `fix/<slug>` branches, in
git worktrees when several are in flight, and lands squashed.

The repository ran the opposite way until now: a single branch, named after the
chat session that created it, with everything pushed straight to it. That was
fast, and in one working day it put two defects on the trunk that no local check
could have found — a Terraform module that could not `init` because it declared a
variable Terraform reserves, and a task pointing at a key path that had moved,
which was invisible locally because a `creates:` guard file already existed on
the development machine. Both were caught by CI *after* they were on the trunk.
Protection turns that into caught *before*.

## Considered Options

**Pull requests by convention, without protection** — rejected. Nothing would
have stopped either of those pushes, and the value here is the enforcement, not
the ceremony.

**Requiring only `lint`** — rejected, and this is the decision most worth
recording. `lint` takes about a minute and `apply` takes twelve to fifteen, so
requiring only the fast one is tempting. But `lint` was green for both defects
above. `apply` — which converges a real machine and then converges it again to
check it settles — is what caught them. Requiring the cheap check and treating
the effective one as advisory would invert what the evidence says.

## Consequences

Every change now costs a branch, a pull request and a wait of twelve to fifteen
minutes. That is a real slowdown against pushing to trunk, accepted deliberately.

Because that wait is long, the agent enables auto-merge rather than blocking on
it: a pull request lands itself when both checks pass. This means image changes
can reach `main` without a human reading the diff. That is a considered trade —
across the session that produced this decision, CI caught real defects and human
diff review caught none — but it is a trade, not a free win.

`apply` must report on every pull request, including ones touching no Ansible,
because a required check that never reports blocks its pull request forever. The
job therefore always runs and short-circuits internally instead of being skipped
by a job-level `if:`.

Protection does not apply to the repository owner, leaving an escape hatch for
emergencies. The workflow is documented so that agents follow it by instruction
rather than relying on the rule to stop them.
