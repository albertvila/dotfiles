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

`$RUNDIR` is the run directory `<worktree>/.herdr-runs/<feature>/`. Entered from
`/orchestrate-herdr-plan` it is already set; entered directly, resolve it as the
most recent `.herdr-runs/*/manifest.txt` in this worktree and say which run was
picked.

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

`herdr agent wait` fires on a **transition**, not on the current state, so a
worker that settled while nobody was looking is invisible to it. Check first,
then wait — and treat every wait timeout as a checkpoint, not a failure:

```sh
# settle <agent-name>: loop until the turn is over, or until the agent is unreadable
while :; do
  st=$(herdr agent get "<name>" 2>/dev/null | jq -r '.result.agent.agent_status // empty')
  case "$st" in idle|done|blocked|"") break;; esac   # "" = no agent left: inspect, never assume
  herdr agent wait "<name>" --until idle --until done --until blocked --timeout 600000 \
    > "$RUNDIR/logs/wait-<name>.json" 2>&1 || true
done
```

**A finished pi turn reports `idle` or `done` — treat both alike.** Herdr returns
`agent_status: "done"` for a pi agent whose turn ended (14 of 14 wait logs in the
run that produced this line) and `idle` for one caught between turns; a
coordinator that expected only `idle` would read every settle as an agent exit.
Break on `idle`, `done`, `blocked` and the empty status alike, and include both
`idle` and `done` in the `--until` list. Whichever arrives is a settle
**candidate**, not proof: the agent's report file on disk is what settles it.

A wave dispatches in parallel and settles in parallel — one shell block each:

```sh
for id in <id1> <id2>; do
  herdr agent prompt "item-$id" "$(cat "$RUNDIR/prompts/item-$id.txt")" \
    > "$RUNDIR/logs/prompt-item-$id.json" 2>&1 &
done
wait                       # prompts are in their panes; the status each leaves is read next
# settle-wait the wave with the loop above in parallel; freeze each diff as it settles
for id in <id1> <id2>; do
  ( while :; do
      st=$(herdr agent get "item-$id" 2>/dev/null | jq -r '.result.agent.agent_status // empty')
      case "$st" in idle|done|blocked|"") break;; esac
      herdr agent wait "item-$id" --until idle --until done --until blocked --timeout 600000 >/dev/null 2>&1 || true
    done ) &
done
wait
```

**A prompt's exit code is not a delivery report.** `--wait --timeout <ms>` says
whether the agent's status became readable inside that window and nothing more:
`{"error":{"code":"timeout"}}` from a prompt whose agent is working is the normal
outcome of a short window, not a lost prompt. Never re-prompt on that code alone —
`herdr agent get` and `herdr agent read` say whether the text arrived, and a
genuinely unprompted agent is re-prompted only after that read. The log is for the
case where the prompt never landed at all.

**Wake on the first settle, not the last.** A block that ends in `wait` hands back
control only when the slowest agent in it is done, so a worker that settled two
minutes in keeps its review waiting for as long as its sibling runs — the run pays
for the slowest agent twice, once in work and once in the wait. Settle each agent
in its own bounded call, or wake on the first (`wait -n`), and do its work the
moment it settles: freeze that diff, dispatch that review, then go back to waiting
for the rest. Keep the settle loop's budget short and *below* the timeout that
wraps the call — a 1500s budget inside a 1600s bash timeout reports neither, and
the turn is gone for 26 minutes.

**A stalled turn is not a settle.** `idle` — or a `wait` timeout — with no report
file on disk means the turn died mid-work, not that the agent finished: read the
pane (`herdr agent read "<name>" --source recent-unwrapped --lines 60`) and, if
the turn ended without a report, re-prompt **that same agent** once with
`continue` — never the whole prompt again. A second stall is a blocker: record
it with `cause.code: turn_stalled`, notify the operator, and keep the rest of the
frontier moving. A turn that ended mid-generation is invisible in every status
field the run reads, so this
check is the only thing that catches it.

**Reading and releasing.** The report file is the truth; the scrollback tail is
the summary: `head -1` the report for a verdict, then
`herdr agent read "<name>" --source recent-unwrapped --lines 60` for the final
message. A **review, fix or ponytail** tab is released —
`herdr tab close "$tab"` — once its settlement is recorded; that recording is
what makes the close safe. A **worker** tab is retained until the run's cleanup,
so a fix round re-prompts the same agent instead of respawning it. Release only
tabs this coordinator created, and never close one before its verdict or report
is on disk. Retention is the other safe choice, and it is *required* while a loop
can still re-open the tab — a reviewer whose completion carried no verdict, a turn
that stalled and needs `continue`, a ponytail pass awaiting a fix round: keep that
tab until the loop is closed, then release it.

**Respawn into the same pane.** When an agent has exited and its item needs
another turn, restart it in the pane recorded in the ledger — the tab keeps its
label and position, and the freed name is reused:

```sh
herdr agent start "item-<slug>" --kind pi --pane "<recorded pane>" \
  > "$RUNDIR/logs/start-item-<slug>-f<n>.json"
```

**Blocked dialog.** `blocked` is a user-facing gate. Inspect `agent get` and
`agent read`, then: if the approved manifest answers the question exactly, answer
it in the pane (`herdr pane send-text "<pane>" "<answer>"`, then
`herdr pane send-keys "<pane>" Enter`) and confirm the worker resumes working;
otherwise record the blocker with `cause.code: worker_blocked`, notify the
operator, and end the turn. The
coordinator never guesses an answer and never leaves a blocked worker unwatched.

## Prompt contracts

The coordinator writes every prompt to `$RUNDIR/prompts/<name>.txt` and passes it
by quoted substitution, so a long multi-line prompt never becomes a
shell-quoting bug. Every prompt is self-contained: target, change, constraints,
ownership, observable acceptance — and the report contract. **Paths are spelled
out absolutely in the prompt file**: a worker tab is a fresh shell with no
`$RUNDIR` in its environment. Work orders never restate lifecycle mechanics
(start flags, wait loops); those are this skill's. Every prompt also quotes the
item's `acceptance` and `out-of-scope` lines verbatim from the manifest: those
are the criteria a review checks, and a reviewer never re-derives them from the
ticket. The review brief also quotes the worker's own `HARDEST:`, `REJECTED:`
and `UNSURE:` lines from its report; where the report omitted them, the brief
says so rather than passing silence off as certainty.

**Worker** (`item-<slug>.txt`) — ends with:

> You are in this run's worktree: leave your changes uncommitted and do
> NOT commit or push. Touch nothing outside the file scope above. Never wait for
> human input — if something blocks you, stop and report. Run the item's tests
> and name the command in your report. Write your report to
> `$RUNDIR/reports/item-<slug>.md`: what changed, the acceptance evidence, the
> exact test command and result, then three one-line answers — `HARDEST:` the
> hardest decision you made, `REJECTED:` the alternatives you rejected and why,
> `UNSURE:` what you are least confident about. Your final message is three
> lines — `DONE` or `BLOCKED`, one line of what changed, one line of what
> remains.

**Review** (`review-<slug>-r<n>.txt`) — ends with:

> Fresh eyes: review the frozen diff at `$RUNDIR/diffs/<slug>-r<n>.diff`, not the live
> worktree — another worker may already be changing those files; read worktree
> files for surrounding context only. Report findings against the item's
> acceptance criteria and within its out-of-scope line, both quoted above, and
> read the worker's `HARDEST:`/`REJECTED:`/`UNSURE:` lines quoted above as a lead
> to check against the frozen diff, never as a verdict. Do not edit files. A
> test proved non-vacuous by reverting
> the change is reverted in a **scratch copy** — a `/tmp` copy, or
> `git worktree add --detach` — never in this worktree, which holds other items'
> uncommitted work; a gate you run in this worktree measures whatever else is
> uncommitted here, so name the revision your evidence is about. Read only the dependency roots you
> need; never run unbounded scans (no `find /`, no recursive grep over `/`). A
> criterion needing source you cannot locate is reported **unverifiable**. Write
> your full report to `$RUNDIR/reports/review-<slug>-r<n>.md` whose FIRST line is
> `VERDICT CLEAN` or `VERDICT FINDINGS`. Your final message must be the complete
> report, starting with that verdict line.

**Ponytail** (`ponytail-<n>.txt`) — ends with:

> Run `/ponytail-review` on the full uncommitted diff (`git diff HEAD` plus
> `git status --porcelain` so new files are not invisible). Report over-
> engineering findings only; anything else you notice goes in the same report
> labelled out of scope. Do not edit files. Write your report to
> `$RUNDIR/reports/ponytail-<n>.md` whose FIRST line is `VERDICT CLEAN` or
> `VERDICT FINDINGS`; your final message starts with that verdict line.

**Fix** (`fix-<slug>-f<n>.txt`) — the findings verbatim, the item's file scope,
and the worker contract above. A fix round to a live worker re-prompts its own
agent; a fresh `fix-<slug>-f<n>` agent starts only when the worker's pane is gone.

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

The ledger's shape is [`ledger.md`](../orchestrate-core/ledger.md) — the same
record BB writes. Herdr fills it like this:

- `runtime: "herdr"`, plus `feature`, `project`, `rundir`, `tracker`, `flow`,
  `mode`, `startedAt`, `models`, `ciBaseline`, `validationBaseline`, `gates`
- `executors: [{ "id": "coordinator", "pane": "$HERDR_PANE_ID", "session": … }]`
  — `executors[0]` is the run's identity. Its `endedAt` is stamped in the same
  write as the verification ask: a coordinator row left `null` has no upper
  bound, so everything the turn does after `finishedAt` lands in the retro's
  covered time as if it were run work.
- `retro: { "id": "retro-<feature-slug>", "session": …, "tab": … }`, written the
  moment the spawn returns its session — a retro with no row is an agent the
  record cannot name and the retro prices nowhere.
- each item's `worker: { "id": "item-<slug>", "pane": …, "tab": …, "session": … }`,
  and in Flow B a `worktree: { workspace, path, branch }`
- every `reviews`/`fixes`/`ponytail` entry carries `id` (the agent name),
  `session`, `pass`, and — for a review or ponytail pass — `verdict`

Extensions Herdr adds, in the contract's shape: `pr` {number, url, mergedAt,
mergeCommit, base}, `prs` [{number, url, head, commit, mergedAt, kind}],
`postMerge` {branchDeleted, tabsReleased, tabsKept, pending}, `reopenRounds`
[{item, at, why, agent, landedAs}].

Record the coordinator as `executors[0]` at the start. The findings-round cap
reads off the review rounds that opened a `fixes` entry, per the review contract. The `done` rule and the reopen rule are
[`threads.md#the-ledger`](../orchestrate-core/threads.md#the-ledger). `ponytail` is a list of passes, appended in order like `reviews` —
a two-pass ponytail (`FINDINGS` → fix round → re-check) keeps both, at `pass: 1`
and `pass: 2`, because only the last one is the verdict and only the first one
holds the findings that opened the fix round. Every pass keeps its `id` and
`session`: a rewrite that drops the session prices the whole lane at
zero in the retro. A convenience `verdict`/`report` may name the last pass; the
array is the record. `items[].fixes` counts **review-driven** rounds only: a
ponytail fix round is recorded under `ponytail` (with its id), because the
projection pairs each `fixes` entry with a review round and reads an unmatched
one as a round still in flight — a settled run then reports `E150`.
**An item the run stops on is typed** — the invariant and the codes are
[`threads.md#the-ledger`](../orchestrate-core/threads.md#the-ledger) and
[cause-contract.md](../orchestrate-core/cause-contract.md). The projection below
exits non-zero on an invented code, a cause on any other status, or a stopped
item with no cause; `cap_exhausted`, `spec_conflict`, `worker_blocked` and
`turn_stalled` are the ones a normal run reaches.

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
The projection below enforces the half of that the ledger can prove on its own
and exits non-zero on it; containment in the agent's own session window is
asserted by the retro, which is the only reader holding both sides.

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

### The pane view — derived, never hand-written

The operator watches the run in a dagr pane. `dagr-run.json` is a **projection of
the ledger** for that pane, and the projection is the coordinator's job: re-render
it after every ledger write (the pane reloads on mtime, so the view stays live).

```sh
python3 <this skill's dir>/scripts/ledger-to-run.py "$RUNDIR" --check   # writes $RUNDIR/dagr-run.json
```

The script ships with **this skill**, not with the worktree: an absolute path
under `~/.agents/skills/orchestrate-herdr-threads/scripts/` (its `readlink -f`
target) is the one that exists, and a run that looks for it in the repo will
wrongly conclude the projection is unavailable and go without its pane view.

`--check` runs `dagr check` on the result; **0 errors** every time. Warnings are
the honest state of a live run — W208 (a working attempt with no liveness facts)
until the item settles, W203 if the ledger is missing attempt timestamps — and
only a settled run (`finishedAt` set) is expected to be clean under `--strict`.

Open the pane beside your own work, once, when the run starts. `dagr-run.json`
is passed explicitly because the pane's own discovery looks for `run.json`, which
is the *retro's* metrics record name:

```sh
herdr plugin pane open --plugin herdr-dagr --entrypoint dagr --placement split \
  --direction right --target-pane "$HERDR_PANE_ID" --cwd "$RUNDIR" \
  --env "DAGR_RUN=$RUNDIR/dagr-run.json" --focus
```

Never hand-edit `dagr-run.json`, and never treat it as the record: the ledger
holds what resume and the retro need (sessions, worktrees, PR urls, tickets, the
model roster) and stays the source of truth. The projection script owns the
contract's traps, which is why they are not restated per write: a review that
returns FINDINGS settles `done` — the *reviewed* attempt is what goes `rejected`;
a fix round is a new attempt whose `cause.sent_back` names the review attempt; an
item blocked by a dependency renders `waits I01` rather than claiming the
operator must act; and every terminal outcome is `reported`, never `verified`,
because nothing in this flow mechanically checks the work.

**The projection reads the shapes this file writes — and checks them.** The
`ponytail` lane is a **list of passes** here and in the retro's script; a reader
that treats it as one mapping takes the whole view down with it (and hides a
`dagr` error it would otherwise have reported). A ledger-shape change lands in
both scripts in the same commit. The script also asserts what the ledger can
prove on its own and exits non-zero when it doesn't hold: an interval that runs
backwards, a gate approved before it was requested, a terminal `finishedAt`
standing over an item or ponytail pass that never settled, and a stopped item
with no `cause` or a code outside the contract. That is where "stamp
the times honestly" gets its teeth — it runs after every write, so the
coordinator sees the mistake while it still knows what it meant.

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
3. **Wait, then collect.** Settle every running agent (see *Waiting*), read its
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
   commit as the next sentence requires.
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
   wait runs beside the retro and never delays the spawn. The body carries the
   closing lines below.
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
  `git -C <wt-path>`.
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
| ponytail | *(none)* | pi's configured default |

Check every named pattern against `pi --list-models` before dispatching, and
record the effective choice in the ledger's `models` — `pi-default` when no flag
was passed.

**The reviewer model follows the item's risk, not the role.** The table's reviewer
is the model for a **high-risk** item; a **mechanical** item — the same ones step 4
gives the short pass — is reviewed on the worker model instead. A review is
the longest single agent in a run and the run cannot close until the last one
settles, so the slowest model on a mechanical diff is wall clock and money spent on
nothing: 39 minutes and $2.76 for a CLEAN verdict on a 63-line diff, against 59
minutes for the 535-line high-risk one, in the run this line came from.

## Review loops

What a review is, when it ends, how deep it goes and how a fix round is capped:
[../orchestrate-core/review-contract.md](../orchestrate-core/review-contract.md).
A worker's `DONE` is a claim, not proof. This section carries only the Herdr
mechanics.

- Every code-changing item gets a separate fresh-eyes review agent; a worker or
  the coordinator reviewing its own work does not count. When the coordinator
  judges findings it reads the frozen diff or a bounded path only — never an
  unbounded scan; an unlocatable criterion is reported unverifiable.
- Findings loop back to the **same worker** while its pane is live: re-prompt
  that agent with `prompts/fix-<slug>-f<n>.txt`. If the pane is gone, start a
  fresh `fix-<slug>-f<n>` agent in the item's worktree. A ponytail fix runs as a
  fresh worker titled `FIX · <one-line>` on the worker model. A 4th findings
  round is never started: the item is `blocked` with `cause.code: cap_exhausted`,
  its findings are surfaced, and the frontier keeps moving.
- **A re-review waits on the artifact, not on the fix's word.** Before spawning
  `review-<slug>-r<n+1>`, re-freeze to `diffs/<slug>-r<n+1>.diff` (or
  `snapshots/post-<slug>-r<n+1>/`) and compare it with the diff the previous pass
  read — `cmp -s` for a diff, `diff -rq` for a snapshot. Identical bytes are not a
  new round: the item is `blocked` with `cause.code: artifact_unchanged`, its
  findings are surfaced, and the frontier keeps moving. Changed bytes are the delta
  the re-review is scoped to, and the brief names it.
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
  `ready-for-agent` only); settlement is comments only, never a close, never any
  other label. Post every comment body by file (`gh issue comment <n> --body-file`),
  never an inline heredoc — a quoting error merges one item's body into another
  item's comment, and the wrong text is visible until someone patches it. See
  [TICKET-WRITE-BACK-GITHUB.md](../orchestrate-core/TICKET-WRITE-BACK-GITHUB.md).

The coordinator owns these writes and writes to a ticket only once its item has
settled — a worker's `DONE` alone does not settle an item.

## PR body

[`threads.md#pr-body`](../orchestrate-core/threads.md#pr-body) owns it — the
intent block and the closing lines are identical in both runtimes.

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
  On resume, the first move is the *Waiting* stalled-turn recovery — `agent read`
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
