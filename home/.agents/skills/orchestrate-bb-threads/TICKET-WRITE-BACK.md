# Ticket write-back (.scratch)

Reached from [SKILL.md](SKILL.md) when the work list comes from
`.scratch/<feature>/issues/NN-*.md` files. The manager keeps those ticket
files in sync with the ledger as items settle:

- Item settles `done` (worker DONE + clean review) → set the ticket's
  `**Status:**` line to `done` and append a line under `## Comments`:
  `Done by thread <id> — <one-line summary>`. At the end of the run, once the
  PR exists, append its URL to each done ticket's comments.
- Item settles `blocked` → leave the status line alone; append a
  `## Comments` line with the blocker so the next triage pass sees it.
- When every item has settled, flip the spec file's own `**Status:**` line
  (`.scratch/<feature>/spec.md`) to `done` too — the per-ticket write-back
  is easy to remember, the spec header is easy to strand.

Write to a ticket only once its item has settled, and mark `done` only after
the review loop is clean — a worker's DONE claim alone does not settle an
item.
