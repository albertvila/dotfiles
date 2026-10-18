# Orchestrate

A family of skills that execute an approved plan as a supervised run: one
coordinator dispatches an agent per item, routes reviews, and records what
happened, in one of two runtimes (BB threads or Herdr tabs).

## The run

**Run**:
One execution of an approved manifest — the coordinator, the lanes it
dispatches, and the ledger that records them.
_Avoid_: Job, session, orchestration

**Manifest**:
The approved plan as data: the items, their acceptance and out-of-scope lines,
the waves, the flow shape and the mode.
_Avoid_: Plan (that is the process; the manifest is its approved output), spec, config

**Coordinator**:
The lane that dispatches the run's work, keeps the ledger, routes findings and
lands the run; it never implements an item itself, and it is the run's identity —
where the ledger lives.
_Avoid_: Manager, orchestrator, executor

**Lane**:
One dispatched agent the ledger names — a worker, a review, a fix, a ponytail
pass, or the coordinator.
_Avoid_: Thread, agent, session

**Role**:
What a lane is for — worker, code-review, ponytail, fix, retro or coordinator —
and what its model policy and independence rules key off.
_Avoid_: Agent type, lane kind

**Wave**:
The set of items whose blockers are settled, dispatched and settled together.
_Avoid_: Batch, stage

**Flow shape**:
How the run's work is arranged: one shared worktree and PR (`A`), a worktree and
PR per item (`B`), items across repositories (`cross-repo`), or a mixed run
(`A+cross-repo`).
_Avoid_: Layout, topology

**Mode**:
How much the run asks the operator: `gated` (a yes to plan and to commit),
`land` (a yes to plan, PRs opened as drafts), or `unattended` (no yeses, one
ticket per item).
_Avoid_: Autonomy level, permission mode

**Gate**:
A point the run stops at for a human yes — the plan gate and the commit gate;
in Flow B each item has its own commit gate.
_Avoid_: Checkpoint, approval step, permission gate

## The ledger

**Ledger**:
The run's one written record, in one shape whichever runtime wrote it, written
as the run goes rather than at the end.
_Avoid_: State file, log, database

**Item**:
One unit of work the run dispatches, with a file scope, an acceptance line and
an out-of-scope line.
_Avoid_: Ticket (an item names a ticket), task, unit

**Item lifecycle**:
The states an item moves through — `todo`, `running`, `done`, `failed`,
`blocked` — and the transitions between them.
_Avoid_: Status machine, workflow

**Cause**:
The typed reason an item the run itself stopped on is `blocked` or `failed`,
drawn from a closed set.
_Avoid_: Error, failure reason, block reason

**Acceptance line**:
The one line naming what proves an item works, quoted verbatim from the plan
into the worker prompt, the review brief and the PR body.
_Avoid_: Definition of done, criteria

**Out-of-scope line**:
The one line naming what an item is not claiming and its reviewer must not
require.
_Avoid_: Non-goals, exclusions

## Review

**Review**:
An independent pass over an item's frozen diff by a lane that did not write it,
ending in a verdict.
_Avoid_: Check, audit, code review

**Verdict**:
What a review or ponytail pass ends with — `CLEAN`, or `FINDINGS` when it found
a defect.
_Avoid_: Result, outcome, score

**Finding**:
A defect in behaviour, in a named acceptance criterion, or in a gate the run
must pass, evidenced by a location and a quotation from the code.
_Avoid_: Issue, bug report, comment

**Nit**:
Everything a review reports that is not a finding — a preference, a style choice
the gate accepts, an observation with no gate behind it.
_Avoid_: Minor finding, suggestion

**Findings round**:
A review pass that ends in findings; it opens a fix round and counts against the
item's cap.
_Avoid_: Iteration, attempt

**Refutation**:
A fix round's answer that names a finding and quotes the code disproving it,
instead of changing code.
_Avoid_: Rejection, dismissal

**Class fix**:
One diagnosis of a defect class, recorded once and shared by every item the
class reached.
_Avoid_: Batch fix, grouped fix

**Ponytail pass**:
The run's second independent gate, reading the change for what can be deleted or
simplified rather than for defects.
_Avoid_: Cleanup pass, lint

## Retro

**Retro**:
The pass that turns a finished run's record into numbers and into proposed edits
to the skill that ran it; it is the run's recorder, not one of its lanes.
_Avoid_: Retrospective report, postmortem

**Corpus**:
The versioned archive of finished runs' records and reports, one directory per
run.
_Avoid_: Archive, run store
