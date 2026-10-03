---
name: orchestrate-herdr-plan
description: "Plan a Herdr orchestration run and take one approval before anything is dispatched, then run it as the coordinator of this Herdr pane with /orchestrate-herdr-threads. Use when the user says '/orchestrate-herdr-plan', or gives a `.scratch/` feature directory, a GitHub issue number, `owner/repo#n` or an issue URL to run."
argument-hint: "@.scratch/<feature>/ | <#issue|owner/repo#issue|issue-url>"
disable-model-invocation: true
---

# Orchestrate Herdr Plan

One loop, three skills, one pane: **plan → run → retro**. This skill is the plan
phase and the run's umbrella: it decides the run's shape, items, waves and
models; takes one approval; writes the manifest; executes the plan in this same
pane with `/orchestrate-herdr-threads`; and spawns the retro when the run
settles.

**Why this pane coordinates.** Herdr has no parent→child edge between agents and
no mail between panes: a manager agent would be one more hop, and a gate it
asked would sit in a pane nobody is looking at. So the BB shape — a plan thread
spawns a manager that spawns workers — collapses here: this pane approves,
coordinates and reports, and every worker is a pi agent in its own tab. That is
why this skill ends by handing off to the threads skill instead of spawning it.

## Input

Two input shapes:

- **A `.scratch/<feature>/` directory reference** (`@.scratch/<feature>/`) — read
  `spec.md` and the `NN-*.md` files under `issues/`. The directory must exist in
  this pane's worktree: the run directory, the plan artifact and the ticket
  write-back all live beside it.
- **A GitHub issue** — a parent whose sub-issues are the tickets, or a direct
  issue with none of its own. Accepted as `#42` / `42`, resolved against this
  pane's `origin` repository, as `owner/repo#42`, or as a full issue URL. Issues
  and pull requests share one number space: check which one resolved and refuse
  a pull request by naming the reason.

There is no task-tracker form. Herdr has no ticket tracker, and the run's own
record is the ledger plus its pi session transcripts, not an external key.

## Preflight

Run all four checks before planning; each one is a stop, not a warning:

1. **This pane is a Herdr agent.** `test "${HERDR_ENV:-}" = 1` must pass. From
   outside Herdr there is no pane context for the worker tabs and no
   `HERDR_WORKSPACE_ID` to hang them on: start a pi agent inside a Herdr pane
   and prompt it with this skill there.
2. **The pi integration is current.** `herdr integration status` must report
   `pi: current`. Without it `herdr agent prompt --wait` returns
   `agent_prompt_stalled` while the agent is in fact working, and the whole wait
   loop misreads running workers. Fix it first: `herdr integration install pi`.
3. **This worktree owns the input.** A `.scratch` input must be readable from
   the current directory; `herdr worktree list --cwd "$PWD"` names the source
   checkout, and Flow B needs a git work tree to create worktrees in. A folder
   workspace caps the run at Flow A, and the approval message says so.
4. **GitHub input only:** `gh auth status` must pass, and the issue's repository
   must match this worktree's `origin` — item file scopes are inferred against
   this checkout's code, so a mismatch stops the run with the mismatch named.

`gh pr create` and the lm status commands (see the threads skill) run from this
worktree, so a repo whose PRs need credentials the session lacks is a fifth
check for that repo's own workflow.

## Reading a GitHub issue

Preflight has passed, so these are reads. Nothing is written to a sub-issue at
plan time.

**Ticket set.** Every sub-issue of the parent, one level deep, read the way
`.scratch/<feature>/issues/` is read. Sub-issues come first; when the sub-issues
API returns nothing — an empty array, not an error, which is what a repository
without issue relationships returns — the parent body's task list is the fallback
ticket set; and only when the body carries no task list either does the parent
body become the single ticket. Which source produced the set is stated in the
approval message.

**Graph.** Read once, at plan time, from the native `blockedBy` edges when there
are any, otherwise from the parent body's `## Blocked by` section. A disagreement
between the two sources is reported. The graph is never re-polled during the run:
GitHub calls an issue unblocked only when its blocker is *closed*, which lags a
run whose blockers are already `done` in the ledger. Sub-issue order is never a
graph.

**Naming.** The feature name is the parent issue title, slugified — it drives the
run directory, the plan artifact and the `RETRO <feature>` tab. An item's id is
`#<issue-number>`, so tab labels, ledger keys and frozen diff filenames need no
translation layer.

**Exclusions.** Closed sub-issues are read, excluded from the item list, and
counted as satisfied blockers. Sub-issues in another repository are excluded
outright — a plan never claims scope the coordinator cannot read code for. Every
excluded issue is named by number in the approval message, under the
`tickets in → items out` line.

## Plan the run

1. Read the spec and every ticket: the `NN-*.md` files under the feature
   directory, or the ticket set resolved from a GitHub parent above.
2. Build the graph from each ticket's `**Blocked by:**` line — that line is the
   graph, not an inference. A GitHub input's graph was fixed by the read above.
3. Assign each item a file scope from what it will build. Disjoint scopes plus
   settled blockers form a parallel **wave**; overlapping scopes serialize.
4. **Reduce the item count first — that is the default move, not a flag to
   raise.** Every item costs a fresh worker tab plus a fresh-eyes review tab, so
   one item per ticket is the wrong starting point. Items with identical file
   scopes merge into one item unless the work needs independent verifiability or
   independent rollback: a reset or history rewrite, an item ending in a push or
   merge rather than a PR, or an acceptance criterion no single reviewer can
   cover. Name that exception in the approval message.
5. Flag the special handling so the coordinator and its reviewers start with the
   facts: run-alone resets, items ending in a push or merge, approval gates, and
   any acceptance criterion reaching into another repo or plugin — list that
   path.
6. Record the **launch reality**. Workers, reviewers and the ponytail pass are
   all `herdr agent start … --kind pi` agents in their own tabs of this
   workspace; the operator watches them in the tab bar and the coordinator never
   shares a pane with them. Role models are pi's own: workers and the ponytail
   pass run on pi's configured default and reviews default to
   `openrouter/anthropic/claude-sonnet-5`, passed as
   `-- --model <pattern>`. Read pi's default once so the approval states it
   truthfully rather than guessing:

   ```sh
   python3 -c "import json;s=json.load(open('$HOME/.pi/agent/settings.json'));print(s.get('defaultProvider','?')+'/'+s.get('defaultModel','?'))"
   ```

   A per-run override is operator syntax — "workers on X, reviewers on Y";
   ponytail follows the worker model unless the line also names one. Check every
   named model against `pi --list-models` before approving it; a model that does
   not work stops the run (see *Models* in `/orchestrate-herdr-threads`).

The plan is ready to render when every ticket has a disposition — its own item or
merged — and every item has a file scope, a wave, and any exception named.

## Render the plan

Write the plan to `$RUNDIR/plan.md`, where `$RUNDIR` is the absolute run
directory `<worktree>/.herdr-runs/<feature>/` — created if missing, never
committed, and handed unchanged to the threads and retro skills. Then show it to
the operator **in the chat**, as the approval message body: the flow, the waves,
the items as a compact chain, the launch reality, and the run notes. Markdown
tables and a small ASCII wave diagram are the whole artifact format — Herdr has
no inline rendering directive and no file-open verb, so there is nothing to
embed.

Diagram shape: items in execution order as a vertical chain with a status word;
blocked-by noted on the left (`← 01`); parallel lanes drawn side by side; a
one-line footer showing the per-item worker → review → findings loop (cap 3) and
the run's end boxes (ponytail pass, then commit+PR or ticket write-back).

## One approval

Present in the approval message: the flow (A, B, the cross-repo shape named as
itself, or `A+cross-repo` when the items mix an in-repo item with one whose files
sit outside every repository), the reduction made — **tickets in, items out**,
with every excluded issue named by number beneath it and, for a GitHub input,
which source produced the ticket set — the waves, the per-item notes, the launch
reality above, and the diagram. Then **end the turn** with the question. Timestamp
the ask first (`date -u +%Y-%m-%dT%H:%M:%SZ`) — that timestamp becomes the plan
gate's `requestedAt`. Nothing is dispatched before the yes: no tab, no agent, no
worktree.

An approval in Herdr is the operator's next message in this pane; a coordinator
that keeps working after asking has ignored the gate.

## Record the plan on accept

On the operator's yes, timestamp the accept
(`date -u +%Y-%m-%dT%H:%M:%SZ`) — that is the plan gate's `approvedAt` — and
write the record once:

- **`.scratch` input** — `$RUNDIR/plan.md` is already the record; append nothing
  to the spec and change no ticket. The spec's own `**Status:**` line is flipped
  by the threads skill when the run settles.
- **GitHub input** — comment the markdown plan on the parent issue and stop
  there: `gh issue comment <parent> --body-file "$RUNDIR/plan.md"`. No
  attachment, no label, no `in_progress` equivalent invented.

Comments are append-only in both trackers — a re-plan appends a versioned record
(`# Plan v2`) rather than editing history.

## The manifest

Write `$RUNDIR/manifest.txt` for the threads skill: data only, no instructions.
Field list, and nothing else:

- the feature name and the run directory `$RUNDIR`
- the tracker, explicit and never inferred from the shape of a reference:
  `tracker: scratch <feature>` or `tracker: github <owner/repo>#<parent>`
- the flow: `A`, `B`, or the cross-repo shape named as itself — and
  `A+cross-repo` when the items mix an in-repo item with one whose files sit
  outside every repository (no worktree, no branch, no PR is possible). Never
  write such a run as plain `A`: the threads skill dispatches on this field, and
  the ledger and the retro trust it
- the base branch for a Flow B or cross-repo run: `base: <ref>`
- the plan gate: `plan-gate: requested=<ISO-8601 UTC> approved=<ISO-8601 UTC>`,
  so the ledger opens with real human-wait numbers
- the items, one per line:
  `id · short title · ticket · file scope · blockedBy` — the ticket is the
  item's own reference, `#<issue-number>` for GitHub, so the coordinator fetches
  exactly the ticket an item names rather than re-deriving it
- the waves: which item ids dispatch together
- run notes the tickets cannot supply: cross-repo paths, run-alone handling,
  approval gates
- a model line only when the operator overrode the role defaults

The test for inclusion is procedural: **does this line tell the executor how to
do something its own skill already specifies?** If yes, cut it. Start flags,
review loops and the ledger mechanics live in `/orchestrate-herdr-threads`.

## Execute the run

In this same turn as the approval reply, follow `/orchestrate-herdr-threads` in
this pane. Read that skill's file; do not restate it and do not spawn a
coordinator — this pane is the coordinator.

## Wait for the run

This pane lives as long as the run. The waiting loop is the threads skill's own —
`herdr agent prompt --wait` and `herdr agent wait` around the worker tabs — and
the run's terminal state is read from the ledger's `finishedAt`, never from a
worker's idle or done status: the commit+PR gate is exactly when the run is not
over. A long wait — many minutes on one worker — is normal.

A worker that reports `blocked` is surfaced to the operator with its question;
the operator's reply in this pane resumes the run. The coordinator never
respawns a worker just to avoid a gate.

## Spawn the retro

Once `finishedAt` is set in the ledger, spawn the retro as the run's own last
agent, so it is visible in the tab bar instead of being this pane's private
afterthought:

```sh
tab=$(herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$PWD" \
  --label "RETRO <feature>" --no-focus)
pane=$(printf '%s' "$tab" | jq -r '.result.root_pane.pane_id')
herdr agent start "retro-<feature-slug>" --kind pi --pane "$pane"
herdr agent prompt "retro-<feature-slug>" "/orchestrate-herdr-retro $RUNDIR" \
  --wait --timeout 12000
herdr notification show "Run settled" --body "RETRO <feature> is running" --sound done
```

A `timeout` from that prompt is the expected exit code — the retro submitted and
started working. Only `agent_prompt_stalled` or `agent_blocked` needs the
inspection the threads skill's reply table prescribes.

The retro is read-only against the run; it cannot spawn anything, and it does
not need to. This pane's job ends by reporting the run's outcome and the retro
tab to the operator.
