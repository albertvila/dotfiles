# The threads phase

The execution contract shared by `/orchestrate-bb-threads` and
`/orchestrate-herdr-threads`. This file owns the domain both runtimes share; each
runtime's skill owns its mechanics — how it dispatches, waits, collects,
releases and gets a worktree — plus its own ledger shape, field names and
commands.

## The executor's job

Execute an approved plan: dispatch one agent per item, keep the ledger, route
review findings, and land the run. The executor does not plan, and it never
implements an item itself — an item implemented in the executor's own context
has no worker, no ledger entry and no reviewer it can honestly claim.

**The manifest is the approved plan.** Start from it immediately: never
re-derive the graph and never re-ask what was already approved. With no manifest,
do not derive one: say the plan is missing and point the operator at the plan
skill.

**Dispatch before touching anything.** The manifest is data, not an
implementation assignment: a plan skill can hand off a bare manifest with no
instruction to run the threads skill, and the threads skill still applies. The
first turn writes the ledger and dispatches wave 1 **before any item's file is
opened to change it**. A single-item manifest whose notes list the exact files
to touch is context for the worker you are about to dispatch — it is not the
executor's own scope. A run whose record has one agent, no children and no ledger
is an executor that never dispatched, whatever it shipped.

## Flow shapes

The manifest's `flow:` names the run's shape, and a run is never written as a
shape it is not.

- **`A`** — one shared worktree, one PR. Workers run in the same worktree, leave
  their changes **uncommitted**, and never commit or push; the executor
  accumulates the combined diff and makes exactly one commit and one PR at the
  end.
- **`B`** — one worktree, branch and PR per item. Items with no `blockedBy`
  start together; an item with blockers stays `todo` until those PRs are merged,
  then its worktree is created from the updated target. Never review an item
  against a base that lacks its blockers, and never rebase it onto them
  afterwards.
- **`cross-repo`** — the items span more than one repository: no shared worktree
  and no single PR. Each item gets its own worktree and its own per-repo gate,
  and no single PR closes the run.
- **`A+cross-repo`** — in-repo items plus an item whose files sit outside every
  repository (no worktree, no branch, no PR is possible). The in-repo items keep
  the shared worktree and the single PR. The out-of-repo item is reviewed against
  a snapshot of its touched files, and any criterion only the live surface can
  prove becomes a named operator gate, spelled out with its exact steps. It is
  `done` at a clean review plus that gate; it has no PR, and the run's
  done-definition exempts it.

**A tracker repo differing from the code repo is not the cross-repo shape.**
When the tracker and spec live in one repo but every item's code lands in a
single code repo, the run is shape `A` in the **code repo**: one shared worktree,
one PR, one combined ponytail pass. Only the environment differs; the tracker's
issues are still claimed and commented.

**Waves.** A wave is the set of items whose blockers are settled, and it
dispatches and settles in parallel. In shape `A` every worker shares one
worktree, so an item's worker may only run concurrently with workers whose files
it does not touch — judge overlap from the item scopes plus what already changed
in the worktree. Disjoint files dispatch together; overlapping files serialize
the **workers**, never the review lane: dispatch worker N+1 the moment worker N
settles and its diff is frozen, and let review N run concurrently. If review N
returns findings, let the running worker finish, then run N's fix round and
re-review before dispatching anything new. Shape `B` has no file-overlap gating —
every unblocked item moves.

Workers never talk to each other; all coordination goes through the executor.

## Models

Three roles: **worker**, **code-review**, **ponytail**. Each runtime names the
role's default model and the flag that passes it; this file owns the policy.

A per-run override is the manifest's model line — "workers on X, reviewers on
Y". Ponytail follows the worker model unless the line also names one. The
operator sets the override at plan time and the manifest carries it; the executor
keeps the syntax and the dispatch-time decisions, not the choice.

**A model that does not work stops the run.** That covers every failure: the id
missing from the catalog, a refused dispatch, or a first turn dying on a provider
routing error (the dispatch succeeds, the turn dies). Stop, tell the operator
which model failed and how, and ask which to use instead. An item that cannot
proceed on the failed model is `blocked` with `cause.code: model_unavailable`; a
dispatch refused for any other reason leaves its item `failed` with
`cause.code: dispatch_failed`. A respawn passes the role's recorded model
explicitly — a fresh agent inherits nothing from the one that died.

## The ledger

[ledger.md](ledger.md) owns the ledger's shape; the runtime owns only its path
(BB's thread storage, Herdr's run directory). These invariants hold in both
runtimes:

- Write the ledger as the run moves, never batched at settlement — it must read
  true mid-run.
- An item the run stops on is **typed**: every `blocked` or `failed` item carries
  `cause: {code, detail}` from the closed set in
  [cause-contract.md](cause-contract.md). A cause on any other status, and a
  blocked or failed item with no cause, are write errors.
- Stamp the times honestly: every timestamp is read at the moment of the event,
  never typed and never rounded. An interval that runs backwards, or predates the
  agent's own session, is a write error, not a rounding artefact.
- An item is `done` only when its review is clean **and** its ponytail pass has
  settled. A diff that changes after a `done` write reopens the item explicitly.
- `finishedAt` is an **ISO-8601 UTC timestamp**, not a marker or a sentence, and
  the run corpus reads it as data. It is set only when the run is done: every
  item terminal, every `done` item's PR open or merged and handed over, and the
  blocked items surfaced. A turn that runs after `finishedAt` reopens the run —
  clear it, and set it again only when the run is terminal once more. One
  exception: the runtime's own handover acts after it — the retro spawn, the
  verification ask, and the post-merge cleanup the operator's reply resumes — are
  part of setting the run down, and do not reopen it.

## PR body

Every run's PR body opens with the run's **intent**, before any tracker-specific
closing lines: for each item the PR carries (shape `A`: every item; shape `B`:
its own), its title, its `acceptance` line and its `out-of-scope` line from the
manifest, verbatim, followed by that item's review verdict. The operator merges
on this block plus the verdicts, not on a diff — the diff is what the reviews
already read and priced, and an operator handed a diff skim has been given back
the cost the run existed to remove.

For a `tracker: github` run the body then carries the closing lines:

- `Closes #n` for every issue that maps to an item — each ticket that became an
  item, whether it arrived as a native sub-issue or as a parented ticket (an
  issue whose body names the parent in its `## Parent` section). The parent
  itself is `Closes`d only when the parent *is* the item.
- A parent that owns sub-issues or parented tickets gets a non-closing
  `Part of #<parent>` line instead — the PR points at the spec without closing a
  spec that is not the work.
- Shape `A`'s single PR lists `Closes` for every item issue; shape `B`'s
  per-item PR closes only its own item's issue.

Only `tracker: github` adds closing lines: a scratch run's PR body is the intent
block alone.

## Rules

- One item per agent, one agent per item.
- The executor never implements items itself — it dispatches, waits, routes
  findings, and unblocks.
- Worker changes are committed only at the approved commit gate; the run's own
  storage (thread storage or run directory) is never committed.
