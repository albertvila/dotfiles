---
name: orchestrate-herdr-plan
description: "Plan a Herdr orchestration run and take one approval before anything is dispatched, then run it as the coordinator of this Herdr pane with /orchestrate-herdr-threads. Use when the user says '/orchestrate-herdr-plan', or gives a `.scratch/` feature directory, a GitHub issue number, `owner/repo#n` or an issue URL to run. Pass --land to skip the commit yes, open the PRs, and stop for verification. Pass --unattended to do that without a plan yes. Neither flag merges."
argument-hint: "@.scratch/<feature>/ | <#issue|owner/repo#issue|issue-url> [--land|--unattended]"
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
- **A GitHub issue** — a parent whose tickets are its sub-issues or the issues
  that name it in their `## Parent` section, or a direct issue with none of
  either. Accepted as `#42` / `42`, resolved against this pane's `origin`
  repository, as `owner/repo#42`, or as a full issue URL. Issues
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

[`plan.md#reading-a-github-issue`](../orchestrate-core/plan.md#reading-a-github-issue)
owns it.

## Plan the run

Steps 1–6 and the completeness rule are
[`plan.md#plan-the-run`](../orchestrate-core/plan.md#plan-the-run).

7. Record the **launch reality**. Workers, reviewers and the ponytail pass are
   all `herdr agent start … --kind pi` agents in their own tabs of this
   workspace; the operator watches them in the tab bar and the coordinator never
   shares a pane with them. Role models are pi's own: workers and the ponytail
   pass run on pi's configured default and reviews default to
   `openrouter/z-ai/glm-5.3`, passed as
   `-- --model <pattern>`. Read pi's default once so the approval states it
   truthfully rather than guessing:

   ```sh
   python3 -c "import json;s=json.load(open('$HOME/.pi/agent/settings.json'));print(s.get('defaultProvider','?')+'/'+s.get('defaultModel','?'))"
   ```

   A per-run override is operator syntax — "workers on X, reviewers on Y";
   ponytail follows the worker model unless the line also names one. Check every
   named model against `pi --list-models` before approving it; a model that does
   not work stops the run (see *Models* in `/orchestrate-herdr-threads`).

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

The mode read, the stop conditions and what the message must present are
[`plan.md#one-approval`](../orchestrate-core/plan.md#one-approval). This runtime
adds the launch reality and the diagram to the message, and timestamps the ask
first (`date -u +%Y-%m-%dT%H:%M:%SZ`) — that timestamp becomes the plan gate's
`requestedAt`.

`gated` and `land` **end the turn** with the question. Nothing is dispatched
before the yes: no tab, no agent, no worktree. An approval in Herdr is the
operator's next message in this pane; a coordinator that keeps working after
asking has ignored the gate.

`unattended` does not end the turn and does not ask. Set `approvedAt` to the
same timestamp as `requestedAt`, set `auto: true`, write the plan record, and
continue in this turn.

## Record the plan on accept

On the operator's yes, or immediately when `mode` is `unattended`, timestamp the accept
(`date -u +%Y-%m-%dT%H:%M:%SZ`) — that is the plan gate's `approvedAt`; for
`unattended` it equals `requestedAt` — and write the record once:

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
[`../orchestrate-core/manifest-contract.md`](../orchestrate-core/manifest-contract.md)
owns the shape, and [`plan.md#the-manifest`](../orchestrate-core/plan.md#the-manifest)
owns what goes in it. This runtime adds the run directory `$RUNDIR`, so the run
can be found again, and the base and plan gate on the `mode` line, so the ledger
opens with real human-wait numbers.

**Check it before handing it on.** The contract's checker is the machine form of
the completeness rule in [`plan.md`](../orchestrate-core/plan.md#plan-the-run) —
the plan is ready to render when every item has a scope, an acceptance line, an
out-of-scope line and a wave:

```sh
python3 ~/.agents/skills/orchestrate-core/scripts/validate-manifest.py "$RUNDIR/manifest.txt"
```

`FAIL:` names every error with the line it is on; a non-zero exit means the
manifest is not the plan that was approved. Fix what it names and run it again.
If a fix changes an item, a file scope, an acceptance line, a wave or the mode,
the approval no longer covers the run — re-render the plan and take it again
(`unattended` records it rather than asking) before anything is dispatched.

## Execute the run

In this same turn as the approval reply — or the same turn as the plan record,
when `mode` is `unattended` — follow `/orchestrate-herdr-threads` in
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

**A turn that ended mid-run is re-entered from the ledger.** After a context
exhaustion, a provider error or a suspended host, read `$RUNDIR/orchestration.json`
and continue from it — never from memory. This pane is the run's only
coordinator, so it never starts a second one.

## Spawn the retro

Once `finishedAt` is set in the ledger, spawn the retro as the run's own last
agent, so it is visible in the tab bar instead of being this pane's private
afterthought — at that moment, never behind the PRs' checks or the verification
ask. Record the returned `agent_session.value` under the ledger's `retro` row
(`{id, session, tab}`) in the same turn:

```sh
tab=$(herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$PWD" \
  --label "RETRO <feature>" --no-focus)
pane=$(printf '%s' "$tab" | jq -r '.result.root_pane.pane_id')
# retro- + the feature slug trimmed to 26 chars: 32 is the hard name limit
slug=$(printf '%s' "<feature-slug>" | cut -c1-26)
herdr agent start "retro-$slug" --kind pi --pane "$pane"
herdr agent prompt "retro-$slug" "/orchestrate-herdr-retro $RUNDIR" \
  --wait --timeout 12000
herdr notification show "Run settled" --body "RETRO <feature> is running" --sound done
```

A `timeout` from that prompt is the expected exit code — the retro submitted and
started working. Only `agent_prompt_stalled` or `agent_blocked` needs the
inspection the threads skill's reply table prescribes.

The retro is read-only against the run; it cannot spawn anything, and it does
not need to. For `gated` this pane's job ends by reporting the run's outcome and
the retro tab to the operator. For `land` and `unattended` that report is the
verification ask in `../orchestrate-core/run-mode.md`, and it is **not**
the last act: the operator's reply that the PRs are merged resumes this pane,
which runs that file's *After the operator merges* steps. Do not merge.
