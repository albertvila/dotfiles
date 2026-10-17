---
name: orchestrate-herdr-threads
description: "Execute an approved orchestration plan as the coordinator of this Herdr pane: dispatch pi agents into their own tabs, keep the ledger, route reviews, land the run. Use when the user says '/orchestrate-herdr-threads', or this pane carries a manifest from /orchestrate-herdr-plan."
---

# Orchestrate Herdr Threads

Execute an approved plan. **This pane is the coordinator**: it dispatches one pi
agent per work unit into its own Herdr tab, keeps the ledger, routes review
findings, and lands the run. [`threads.md#the-executors-job`](../orchestrate-core/threads.md#the-executors-job)
owns the job, the manifest rule and the dispatch-before-touching rule; this file
owns the Herdr mechanics.

Read [../orchestrate-core/run-mode.md](../orchestrate-core/run-mode.md)
before the first dispatch. It owns `mode`, the CI baseline, the validation exit
code, Flow B bases, and the merge command. A sentence in this file that
disagrees with it is wrong.

**The body is order; the references are mechanics.** Three files under
[`references/`](references/) — waiting, prompts, record — are loaded at the step
that acts on them, and each stub below names what it owns and what goes wrong
without it. Read the reference, not the stub, before the step it belongs to. The
body stays under 40 KiB (`tests/skills_budget_test.sh`): anything only one step
needs belongs in a reference, not here.

`$RUNDIR` is the run directory `<worktree>/.herdr-runs/<feature>/`. Entered from
`/orchestrate-herdr-plan` it is already set; entered directly, resolve it as the
most recent `.herdr-runs/*/manifest.txt` in this worktree and say which run was
picked.

## Failure handling

- **A suspended host ends every live turn, and nothing in the run can say so.**
  Closing a laptop drops the network first and then freezes the machine: every
  in-flight turn — the workers' and the coordinator's own — dies on provider
  timeouts, the ledger stops being written, and the run resumes only when the
  operator wakes the host and prompts `continue`. In the run that produced this
  line that was 9h31m of a 13h20m span, and the two dead turns looked exactly
  like a slow model: `Request timed out.` ×3, `Retry failed after 3 attempts`.
  For a `land` or `unattended` dispatch, say which it is: keep the host awake
  (`caffeinate -s` **on AC power**, or the platform's equivalent — clamshell
  sleep on battery overrides an idle or display assertion), or accept that the
  run pauses at the lid and tell the operator the run is waiting on the machine.
  On resume, the first move is the stalled-turn recovery in `references/waiting.md` — `agent read`
  each live agent, then `continue` the same agent — and the timestamps the ledger
  gains are the resume's, not the sleep's.
- A coordinator turn that spans the whole run is normal: the coordinator is
  blocked on `herdr agent wait`, not thinking.
- A resumed coordinator re-reads the ledger and the ticket files before acting —
  its own memory of the run may be stale.
- An agent reports `BLOCKED`, or `agent get` no longer finds it: read its
  report, `agent read` tail and logs before respawning anything, record the
  blocker in the ledger (`worker_blocked` for a question, `turn_stalled` when the
  turn died), surface it to the operator, and keep working the rest
  of the frontier.
- **Never act on absence.** A failed `agent get`, an `unknown` status and a wait
  timeout are all unverifiable: inspect the pane and its transcript before
  deciding anything. Positive evidence that an agent is gone is `agent get`
  reporting no such agent while its pane shows a shell prompt again. Only then
  is a respawn — same pane, same name — the move.
- A `herdr agent start` that exits non-zero is **not** relaunched blindly: read
  its error code and surface it — an item that could not be started is `failed`
  with `cause.code: dispatch_failed`. A refused start is a fact about the run,
  not a retry prompt.
- **A turn that ended mid-run is re-entered from the ledger.** After a context
  exhaustion, a provider error or a suspended host, read `$RUNDIR/orchestration.json`
  and continue from it — never from memory, and never by starting a second
  coordinator. This pane is the run's only coordinator.
- The coordinator never answers a blocked dialog it cannot answer from the
  approved manifest, never stops an agent it did not start, and never closes a
  tab it did not create.

## Rules

[`threads.md#rules`](../orchestrate-core/threads.md#rules) owns the shared
rules. The Herdr-specific one: workers, reviews, fix rounds and ponytail passes
are all normal pi agents in their own tabs; every settled one ends in a release
decision (closed), or retention the operator asked for.

## Where work runs

One work unit = one tab + one named pi agent in that tab's root pane. The
coordinator keeps its own pane; workers never share a pane, with the coordinator
or with each other.

```sh
# placement — a no-focus tab in this workspace (Flow A) or the item's (Flow B)
tab=$(herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$PWD" \
  --label "ITEM <id> · <short title>" --no-focus)
pane=$(printf '%s' "$tab" | jq -r '.result.root_pane.pane_id')
# label convention: ITEM · REVIEW · PONYTAIL · FIX · RETRO

# start — pi's own flags go after `--`; reply is JSON on stdout
herdr agent start "item-<slug>" --kind pi --pane "$pane" \
  > "$RUNDIR/logs/start-item-<slug>.json"

# submit — activity gate, not the finish line
herdr agent prompt "item-<slug>" "$(cat "$RUNDIR/prompts/item-<slug>.txt")" \
  --wait --timeout 12000 > "$RUNDIR/logs/prompt-item-<slug>.json" 2>&1
```

`herdr agent start` returns only once pi is ready for input; its JSON carries
`agent_session.value` (the pi session transcript the retro reads), `pane_id` and
`argv`. Record all of them in the ledger.

**Write the item's `dispatchAttempt` before `herdr agent start`.** The write
(`{at, role, label}` — the label is the tab label you are about to use) is what a
coordinator resumed after a death looks for: an attempt with no lane recorded
beside it is resolved with `herdr agent list` for the lane whose tab carries that
label, **before** any replacement is started. A start that already happened is a
duplicate, not a retry ([threads.md](../orchestrate-core/threads.md#the-ledger)).

**Names.** `[a-z][a-z0-9_-]{0,31}`, unique among live agents — a settled agent
still holds its name until it exits. `<slug>` is the item id lowercased with `#`
dropped and everything outside `[a-z0-9_-]` collapsed to `-`, trimmed to 22
chars: `item-01`, `review-01-r2`, `fix-01-f1`, `ponytail`. The retro's name is
`retro-` + the feature slug **trimmed to 26 characters** — the prefix and the
32-character limit leave no more room, and an untrimmed 30-character slug is
refused outright with `invalid_agent_name`.
A refused start (`agent_name_taken`, `agent_not_ready`, …) is surfaced with its
error code; the coordinator never renames, stops, or repurposes an agent it did
not start.

## Reply codes

Read `herdr agent prompt --wait --timeout 12000` by its exit code and
`.error.code`, never by hope:

| Result | Meaning | Move |
|---|---|---|
| exit 0, `agent_status: done` / `blocked` | the prompt settled fast (small item, or blocked immediately) | read it; no wait needed |
| exit 1, `timeout` | **submitted and working** — the 12 s activity gate fired, the turn is still running | wait for settlement |
| exit 1, `agent_prompt_stalled` | the prompt was **not confirmed delivered** | inspect `agent get` and `agent read`; never blind-resend |
| exit 1, `agent_blocked` | the agent was already waiting at a dialog | inspect; surface to the operator |

Any other error is surfaced with its code. A `timeout` is the expected result
for every real work unit: 12 seconds is how long Herdr watches for the turn to
start, not how long the work takes. An **empty prompt log** (exit 0, nothing
written) proves neither delivery nor failure — confirm from
`logs/start-<name>.json`'s session path and the agent's own file on disk before
deciding anything.

## Waiting

Load [`references/waiting.md`](references/waiting.md) at the first settle, and
again the moment a turn stalls. It owns the settle loop, what Herdr's `idle` and
`done` mean, the stalled-turn recovery, tab release and the respawn command — a
settle written from this stub gets one of those wrong, and the run then waits on
an agent that already stopped.

## Prompt contracts

Load [`references/prompts.md`](references/prompts.md) before writing the first
prompt file. It owns the worker, review, ponytail and fix contracts verbatim, the
report each one writes, and the rule that every prompt is self-contained and
quotes the item's `acceptance` and `out-of-scope` lines from the manifest — a
prompt written from this stub drops one of them, and the agent it starts reports
something no review can check.

## The run's record

There is no Tasks panel for this — the coordinator IS the tracker. **Open the
run first:** create its working directories, record the coordinator as
`executors[0]`, and seed the ledger from the manifest — items with
`status: todo`, `criteria` and `outOfScope` verbatim, `startedAt` (UTC), the
manifest's plan gate under `gates.plan`, and the resolved `models`. Then
dispatch, before reading any item's files. Keep `$RUNDIR/orchestration.json`
true as the run moves, never batched at settlement — and stamp the times the
pane and the retro both read: `startedAt` when you dispatch a worker or a
review, `endedAt` when it settles:

```sh
mkdir -p "$RUNDIR"/{logs,prompts,reports,diffs,snapshots}
herdr agent get "$HERDR_PANE_ID" | jq -r '.result.agent.agent_session.value'   # coordinator session
```

**Load [`references/record.md`](references/record.md) before the first write.**
It owns the Herdr field list, the runtime extensions, the ponytail lane's shape,
the typed stops, the reopen rule and the pane projection — the ledger's *shape*
as opposed to the order below, which stays here. A record written from this page
has the right opening and the wrong fields, and the pane, the checker and the
retro then read three different runs.

**Check every write, and never dispatch on a non-zero exit.** The ledger is what
resume and the retro read; a record that contradicts itself charges them for a
mistake the coordinator already knows it made.

```sh
python3 ~/.agents/skills/orchestrate-core/scripts/validate-ledger.py "$RUNDIR/orchestration.json"
```

What it refuses is the half a single snapshot can prove, item by item, against
[`threads.md#the-item-lifecycle`](../orchestrate-core/threads.md#the-item-lifecycle).
The projection in `references/record.md` imports the same checks, so the pane cannot disagree with it.

**Stamp the times honestly, and assert them.** Every timestamp you write is read
from `date -u` at the moment of the event — never typed, never rounded to the
minute, never the time you meant to ask at. A literal `requestedAt` written 65
seconds before the gate question was posted shortens the human wait the retro
reports; an `endedAt` rounded down understates the item. An item's `endedAt` is
that item's own last settlement — its worker, its review, its fix round — never the
gate's `requestedAt`; gate times belong in `gates` and nowhere else. Before
writing, check what you are about to record: every agent's `startedAt ≤ endedAt`,
and both inside that agent's session window. An interval that runs backwards or
predates the agent's own transcript is a write error, not a rounding artefact.
The projection below reports the write errors `scripts/validate-ledger.py`
refuses, so the pane cannot disagree with the checker; containment in the agent's
own session window is asserted by the retro, which is the only reader holding
both sides.

**A reopen clears the terminal marker.** Reopening an item sets `status` back to
`running`, nulls the item's `endedAt`, records why under the item, and clears
`finishedAt` — a terminal marker must never stand over a live item, and the retro
reads `finishedAt` as "nothing is in flight". Re-stamp `finishedAt` when the
reopened item settles again, and remember that a reopen after the commit gate
leaves the PR's evidence describing the previous revision: say so at the next
gate, and follow the work with `branch` — a follow-up that ships on its own
branch updates the field, or the ledger names a branch it already deleted.

The run is done when every item carries a terminal status (`done`, `failed`, or
`blocked`), every `done` item's PR is open or merged and handed over, and the
blocked items are surfaced to the operator. `land` and `unattended` set
`finishedAt` when the PRs are open. An unmerged PR is finished for those modes. An out-of-repo item
(`A+cross-repo`) has no PR to hand over: its named operator gate stands in for
one, and it is surfaced like a blocked item until that gate is done. Once
`finishedAt` is written, the run's last act is its retro agent — spawn it exactly
as `/orchestrate-herdr-plan` (*Spawn the retro*) does, at that moment and never
behind the PRs' checks: the retro reads the run while the checks are still
running, and a spawn parked behind a `gh pr checks --watch` costs the run the
whole wait. This skill does not restate the spawn.

## Flow A — one shared worktree, one PR

Shape `A` is [`threads.md#flow-shapes`](../orchestrate-core/threads.md#flow-shapes).
In this runtime every worker runs in **this pane's worktree** (`--cwd "$PWD"`).

For `tracker: github <owner/repo>#<parent>`, claim the parent and every item
issue before spawning — not an excluded issue:

```sh
gh issue edit <n> --repo <owner/repo> --add-assignee @me
gh issue edit <n> --repo <owner/repo> --remove-label ready-for-agent
```

`@me` is the authenticated `gh` user. Nothing replaces the label. Do not close,
and do not add or remove any other label. A scratch tracker has no issue to
claim. Then **dispatch before reading any item's code**. The coordinator never
opens an item's files to change them: an item implemented here has no worker
agent, no ledger entry and no reviewer it can honestly claim.

1. **Dispatch every ready item's worker** into its own tab, in the manifest's
   wave, and record each returned agent, pane, tab and session in the ledger.
2. **Parallel only on disjoint files; reviews overlap the next worker.** The
   rule is [`threads.md#flow-shapes`](../orchestrate-core/threads.md#flow-shapes);
   apply it from the item scopes plus what already changed in the worktree
   (`git status`, files touched by running workers).
3. **Wait, then collect.** Settle every running agent (see `references/waiting.md`), read its
   report and final message, and mark the item `done` or `blocked`/`failed`
   from evidence — the worker's `DONE` is a claim, not proof. This step runs to
   completion before the turn ends: the coordinator's turn ends at a pending
   gate question or at the run's end, never between a dispatch and its settle.
   A turn that ends with agents in flight leaves the run unwatched — nothing
   notices a stalled reviewer, and only a human poke restarts it.
4. **Freeze the diff before reviewing it**, once per pass — the next worker may
   already be changing the same worktree, and a pass must read bytes that cannot
   move under it:

   ```sh
   mkdir -p "$RUNDIR/diffs"
   { git diff HEAD -- <item files>; printf '\n# worktree status:\n'; \
     git status --porcelain -- <item files>; } > "$RUNDIR/diffs/<slug>-r<n>.diff"
   ```

   `<n>` is the review pass the freeze feeds, and the file is never rewritten:
   pass n+1 writes its own, which is what lets the re-review gate compare the two.
   `git diff HEAD` shows **nothing** for files the worker created new; the
   appended porcelain line is what makes a new file visible. For an item whose
   files are all untracked, copy them into
   `$RUNDIR/snapshots/post-<slug>-r<n>/` and point the review at that instead.

   Then start a fresh-eyes review agent — same workspace, reviewer model, its
   own tab. Scale its depth to the item's risk, per the review contract: a
   **high-risk** item — real state, logic, or contract surface (schemas, fetch
   lifecycles, data scoping) — gets the full adversarial prompt in this thread;
   a **mechanical** item — deletions, renames, rendering-only, docs, config —
   gets the frozen diff plus a short completeness check. Neither invokes the
   two-axis `/code-review` skill.
5. **One ponytail pass on the combined diff**, once every item's review is
   clean, in its own tab on the full uncommitted diff. The pass reports ponytail
   findings only; anything else it notices goes in the same report as an
   out-of-band note. **A note that names a defect — real behaviour, or a named
   acceptance criterion — is not a preference: it opens a fix round before the
   commit gate.** The coordinator confirms it against HEAD, the item's files are
   fixed by the worker model (the item's own agent while its pane is live), and
   the next ponytail pass re-checks it; a fix that changes behaviour, state or a
   contract surface also gets a fresh-eyes review of its delta, per the review
   contract. A preference, a style choice, or an observation
   with no gate behind it stays out-of-band: not fixed in-run, reported to the
   operator in the run summary. **The item's `done` write waits for that pass** —
   write it when the pass has settled, not when its tab opens or while it runs:
   the ledger reads `done` as an item whose ponytail pass has settled, and an
   item marked `done` with a fix round open is the state that rule exists to
   prevent. Its `endedAt` comes from `date -u` like every other stamp, never
   typed. In a multi-repo run there is no combined diff: one ponytail pass per
   item diff, none optional.
6. **Commit + open one PR.** Do not open this gate until
   [run-mode.md](../orchestrate-core/run-mode.md) validation exited 0.
   `land` and `unattended` do not end the turn and do not ask: record the gate
   with `auto: true` and the conventional message, then create the run branch and
   commit as the next sentence requires — and open the PR as a draft titled
   `[AI-DRAFT] <the commit's subject>` (`--draft --title …` on the `gh pr create`
   below), per [run-mode.md](../orchestrate-core/run-mode.md).
   `gated` proposes the commit message and file list to the
   operator (per repo conventions; detect the PR base branch), records
   `gates.commit.requestedAt`, and **ends the turn** with the question. This pane
   is the only one that can answer it, so the reply that arrives here is the
   approval, and nothing is committed before it. On yes: record
   `gates.commit.approvedAt`, **create the run branch first** — this pane's
   worktree is checked out on the base branch, so a bare `git push HEAD` puts the
   run's commit on the base and needs a force-push to undo it; `git checkout -b
   "<branch>"`, or `git push origin HEAD:refs/heads/<branch>`, before anything
   leaves the worktree — commit, push the branch, open exactly one PR
   (`gh pr create`), then post the repo's own status checks if its PRs publish
   `lm-build/*`:

   ```sh
   lm pr-test --base origin/<base>
   lm report-upload
   ```

   Run the upload even when pr-test fails, so GitHub gets a failure instead of a
   missing check. Where those credentials are absent, say so and hand the two
   commands to the operator — the PR is then **open, checks not posted**, never
   check-complete. In a repo whose checks come from its own CI workflows,
   `gh pr checks <n>` names what is still running, and the PR is done when those
   are green — never read absence from merged history. Watch them **after**
   `finishedAt` is stamped and the retro is in its tab, not before: the check
   wait runs beside the retro and never delays the spawn. Write the body with the
   `pr` skill (see *PR body*).
7. **Post-merge cleanup.** The sequence is
   [run-mode.md](../orchestrate-core/run-mode.md)'s *After the operator
   merges* — `gated` runs it when the operator says the PR merged, `land` and
   `unattended` when the same reply answers the verification ask. Herdr's part:
   release every tab this coordinator created, including the worker tabs kept
   open through the run — the operator's own panes are theirs — and stamp
   `pr.mergedAt` and `postMerge` in that turn. A ledger closed with
   `postMerge.pending` ("operator merge of PR …") and `mergedAt: null` is a run
   whose step 7 has not happened yet — nobody should read that as a finished one.

## Flow B — one worktree and PR per item

Trigger: the manifest's flow is `B`. Shape `B` is
[`threads.md#flow-shapes`](../orchestrate-core/threads.md#flow-shapes); this
runtime's worktree mechanics are below.

```sh
git fetch origin <target>
herdr worktree create --cwd <repo-root> --branch "<feature-slug>/<slug>" \
  --base "origin/<target>" --label "<id> · <short title>" --no-focus
```

The reply carries `.result.workspace.workspace_id`, `.result.root_pane.pane_id`
and `.result.worktree.path` — record all three in the ledger's item, start the
worker in that root pane (its cwd is already the worktree), and place its review
tab in the same workspace (`tab create --workspace <item-ws> --cwd <wt-path>`).

Then run Flow A steps 2–7 with these deltas:

- **Step 2** — no file-overlap gating. An item stays `todo` until its blockers'
  PRs are merged, not merely `done`.
- **Steps 4–5** — the review and the ponytail pass read that item's branch
  worktree, and the ponytail pass runs per branch on that branch's uncommitted
  diff.
- **Step 6** — one PR per item, from that item's worktree. The commit gate is
  [run-mode.md](../orchestrate-core/run-mode.md): `gated` asks, `land` and
  `unattended` do not. Commit the branch from the coordinator with
  `git -C <wt-path>`, and in `land` and `unattended` open it a draft titled
  `[AI-DRAFT] <the item's subject>` (`--draft --title …`). Same body: the `pr`
  skill (see *PR body*).
- **Merge the wave, then dispatch the next.** Only `gated` merges each ready
  PR, with the `gh pr merge --match-head-commit` command in run-mode.md.
  `land` and `unattended` do not merge and do not dispatch the next wave. After a
  `gated` wave is merged, fetch and create worktrees for the items it unblocked. Retire each
  item's worktree once its PR is merged and its agents are gone:
  `herdr worktree remove --workspace <item-ws>`. Do **not** pass `--force`: a
  dirty worktree refusing to be removed is the signal that work is still in it,
  and that gets surfaced, not discarded. `--trust-repository` is only for a
  repository the operator has already verified, never a retry for a failed
  worktree command.

## Cross-repo runs

The shapes are [`threads.md#flow-shapes`](../orchestrate-core/threads.md#flow-shapes).
This runtime's delta: each item gets its own worktree, and an out-of-repo item's
touched files are copied to `$RUNDIR/snapshots/post-<slug>-r<n>/` for its
completeness review.

## Models

Role policy — the roles, the override syntax, and what a failed model does — is
[`threads.md`](../orchestrate-core/threads.md#models). This adapter owns the
Herdr ids and how they are passed and checked.

Role defaults, passed on `herdr agent start` as pi flags after `--`:

| Role | Start flag | Default |
|---|---|---|
| worker | *(none)* | pi's configured default (`~/.pi/agent/settings.json`) |
| code-review | `-- --model openrouter/z-ai/glm-5.3` | GLM 5.3 |
| ponytail | `-- --model openrouter/anthropic/claude-sonnet-5` | Sonnet 5 |

Neither gate may inherit pi's configured default: it is the worker model, so a
role with no flag is the author reviewing itself. See *Models* in
[`threads.md`](../orchestrate-core/threads.md#models) for the family rule.

Check every named pattern against `pi --list-models` before dispatching, and
record the effective choice in the ledger's `models` — `pi-default` when no flag
was passed.

**Write the receipt beside the request.** `models` is what the run asked for;
`served` is what the lane's own record named — the pi session transcript the
ledger already points at, whose assistant messages carry `provider` and `model`
— read when the role's first lane settles, and on a single lane when that lane
diverges from its role. A transcript naming no model, or several, leaves `served`
out, and a role with none reads as unverified
([threads.md](../orchestrate-core/threads.md#models)).

**The reviewer model follows the item's risk, not the role.** The table's reviewer
is the model for a **high-risk** item; a **mechanical** item — the same ones step 4
gives the short pass — is reviewed on the worker model instead. A review is
the longest single agent in a run and the run cannot close until the last one
settles, so the slowest model on a mechanical diff is wall clock and money spent on
nothing: 39 minutes and $2.76 for a CLEAN verdict on a 63-line diff, against 59
minutes for the 535-line high-risk one, in the run this line came from.

The call is not a private one: record it as the item's
`risk` in the ledger when the review is dispatched ([ledger.md](../orchestrate-core/ledger.md)),
because a retro that finds no `risk` cannot tell this rule applied from a flag
someone forgot.

## Review loops

What a review is, when it ends, how deep it goes and how a fix round is capped:
[../orchestrate-core/review-contract.md](../orchestrate-core/review-contract.md).
A worker's `DONE` is a claim, not proof. This section carries only the Herdr
mechanics.

- Every code-changing item gets a separate fresh-eyes review agent; a worker or
  the coordinator reviewing its own work does not count. When the coordinator
  judges findings it reads the frozen diff or a bounded path only — never an
  unbounded scan; an unlocatable criterion is reported unverifiable.
- **The brief carries the finding contract and the run's classes.** Every finding
  is asked for as `<file>:<line> · <class> · <what breaks> · "<the quoted code>"`,
  and the brief lists every `<class>` already in the run's `classFixes` so a
  finding of a known class reuses the recorded slug instead of coining a second
  one. A claim with no quotation is a nit: it opens no round and goes to the
  operator with the rest ([review-contract.md](../orchestrate-core/review-contract.md)).
- **A class the run has already diagnosed is not diagnosed again.** When a
  finding's `<class>` matches a `classFixes` entry, reuse that entry's `brief`
  verbatim, append the item id to its `items`, and run **one** repair round for
  the class in the worktree the affected items share (a `FIX · <class>` agent, or
  the first affected item's live worker) — recording that lane's `id` and
  `session` on each affected item's `fixes` round, which both retros price once.
  Items that share no worktree (Flow B) still share the brief, each running its
  own repair from it. Each affected item still gets its own re-review of the
  repair's delta: a verdict is never shared.
- Findings loop back to the **same worker** while its pane is live: re-prompt
  that agent with `prompts/fix-<slug>-f<n>.txt`. If the pane is gone, start a
  fresh `fix-<slug>-f<n>` agent in the item's worktree. A ponytail fix runs as a
  fresh worker titled `FIX · <one-line>` on the worker model. A 4th findings
  round is never started: the item is `blocked` with `cause.code: cap_exhausted`,
  its findings are surfaced, and the frontier keeps moving.
- **A re-review waits on the artifact, not on the fix's word.** Before spawning
  `review-<slug>-r<n+1>`, re-freeze to `diffs/<slug>-r<n+1>.diff` (or
  `snapshots/post-<slug>-r<n+1>/`) and compare it with **every freeze this item has
  read** — `cmp -s` against each `diffs/<slug>-r*.diff`, `diff -rq` against each
  snapshot. Identical to the one the previous pass read is `cause.code:
  artifact_unchanged`; identical to an **earlier** one is `cause.code:
  nonconvergent`, because the rounds are bouncing the diff. Either way the item
  stops, its findings are surfaced, and the frontier keeps moving. Changed bytes
  are the delta the re-review is scoped to, and the brief names it.
- **`REFUTED:` and a returning finding are stops, not rounds.** A fix round that
  returns `REFUTED:` with the disproving code quoted adds no re-review: write
  `refutation: {finding, evidence}` on that round's `fixes` entry and block the
  item with `cause.code: finding_refuted`. The same finding — same file, line and
  normalized title — in two consecutive findings rounds is `cause.code:
  nonconvergent` before a third is spawned. Both rules are
  [../orchestrate-core/review-contract.md](../orchestrate-core/review-contract.md);
  what this skill owes is the write and the stop.
- **Delete the worker's report before a fix round starts:**
  `rm -f "$RUNDIR/reports/item-<slug>.md"`, whether the round re-prompts the same
  worker or starts a fresh `fix-<slug>-f<n>` agent in its worktree. That path is
  reused across rounds, so a fix round that settles without writing leaves the
  previous round's report on disk — and the settle rule reads that file as this
  round's evidence. With it removed, a silent fix round has no report at all and
  the stalled-turn rule catches it.
- A non-verdict completion is re-prompted once in the same reviewer — its tab is
  still open — and adds no `reviews` entry.
- Append a `reviews` entry for every completed pass; the findings rounds are the
  review rounds that opened a `fixes` entry, and the cap reads off those. A
  ponytail fix round is named under `ponytail`, never in `items[].fixes` — the
  `fixes` array is review-scoped, and the projection reads an extra entry there
  as an in-flight review round.

## Ticket write-back

Dispatch on the manifest's `tracker:` value:

- `tracker: scratch <feature>` (work list from `.scratch/<feature>/issues/NN-*.md`)
  — keep those ticket files in sync with the ledger as items settle; see
  [TICKET-WRITE-BACK.md](../orchestrate-core/TICKET-WRITE-BACK.md).
- `tracker: github <owner/repo>#<parent>` — claim at dispatch (assignee, drop
  `ready-for-agent` only); item settlement is comments only, never a close, never any
  other label. The parent spec is closed by the run after the merge, not here
  ([run-mode.md](../orchestrate-core/run-mode.md), *After the operator merges*,
  step 5). Post every comment body by file (`gh issue comment <n> --body-file`),
  never an inline heredoc — a quoting error merges one item's body into another
  item's comment, and the wrong text is visible until someone patches it. See
  [TICKET-WRITE-BACK-GITHUB.md](../orchestrate-core/TICKET-WRITE-BACK-GITHUB.md).

The coordinator owns these writes and writes to a ticket only once its item has
settled — a worker's `DONE` alone does not settle an item.

## PR body

[`threads.md#pr-body`](../orchestrate-core/threads.md#pr-body) owns it — read
and follow the `pr` skill there. The body is identical in both runtimes.
