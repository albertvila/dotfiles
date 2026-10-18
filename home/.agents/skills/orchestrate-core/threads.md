# The threads phase

The execution contract shared by `/orchestrate-bb-threads` and
`/orchestrate-herdr-threads`. This file owns the domain both runtimes share; each
runtime's skill owns its mechanics — how it dispatches, waits, collects,
releases and gets a worktree — plus its own ledger shape, field names and
commands.

## The coordinator's job

Execute an approved plan: dispatch one agent per item, keep the ledger, route
review findings, and land the run. The coordinator does not plan, and it never
implements an item itself — an item implemented in the coordinator's own context
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
coordinator's own scope. A run whose record has one agent, no children and no ledger
is an coordinator that never dispatched, whatever it shipped.

## Flow shapes

The manifest's `flow:` names the run's shape, and a run is never written as a
shape it is not.

- **`A`** — one shared worktree, one PR. Workers run in the same worktree, leave
  their changes **uncommitted**, and never commit or push; the coordinator
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

Workers never talk to each other; all coordination goes through the coordinator.

## Models

Three roles: **worker**, **code-review**, **ponytail**. Each runtime names the
role's default model and the flag that passes it; this file owns the policy.

A per-run override is the manifest's model line — "workers on X, reviewers on
Y". Ponytail keeps its own role default; only a ponytail **fix** runs on the
worker model, because a fix is authoring, not review. The operator sets the
override at plan time and the manifest carries it; the coordinator
keeps the syntax and the dispatch-time decisions, not the choice.

**No gate reviews its author's family.** `code-review` and the ponytail pass are
the run's two independent gates: each must run on a model family different from
the one that wrote the diff, and different from each other. A second opinion from
the author's own family is the author's opinion twice. A runtime whose default for
one role is another role's default, or a role that inherits the runtime's own
default (equal to the worker), breaks this silently.

The one licensed exception is the Herdr adapter's risk rule
([`/orchestrate-herdr-threads`](../orchestrate-herdr-threads/SKILL.md#models)): a
**mechanical** item's `code-review` may run on the worker model, and the recorded
`risk` is what makes that deliberate rather than forgotten. It never covers a
ponytail pass or the fresh-eyes review of a fix delta — those read taste and
behaviour, which is exactly where a same-family reviewer converges on the author's
blind spots instead of finding them.

**A model that does not work stops the run.** That covers every failure: the id
missing from the catalog, a refused dispatch, or a first turn dying on a provider
routing error (the dispatch succeeds, the turn dies). Stop, tell the operator
which model failed and how, and ask which to use instead. An item that cannot
proceed on the failed model is `blocked` with `cause.code: model_unavailable`; a
dispatch refused for any other reason leaves its item `failed` with
`cause.code: dispatch_failed`. A respawn passes the role's recorded model
explicitly — a fresh agent inherits nothing from the one that died.

**The request and the receipt are two fields, and both are written.** `models` is
what the run asked for; `served` is what the lane's own record names, read as the
lane settles — Herdr: the pi session transcript the ledger already points at; BB:
`bb thread log <id> --json` and its `execution.model`. Write it when the record
names exactly one model, under the role for that role's first lane and on the lane
itself when a lane diverges from its role. A lane that ran several models, or
whose record names none, leaves `served` out and reads as **unverified** — absent
is the honest value there, and a retro that cannot see the field prices the
request as if it were the fact ([ledger.md](ledger.md)).

## Liveness

A dispatched lane has a heartbeat: the pi session transcript on Herdr, the
thread record on BB. The coordinator reads that lane's last-activity signal and
compares it with now.

`STALE_GAP_SEC` is **900** seconds. An open turn — the lane's status still
working — whose activity has not moved for longer than that is a **stale
candidate, never a verdict**: the coordinator reads the agent (Herdr `agent read`,
BB `thread log`/`output`) before acting. A single tool call writes nothing until
it returns, so a test suite longer than the gap is the expected false positive;
that is why the check confirms and does not kill.

A confirmed stall — a turn that ended with no report — is the runtime's
stalled-turn recovery: re-prompt that same agent once, then record `turn_stalled`
on the second stall ([cause-contract.md](cause-contract.md)). Liveness never
restarts an agent the coordinator did not start, and never reads a quiet transcript
as proof of death.

## Escalation

A worker that cannot proceed and cannot find the answer in the manifest
escalates: it stops its turn and reports `ESCALATE:` with **exactly one
question**, the options it sees, and the one it recommends. Never guess, never
wait. This is a decision handed up, not a failure.

The coordinator answers from the approved manifest when the manifest answers; the
answer is routed back into the **same worker** (BB: `bb thread queue create` then
`queue send`; Herdr: prompt the same agent), and the item stays `running`. Only
when the manifest does not answer it does the item become `blocked` with
`cause.code: worker_blocked`, whose `detail` is that one question.

- `gated` puts that single question to the operator, with the worker's options,
  and routes the reply back to the same worker; the item returns to `running`
  and its `cause` is cleared.
- `land` and `unattended` have no human in the loop: the question is surfaced
  and the frontier keeps moving, exactly as a `worker_blocked` item does today.

A worker's context is preserved across this exchange — the answer resumes the
same agent, it does not respawn one. An unanswered escalation is a block, and a
block is not a settle.

## The ledger

[ledger.md](ledger.md) owns the ledger's shape; the runtime owns only its path
(BB's thread storage, Herdr's run directory). These invariants hold in both
runtimes:

- Write the ledger as the run moves, never batched at settlement — it must read
  true mid-run.
- **The dispatch write comes before the spawn.** Dispatching is the run's one
  non-idempotent act: a manager that dies between spawning a lane and recording
  it leaves a resume with nothing to read, and the second spawn it then makes is
  the duplicate this record exists to prevent. So the item's `dispatchAttempt`
  (`{at, role, label}`, [ledger.md](ledger.md)) is written **first**, then the
  lane. On resume, an attempt whose role has no lane beside it is resolved by
  finding that lane in the runtime — BB: the child thread carrying that label;
  Herdr: `herdr agent list` — before any replacement is spawned. Never spawn on
  an attempt that already produced a lane.
- Stamp the times honestly: every timestamp is read at the moment of the event,
  never typed and never rounded. An interval that runs backwards, or predates the
  agent's own session, is a write error, not a rounding artefact.
- `finishedAt` is an **ISO-8601 UTC timestamp**, not a marker or a sentence, and
  the run corpus reads it as data. It is set only when the run is done: every
  item terminal, every `done` item's PR open or merged and handed over, and the
  blocked items surfaced. A turn that runs after `finishedAt` reopens the run —
  clear it, and set it again only when the run is terminal once more. One
  exception: the runtime's own handover acts after it — the retro spawn, the
  verification ask, and the post-merge cleanup the operator's reply resumes — are
  part of setting the run down, and do not reopen it.

### The item lifecycle

An item's `status` is the only thing that moves, and these are the transitions.
Anything else is a write error.

| from | to | written when | the write carries |
|---|---|---|---|
| — | `todo` | seeded from the manifest, before wave 1 dispatches | nothing: no `worker`, no `startedAt`, no `reviews`, no `fixes` |
| `todo` | `running` | its blockers have settled, and in shape `A` its files are disjoint from every running worker's | `worker.id`, `startedAt` |
| `running` | `done` | its review is CLEAN **and** its ponytail pass has settled | `endedAt` |
| `running` | `blocked` | a stop from the closed set | `cause: {code, detail}` — [cause-contract.md](cause-contract.md) |
| `running` | `failed` | the dispatch itself was refused | `cause.code: dispatch_failed` |
| `blocked` | `running` | the answer routed into the same worker, or the operator's adjudication | `cause` cleared |
| `done` | `running` | its frozen diff changes | an explicit reopen: `endedAt` cleared, and `finishedAt` cleared with it |

Two things that look like transitions and are not:

- **A `todo` item held by an unmet blocker stays `todo`.** A wait is not a block:
  no `cause`, no stop, and the item moves when its blocker settles.
- **A block is not a settle.** `blocked` is terminal for the run's
  done-definition and for `finishedAt`, and the item still returns to `running`
  when what stopped it is answered.
- **A `failed` item is terminal for the run.** `dispatch_failed` is a fact about
  the run, not a retry prompt: the item is surfaced under the run's
  done-definition, and the retry is the next run's, on an environment the operator
  has fixed ([cause-contract.md](cause-contract.md)).

The table is what the writer reads. `python3 scripts/validate-ledger.py <ledger>`
prints `OK: <n> item(s)` and exits 0, or `FAIL:` with one line per write error and
exits 1 — and the run does not move again until it reads clean: a runtime that
acts on a record contradicting itself charges the retro for a mistake the writer
already knows it made. It enforces the half a single snapshot can prove, since
the status a write replaced is gone by the time the next write is checked: a
status and the fields beside it disagreeing (a `todo` with a worker, a `running`
with an `endedAt`), a `done` with no clean review, a `FINDINGS` verdict with no
round behind it, a fourth findings round, a stamp typed instead of read, a
`finishedAt` standing over live work, a lane with no `id` to price it by, and who
acted — a worker or reviewer that is one of the run's own `executors`, or a
reviewer that is the item's own worker. Each runtime's skill carries the command
for its ledger path.

**No history is stored, and that is a decision, not an oversight.** The checker
sees one file, so an item batched straight past a status — a `done` never written
`running` — is indistinguishable from one written as the run moved: the status the
write replaced is gone. Two ways to close that were considered, and both are
refused. A `--previous` copy per write tolls every write in both runtimes to catch
a record that, once shipped, is identical to a correct one. An append-only journal
that derives the snapshot reverses [ledger.md](ledger.md)'s shape and rebuilds
every reader, down to the retro's own scripts, to reconcile a drift a single
writer does not produce — and the shape drift that does occur, an old run's extra
field or a second copy of the gates, is caught above without it. An item that
never passed through `running` leaves nothing a reader can act on: the retro
prices intervals from the stamps and the sessions, and those are written either
way. Keeping that discipline is the writer's — *write the ledger as the run
moves*, never batched — and the failure it prevents is invisible because it would
not have changed anything a reader reads.

## PR body

Read and follow the `pr` skill before opening each PR — shape `A`'s one PR and
each of shape `B`'s per-item PRs. The body is that template. Set it at create
(`gh pr create --body-file`); when the environment already opened the PR, `gh
pr edit --body-file` before the PR counts as open. A PR opened without the skill is
not done.

Summary opens with the run's **intent**, then the diagram the skill calls for.
Intent, for each item the PR carries (shape `A`: every item; shape `B`: its
own): its title, its `acceptance` line and its `out-of-scope` line from the
manifest, verbatim, followed by that item's review verdict. The operator merges
on this block plus the verdicts, not on a diff — the diff is what the reviews
already read and priced, and an operator handed a diff skim has been given back
the cost the run existed to remove.

Evidence is the skill's before/after: the validation command that exited 0, and
that verdict. Merge Danger is the skill's door and blast radius, from the diff.

For a `tracker: github` run the body then carries the closing lines, after the
skill's sections so GitHub still links them:

- `Closes #n` for every issue that maps to an item — each ticket that became an
  item, whether it arrived as a native sub-issue or as a parented ticket (an
  issue whose body names the parent in its `## Parent` section). The parent
  itself is `Closes`d only when the parent *is* the item.
- A parent that owns sub-issues or parented tickets gets a non-closing
  `Part of #<parent>` line instead — the PR points at the spec without closing a
  spec that is not the work. Nothing else closes it either, so the run does:
  [run-mode.md](run-mode.md)'s *After the operator merges*, step 5, closes the
  parent once nothing naming it is still open.
- Shape `A`'s single PR lists `Closes` for every item issue; shape `B`'s
  per-item PR closes only its own item's issue.

Only `tracker: github` adds closing lines: a scratch run's body is the skill's
sections with the intent block, and nothing after them.

## Rules

- One item per agent, one agent per item.
- The coordinator never implements items itself — it dispatches, waits, routes
  findings, and unblocks.
- Worker changes are committed only at the approved commit gate; the run's own
  storage (thread storage or run directory) is never committed.
