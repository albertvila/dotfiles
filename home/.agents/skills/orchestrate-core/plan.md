# The plan phase

The planning contract shared by `/orchestrate-bb-plan` and
`/orchestrate-herdr-plan`. This file owns what a plan must decide and what an
approval must carry; each runtime's skill owns its input shapes, preflight,
artifact format, tracker record, and spawn/execute mechanics.

## Reading a GitHub issue

Preflight has passed, so these are reads. Nothing is written to a ticket at
plan time.

**Ticket set.** Every sub-issue of the parent, one level deep, read the way
`.scratch/<feature>/issues/` is read. Sub-issues come first; when the sub-issues
API returns nothing — an empty array, not an error, which is what a repository
without issue relationships returns — the **parented tickets** take their place:
the repo's own issues whose body names this issue in a `## Parent` section, which
is how `/to-tickets` publishes its tickets (one issue per ticket; the parent is a
body reference, not necessarily a native sub-issue edge). The parent body's task
list is the next fallback, and only when none of those produced a ticket does the
parent body become the single ticket — a spec body is a spec, not the work, so a
parent that has published tickets is never itself an item; its PR carries
`Part of #<parent>` instead (*PR body* in `threads.md`). Which source produced
the set is stated in the approval message.

**Graph.** Read once, at plan time, from the native `blockedBy` edges when there
are any; otherwise from each ticket's own `## Blocked by` section — for
sub-issues and parented tickets alike — and only from the parent body's when the
ticket bodies carry none. A disagreement between the sources is reported. The
graph is never re-polled during the run: GitHub calls an issue unblocked only
when its blocker is *closed*, which lags a run whose blockers are already `done`
in the ledger. Ticket order is never a graph.

**Naming.** The feature name is the parent issue title, slugified — it drives the
plan artifact, the run's identity and the retro's label. An item's id is
`#<issue-number>`, so labels, ledger keys and frozen diff filenames need no
translation layer.

**Exclusions.** Closed tickets are read, excluded from the item list, and counted
as satisfied blockers. A ticket in another repository is excluded outright — a
plan never claims scope the executor cannot read code for. Every excluded issue
is named by number in the approval message, under the `tickets in → items out`
line.

## Plan the run

1. Read the spec and every ticket: the `NN-*.md` files under the feature
   directory, or the ticket set resolved from a GitHub parent above.
2. Build the graph from each ticket's `**Blocked by:**` line — that line is the
   graph, not an inference. A GitHub input's graph was fixed by the read above.
3. Assign each item a file scope from what it will build. Disjoint scopes plus
   settled blockers form a parallel **wave**; overlapping scopes serialize.
4. **Reduce the item count first — that is the default move, not a flag to
   raise.** Every item costs a full worker plus a fresh-eyes review cycle, so
   one item per ticket is the wrong starting point. Items with identical file
   scopes merge into one item unless the work needs independent verifiability
   or independent rollback: a reset or history rewrite, an item ending in a
   push or merge rather than a PR, or an acceptance criterion no single
   reviewer can cover. Name that exception in the approval message instead of
   leaving it implicit. `mode: unattended` skips this reduction: one ticket,
   one item. Say that in the plan record.
5. **Capture each item's intent — from this session, not from the ticket.** One
   line of acceptance: what proves the item works, which is exactly what its
   reviewer checks. One line of out-of-scope: what the item is not claiming and
   its reviewer must not require. Both come from the discussion that produced
   this approval. The ticket was written before the work, so it cannot carry a
   decision made here, and a reviewer that re-derives the criteria from it is
   checking a document nobody updated. An item whose acceptance one review
   agent cannot hold is an item to split (step 4).
6. Flag the special handling so the executor and its reviewers start with the
   facts: run-alone resets, items ending in a push or merge, approval gates
   (commit plans, force-pushes), and any acceptance criterion reaching into
   another plugin or repo — list that path.

The plan is ready to render when every ticket has a disposition — its own item
or merged — and every item has a file scope, an acceptance line, an out-of-scope
line, a wave, and any exception named.

## One approval

Read `mode` from the argument before rendering: `--unattended`, `--land`, or
neither (`gated`). Both flags is a stop. `land` or `unattended` on a cross-repo
or `A+cross-repo` plan is a stop — name the shape. The contract is
[run-mode.md](run-mode.md).

Present in the approval message: the flow (A, B, or the cross-repo shape named
as itself), the mode, the reduction made — **tickets in, items out**, with every
excluded issue named by number beneath it and, for a GitHub input, which source
produced the ticket set — the waves, the per-item notes, and the model
assignments.

`gated` and `land` do not continue until the operator's yes; `unattended` does
not ask and writes the plan record with both gate timestamps equal to now and
`auto: true`, then continues. Nothing is dispatched before that record exists,
and the executor never re-asks what was approved here. The runtime skill names
the exact record and what a yes starts.

## The manifest

The executor's prompt is a **manifest**: data only, no instructions. The field
list, the item line and wave line formats, and what every header line means are
[manifest-contract.md](manifest-contract.md) — that file owns the shape, and the
shape is the same in both runtimes. What goes in it:

- the feature name and the run's identity
- the tracker, explicit and never inferred from the shape of a reference
- the flow — `A`, `B`, or `A+cross-repo` when the items mix an in-repo item with
  one whose files sit outside every repository. Never write a mixed run as plain
  `A`: the executor dispatches on this field, and the ledger and the retro trust
  it
- the `mode` line, never omitted
- the items, each naming its own ticket — `#<issue-number>` for GitHub, so the
  executor fetches exactly the ticket an item names rather than re-deriving it —
  with its acceptance and out-of-scope lines one line each, verbatim from the
  plan discussion: the executor quotes them in the worker prompt, the review
  brief and the PR body, and never substitutes the ticket's own wording
- the waves, and any run note the tickets cannot supply: cross-repo paths,
  run-alone handling, approval gates
- a model line only when the operator overrode the role defaults

The test for inclusion is procedural: **does this line tell the executor how to
do something its own skill already specifies?** If yes, it is wrong — cut it.
Role models, dispatch flags, review loops and ledger mechanics live in the
threads skill and are never restated here. Intent is not mechanics: an item's
acceptance and out-of-scope lines are data about what that item is, and they
stay.
