# Issue tracker: Local Markdown

Issues and specs for this repo live as markdown files in `.scratch/`.

Chosen over GitHub Issues deliberately: this is a single-maintainer personal
infrastructure repo, and `gh` is not installed on the workstation it is
developed on. Local files need no CLI, no auth and no network. The tradeoff is
that nothing here is visible from GitHub's web UI. Switch by re-running
`/mattpocock-skills:setup-matt-pocock-skills`, or by editing this file.

## Conventions

- One feature per directory: `.scratch/<feature-slug>/`
- The spec is `.scratch/<feature-slug>/spec.md`
- Implementation issues are one file per ticket at `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01`, never a single combined tickets file
- Triage state is recorded as a `Status:` line near the top of each issue file
- Comments and conversation history append to the bottom of the file under a `## Comments` heading

The `triage` skill is not installed here, so there is no label vocabulary file
and no `docs/agents/triage-labels.md`. Use plain, obvious `Status:` values
(`open`, `in-progress`, `done`, `wontfix`). If `triage` is installed later,
re-run the setup skill and it will write the canonical label mapping.

## When a skill says "publish to the issue tracker"

Create a new file under `.scratch/<feature-slug>/` (creating the directory if needed).

## When a skill says "fetch the relevant ticket"

Read the file at the referenced path. The user will normally pass the path or the issue number directly.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a file with one **child** file per ticket.

- **Map**: `.scratch/<effort>/map.md` (the Notes / Decisions-so-far / Fog body).
- **Child ticket**: `.scratch/<effort>/issues/NN-<slug>.md`, numbered from `01`, with the question in the body. A `Type:` line records the ticket type (`research`/`prototype`/`grilling`/`task`); a `Status:` line records `claimed`/`resolved`.
- **Blocking**: a `Blocked by: NN, NN` line near the top. A ticket is unblocked when every file it lists is `resolved`.
- **Frontier**: scan `.scratch/<effort>/issues/` for files that are open, unblocked, and unclaimed; first by number wins.
- **Claim**: set `Status: claimed` and save before any work.
- **Resolve**: append the answer under an `## Answer` heading, set `Status: resolved`, then append a context pointer (gist + link) to the map's Decisions-so-far in `map.md`.

## Note for this repo specifically

`.scratch/` is working material, not build input. Nothing in the Ansible,
Packer or Terraform paths reads it, and `make lint` does not check it.
