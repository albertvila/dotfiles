---
name: orchestrate-bb-plan
description: "Plan a BB orchestration run and take one approval before anything is dispatched, then spawn and babysit the manager thread that executes it. Use when the user says '/orchestrate-bb-plan', or gives a BB Task key, a `.scratch/` feature directory, or a GitHub issue number, `owner/repo#n` or issue URL to run."
argument-hint: "<BB Task key|ULID> | @.scratch/<feature>/ | <#issue|owner/repo#issue|issue-url>"
---

# Orchestrate BB Plan

One loop, three skills, three threads: **plan → run → retro**. This skill is
the plan phase and the run's umbrella. It decides the run's shape, items,
waves and models; takes one approval; records the plan on the run's tracker;
spawns the manager thread; waits for the run to settle; and spawns the retro
thread.

The plan skill decides, the manager executes.

## Input

Three input shapes:

- **A BB Task key or ULID** (`DP-3`). Resolve its spec from the Task
  description — a sweep-created Task carries the spec path and a
  `scratch-sweep-key: <project>:<path>` line. The description may name either a
  `.scratch/<feature>/` directory or a GitHub issue; both resolve the same way.
  If it resolves to neither, report what you found and ask for the path or the
  issue; never guess.
- **A `.scratch/<feature>/` directory reference** (`@.scratch/<feature>/`).
  A bare feature directory with no Task stops here: tell the operator there is
  no Task for it and offer to create one. Create nothing without their yes.
- **A GitHub issue** — a parent whose sub-issues are the tickets, or a direct
  issue with none of its own. Accepted as `#42` / `42`, resolved against the
  plan thread's checkout repository, as `owner/repo#42`, or as a full issue
  URL. Issues and pull requests share one number space, so the resolution step
  must check which it resolved: a pull request number is refused, with the
  reason named, rather than planned as if it were a ticket.

## Where the plan thread runs

The plan thread must run in the project checkout — a fresh worktree cannot see
an untracked `.scratch/` tree — and in `auto` or `full` permission mode,
because a child cannot exceed its parent's permission ceiling and the manager
must be free to read the tickets. If either is wrong, say so and stop rather
than spawning a downgraded manager.

A GitHub input adds a third stop: `gh auth status` must pass, or the run fails
mid-plan instead of at the gate. The issue's repository must also match the
plan thread's checkout repository — a mismatch stops the run with the mismatch
named, because item file scopes are inferred against the checkout's code.

Do not run this skill inside a raw terminal `pi` session: `--parent-self` needs
`BB_THREAD_ID`, the artifact needs `$BB_THREAD_STORAGE`, and the manager needs
`$BB_ENVIRONMENT_ID` — none exist outside BB. From a terminal, spawn the plan
thread itself and walk away:

```sh
bb thread spawn --project <project-id> \
  --title "PLAN <feature>" \
  --permission-mode auto --json \
  --prompt "/orchestrate-bb-plan <input>"   # a Task key, @.scratch/<feature>/, or a GitHub issue
```

## Reading a GitHub issue

Preflight has passed, so these are reads. Nothing is written to a sub-issue at
plan time.

**Ticket set.** Every sub-issue of the parent, one level deep, read the way
`.scratch/<feature>/issues/` is read. Sub-issues come first; when the
sub-issues API returns nothing — an empty array, not an error, which is what a
repository without issue relationships returns — the parent body's task list is
the fallback ticket set; and only when the body carries no task list either
does the parent body become the single ticket. Which source produced the set is
stated in the approval message.

**Graph.** Read once, at plan time, from the native `blockedBy` edges when
there are any, otherwise from the parent body's `## Blocked by` section. A
disagreement between the two sources is reported. The graph is never re-polled
during the run: GitHub calls an issue unblocked only when its blocker is
*closed*, which lags a run whose blockers are already `done` in the ledger.
Sub-issue order is never a graph.

**Naming.** The feature name is the parent issue title, slugified — it drives
the artifact path and the `ORCHESTRATE`/`RETRO` thread titles. An item's id is
`#<issue-number>`, so thread titles, ledger keys and frozen diff filenames need
no translation layer.

**Exclusions.** Closed sub-issues are read, excluded from the item list, and
counted as satisfied blockers. Sub-issues in another repository are excluded
outright — a plan never claims scope the plan thread cannot read code for.
Every excluded issue is named by number in the approval message, under the
`tickets in → items out` line.

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
   leaving it implicit.
5. Flag the special handling so the manager and its reviewers start with the
   facts: run-alone resets, items ending in a push or merge, approval gates
   (commit plans, force-pushes), and any acceptance criterion reaching into
   another plugin or repo — list that path.
6. Assign models per item: worker, code-review and ponytail. The role defaults
   live in `/orchestrate-bb-threads` (*Models*); this skill records the
   assignments and any override the operator gave.

The plan is ready to render when every ticket has a disposition — its own item
or merged — and every item has a file scope, a wave, and any exception named.

## Render the plan

Write a self-contained HTML artifact to
`$BB_THREAD_STORAGE/reports/orchestration-plan.html`, then emit
`::inline-vis{source="thread-storage" file="reports/orchestration-plan.html" height="900"}`
as its own block in the approval message — never inside backticks or a code
fence there, or it stays literal text (see the inline-vis skill for the
directive rules).

Shape: items as a vertical chain in execution order, each with a status pill;
blocked-by arcs on the left margin where they cross nothing; a one-row strip at
the bottom showing the per-item worker → review → findings loop (cap 3); the
run's end boxes last (ponytail pass, then commit+PR or ticket write-back).
Parallel waves draw as side-by-side lanes; a serial run draws as a worker chain
with the review lane beside the next worker's box (review N runs while worker
N+1 builds), so the approved diagram cannot be read as one fully serial chain.
One screen, no scrolling.

## One approval

Present in the approval message: the flow (A, B, or the cross-repo shape named
as itself), the reduction made — **tickets in, items out**, with every excluded
issue named by number beneath it and, for a GitHub input, which source produced
the ticket set (sub-issues or the parent body's task list) — the waves, the
per-item notes, and the model assignments, with the diagram inline. Then wait
for one yes.

Exactly one plan approval exists in a run. Nothing is dispatched before it, and
the manager never re-asks what was approved here.

## Record the plan on accept

On the operator's yes, record the plan on the run's tracker, in this order.

A GitHub input requires no BB Task, and none is created: the parent issue is
the run's record. When a Task key and a GitHub issue are both given, both
records are written.

**Task record** (a `.scratch` input, or any run that also carries a Task key):

1. Comment a markdown version of the plan on the Task and capture the returned
   comment id:
   `bb tasks comment <KEY> --body-file <plan.md> --json`
2. Attach the diagram to that same comment, so it survives archiving this
   thread — inline directives do not render in Task comments:
   `bb tasks attachment add <comment-id> --file "$BB_THREAD_STORAGE/reports/orchestration-plan.html" --json`
3. Move the Task to `in_progress`.

**GitHub record** (a GitHub input): comment the markdown plan on the parent
issue and stop there:
`gh issue comment <parent> --body-file <plan.md>`

No attachment and no inline directive: an issue comment renders neither, and
the HTML artifact stays in the orchestration thread where the approval happens.
No label is added or removed, and no `in_progress` equivalent is invented — the
run does not overwrite the tracker's vocabulary with its own.

Comments are append-only in both trackers — no edit, no delete — and
attachments have no replace-in-place, so a re-plan appends a versioned record
(`# Plan v2`) rather than editing history.

## The manifest

The manager's prompt is a **manifest**: data only, no instructions. Field list,
and nothing else:

- the feature name and the Task identity (key or ULID) when there is one
- the tracker, explicit and never inferred from the shape of a reference:
  `tracker: scratch <feature>` or `tracker: github <owner/repo>#<parent>`
- the flow: `A`, `B`, or the cross-repo shape named as itself
- the items, one per line:
  `id · short title · ticket · file scope · blockedBy` — the ticket is the
  item's own reference, `#<issue-number>` for GitHub, so the manager fetches
  exactly the ticket an item names rather than re-deriving it
- the waves: which item ids dispatch together
- run notes the tickets cannot supply: cross-repo paths, run-alone handling,
  approval gates
- a model line only when the operator overrode the role defaults

The test for inclusion is procedural: **does this line tell the executor how to
do something its own skill already specifies?** If yes, it is wrong — cut it.
Role models, spawn flags, review loops and ledger mechanics live in
`/orchestrate-bb-threads` and are never restated here.

The item ticket reference is what the manager reads: a GitHub ticket comes from
`gh issue view <n> --json title,body,comments`, and the parent issue's body is
the spec context for a worker's instructions.

Write it to `$BB_THREAD_STORAGE/manifest.txt`; the spawn step passes that file.

## Spawn the manager

Spawn the manager as this thread's child, into the plan thread's own
environment, with every choice explicit — no argument is left to a default:

```sh
bb thread spawn --parent-self \
  --environment "$BB_ENVIRONMENT_ID" \
  --model "<worker-model>" \
  --title "ORCHESTRATE <feature>" \
  --permission-mode auto --json \
  --prompt-file "$BB_THREAD_STORAGE/manifest.txt"
```

`--prompt-file` keeps the manifest out of shell quoting. On the pi provider
`auto` is rejected ("Provider pi only supports full permission mode") — pass
`full` there, matching the plan thread's own ceiling. Record the manager's
thread id.

## Wait for the run

The plan thread lives as long as the run. Wait on the manager in a
timeout-and-recheck loop and read the run's terminal state from the ledger,
never from the manager's idle status — the manager pauses at the commit+PR
gate, which is exactly when the run is not over:

```sh
bb thread wait <manager-id> --status idle --timeout 1800 --json
bb status --json   # → dataDir; ledger at "$dataDir/thread-storage/<manager-id>/orchestration.json"
```

Exit only when `finishedAt` is set in that ledger. A wait timeout is not a
failure: if the thread is still working, wait again. A long plan turn — an hour
or more — is normal: it is blocked on `bb thread wait`, not thinking.

A manager that reports `error`, or reaches a terminal state without a
`finishedAt`, is surfaced to the operator with its log. The plan thread never
respawns it.

## Spawn the retro

Once `finishedAt` is set, spawn the retro thread from the plan thread, as the
manager's sibling rather than its child — the run tree then reads as phases:

```sh
bb thread spawn --parent-self \
  --environment "$BB_ENVIRONMENT_ID" \
  --title "RETRO <feature>" \
  --permission-mode auto --json \
  --prompt "/orchestrate-bb-retro <manager-id>"
```

The plan thread's job ends there: report the run's outcome and the retro thread
to the operator.
