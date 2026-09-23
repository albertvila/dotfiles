# Ticket write-back (GitHub)

Reached from [SKILL.md](SKILL.md) when the manifest's tracker is
`github <owner/repo>#<parent>`. Write-back is **comments only**: the manager
never closes an issue, and never adds, removes or repurposes a label. Closing
is the PR's job — the PR body carries the closing lines (see *PR body closing
lines* in [SKILL.md](SKILL.md)).

An item's issue number comes from its ticket reference in the manifest, never
from re-deriving it. The run's **excluded** issues — closed sub-issues,
sub-issues in another repository, anything else the approval message named —
are **never written to**: the run never touched them, so they accrue no run
metadata.

- Item settles `done` (worker DONE + clean review) → post **exactly one**
  comment on its sub-issue naming the thread id, the outcome, and the PR URL
  once it exists. Until the PR exists (Flow A opens it at the end) leave the
  URL out and edit that same comment to add it — one comment, never a second.
- Item settles `blocked` → comment the blocker on that item's own issue, so
  the next triage pass sees it without reading the thread.
- At the commit-and-PR gate, once every item has settled, post the run-summary
  comment on the **parent** — and nothing else on the parent. No label, no
  close, no edit to the plan comment.
- The parent is never given a per-item comment. When the parent *is* the item
  (it owns no sub-issues), its outcome rides the run summary; the PR body
  closes it with `Closes #n`.

Write to an issue only once its item has settled, and write `done` only after
the review loop is clean — a worker's DONE claim alone does not settle an
item.
