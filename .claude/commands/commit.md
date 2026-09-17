---
description: Commit the current work using the repo's Conventional Commits convention, updating CHANGELOG.md
---

Commit the current changes using the `commit` skill.

Follow it end to end — survey the diff, update `CHANGELOG.md` only if the change is
user-facing, draft a Conventional Commits message, show the message and the exact file
list for confirmation, stage those specific paths, commit, validate with
`make lint-commits`, then push.

$ARGUMENTS
