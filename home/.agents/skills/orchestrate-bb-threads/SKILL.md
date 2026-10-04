---
name: orchestrate-bb-threads
description: "Execute an approved orchestration plan as the manager thread: dispatch the workers, keep the ledger, route reviews, land the run. Use when the user says '/orchestrate-bb-threads', or the prompt carries a manifest from /orchestrate-bb-plan."
---

# Orchestrate BB Threads

Execute an approved plan. This thread is the manager: it dispatches one visible
child thread per item, keeps the ledger, routes review findings, and lands the
run. It does not plan.

**A manifest in the prompt is the approved plan.** The manifest carries the
items with their file scopes and blockers, the flow, the waves, the `mode`
line, and any run notes or model overrides (see `/orchestrate-bb-plan`, *The manifest*). Start
from it immediately — never re-derive the graph and never re-ask what was
already approved. With no manifest, do not derive one: say the plan is missing
and point the operator at `/orchestrate-bb-plan`.

Read [run-mode.md](run-mode.md) before the first spawn. It owns `mode`, the CI
baseline, the validation exit code, Flow B bases, and the merge command. A
sentence in this file that disagrees with it is wrong.

**Read this file and dispatch before touching anything.** A manifest is data,
not an implementation assignment: a plan thread can dispatch a bare manifest
with no instruction to run this skill, and this skill still applies. Your first
turn writes `$BB_THREAD_STORAGE/orchestration.json` and spawns wave 1 **before
you open any item's file to change it**. The manager never implements items
itself — a draft you author has no worker thread, no reviewer, and no ledger
entry it can honestly claim.

## Spawn flags

Every spawn in this skill passes `--parent-self --json --permission-mode
auto` and `--project "$BB_PROJECT_ID"`. On the pi provider `auto` is rejected
("Provider pi only supports full permission mode") — pass `full` there. Without
`--project`, spawn fails with `missing_required` even inside that project.

## Models

Role defaults, passed via `--model` when spawning:

| Role        | Default model (`--model` id)           |
|-------------|----------------------------------------|
| worker      | `openrouter/deepseek/deepseek-v4.1-flash` |
| code-review | `openrouter/z-ai/glm-5.3`                     |
| ponytail    | `openrouter/deepseek/deepseek-v4.1-flash` |

These are live catalog ids, not display names. Use the openrouter route only,
never opencode.

Check existence before spawning with a non-truncating listing:
`bb provider models pi | grep -F 'openrouter/<vendor>/<model>'`. The ids are
on the pi catalog; `bb provider models openrouter` returns no models. Never
read absence from a `head`-piped catalog listing — the id can sit past the cut.
An id present in the catalog can still be blocked by an OpenRouter workspace
guardrail; only a turn reveals that, so "absent from the catalog" and
"blocked at runtime" are different failures with the same stop-and-ask ending.

Per-run override syntax: "workers on X, reviewers on Y"; ponytail follows the
worker model unless the line also names one ("ponytail on Z"). The operator
sets an override at plan time and the manifest carries it — the manager keeps
the syntax and the spawn-time decisions, not the choice.

**A model that does not work stops the run.** That covers every failure: the
id is missing from the catalog, the spawn fails, or the first turn dies on a
provider routing error (e.g. OpenRouter's allowed-providers rejecting every
upstream serving the model — the spawn succeeds, the turn dies with a 404).
Stop, tell the user which model failed and how, and ask which model to use
instead.

## Review loops

What a review is, when it ends, how deep it goes and how a fix round is capped:
[review-contract.md](review-contract.md). A worker's DONE is a claim, not proof.
This section carries only the BB mechanics.

- The review thread is always a **spawned child thread**. An `Agent`/subagent
  call inside the authoring thread is not a review: it is invisible to the run
  record, its tokens are unpriced, and the actor that judged the findings is the
  actor that wrote the diff. The manager never substitutes its own reading of a
  diff for the review thread; when it judges findings it reads the frozen diff
  or a bounded path only, and an unlocatable criterion is unverifiable.
- Findings loop back to the **same worker**: queue them as a follow-up message
  (`bb thread queue create <id> "<findings>"`, then `bb thread queue send`); if
  the thread is dead, respawn the item's worker with the findings in the prompt.
  **Flow B respawn:** when the worker's thread is dead, respawn with
  `--environment "<worker-env-id>"` (the item's recorded environment from
  the ledger), **never** `--new-environment worktree` — a fresh worktree
  would orphan the item's branch and desync the ledger's `envId`.
- A ponytail fix runs as a **new** child thread on the worker model, titled
  `FIX · <finding>` — a `PONYTAIL …` title is reserved for a ponytail pass.
- Record `reviewCount` for every completed pass and `fixRounds` for the findings
  rounds; read the cap off `fixRounds`. A non-verdict completion is re-prompted
  once in the same thread and does not increment `reviewCount`.

## Flow A — single shared PR

All workers operate in the manager's worktree (`--environment
"$BB_ENVIRONMENT_ID"` at spawn — nothing to state in the prompt). Workers
leave their changes **uncommitted** and never commit or push; the manager
accumulates the combined diff and makes exactly one commit and one PR at the
end. Workers never talk to each other — all coordination goes through the
manager.

**Your first turn dispatches.** For `tracker: github <owner/repo>#<parent>`,
claim the parent and every item issue before spawning. Not an excluded issue:

```sh
gh issue edit <n> --repo <owner/repo> --add-assignee @me
gh issue edit <n> --repo <owner/repo> --remove-label ready-for-agent
```

`@me` is the authenticated `gh` user. Nothing replaces the label. Do not close,
and do not add or remove any other label. A scratch tracker has no issue to
claim. Then write `$BB_THREAD_STORAGE/orchestration.json` and spawn the wave-1
workers before you read any item's code. You never open an item's files to
change them: the manager dispatches, waits, routes findings and unblocks (see
*Rules*), and an item implemented here has no worker thread, no ledger entry
and no reviewer it can honestly claim. A single-item manifest whose notes list
the exact files to touch is context for the worker you are about to spawn — it
is not your own scope.

**Turn 1 is a dispatch turn, not a coding turn — and it is checkable.** Before
the manager opens any item file to change it, `$BB_THREAD_STORAGE/orchestration.json`
must exist and wave 1 must be spawned. If you have edited an item's file and
the ledger does not exist, dispatch has not happened: stop, write the ledger,
spawn the worker, and let it finish the item — do not finish it yourself. A
single-item manifest is the case this most often tempts, and it is not an
exception. A run whose record has one thread, no children and no ledger is a
manager that never dispatched, whatever it shipped.

1. **Spawn every ready item's worker**, each to its own visible child thread.
   Write the prompt to `$BB_THREAD_STORAGE/prompt-<item-id>.txt` and pass it by
   substitution — a long multi-line prompt inlined in the command is a
   shell-quoting bug waiting for a `'`:

   ```sh
   bb thread spawn --parent-self \
     --project "$BB_PROJECT_ID" \
     --environment "$BB_ENVIRONMENT_ID" \
     --model "<worker-model>" \
     --title "<item-id> · <short title>" \
     --permission-mode auto --json \
     --prompt "$(cat "$BB_THREAD_STORAGE/prompt-<item-id>.txt")"
   ```

   The file holds: `Work this item only: <self-contained instructions>. The
   instructions carry the item's acceptance line and its out-of-scope line,
   verbatim from the manifest, alongside the ticket's spec context — the bar is
   the manifest's, not the ticket's. You are in the manager's shared worktree —
   leave your changes uncommitted and do NOT commit or push. When done, your
   final message must state DONE or BLOCKED, give a 3-line summary of what
   changed / what blocks you, then three one-line answers — `HARDEST:` the
   hardest decision you made, `REJECTED:` the alternatives you rejected and why,
   `UNSURE:` what you are least confident about. Without them a worker that is
   unsure of a call reads exactly like one that is certain, so they are not
   optional.`

   Record each returned thread id in the ledger.

2. **Parallel only on disjoint files; reviews overlap with the next
   worker.** All workers share one worktree, so an item's worker may only
   run concurrently with workers whose files it does not touch. Judge
   overlap from the item scopes plus what already changed in the worktree
   (`git status`, files touched by running workers). Disjoint files → spawn
   together. Overlapping files → serialize the **workers**, but never the
   review lane: dispatch worker N+1 the moment worker N reports DONE and its
   diff is frozen (step 4), and let review N run concurrently. If
   review N returns findings, let the running worker finish, then run N's
   fix round and re-review before dispatching anything new (the fix touches
   the same files the next worker will build on).

3. **Wait, then collect.** For each running child:

   ```sh
   bb thread wait <id> --status idle --timeout 600 --json
   bb thread output <id>
   ```

   The command after a successful spawn is `bb thread wait`, in bounded
   slices. Stay on the wait until it matches idle — no `sleep`. A wait that
   returns before idle is not a failure: check `bb thread show <id> --json`.
   If the thread is still working, emit one short status line naming the
   running children and the longest-running one, then wait again — never let
   more than ~15 minutes of run time pass without a status line. A child whose
   log shows `provider/error` with `willRetry` is surfaced to the operator,
   not silently re-waited. Collect the final output and mark the item `done`
   or `blocked`/`failed` from the worker's DONE/BLOCKED report.

4. **Fresh-eyes review per item, from a frozen diff.** When a worker
   reports DONE, first freeze the item's diff so the review is immune to
   the next worker's churn:

   ```sh
   mkdir -p "$BB_THREAD_STORAGE/diffs"
   git diff HEAD -- <item files> > "$BB_THREAD_STORAGE/diffs/<item-id>.diff"
   ```

   If the workspace isn't git-tracked (e.g. a gitignored plugin dir), copy
   the item's files into `$BB_THREAD_STORAGE/snapshots/post-<item-id>/`
   instead and have the review diff against the previous item's snapshot.

   Then spawn a review thread — same shared environment, reviewer model,
   `--parent-self`. Scale its depth to the item's risk (see *Review loops*):
   a **high-risk** item — real state, logic, or contract surface (RPC
   schemas, fetch lifecycles, data scoping) — gets the full adversarial pass
   and keeps the whole-directory snapshot; a **mechanical** item — deletions,
   renames, rendering-only, docs, config — gets a short pass over a diff
   scoped to that item's files. Either way the review runs **in the review
   thread itself**: do not invoke the two-axis `/code-review` skill, whose
   mandatory Standards/Spec sub-agents report their tokens nowhere the run can
   see. Both shapes carry the same final-message contract:

   ```sh
   bb thread spawn --parent-self \
     --project "$BB_PROJECT_ID" \
     --environment "$BB_ENVIRONMENT_ID" \
     --model "<reviewer-model>" \
     --title "REVIEW <item-id> · <short title>" \
     --permission-mode auto --json \
     --prompt "$(cat "$BB_THREAD_STORAGE/prompt-review-<item-id>.txt")"
   ```

   The file holds: `Fresh-eyes code review. Review the frozen diff at
   $BB_THREAD_STORAGE/diffs/<item-id>.diff (item <item-id>: <item scope>;
   acceptance: <the item's acceptance line>; out-of-scope: <the item's
   out-of-scope line>; worker's own account: <the worker's HARDEST / REJECTED /
   UNSURE lines, verbatim from its final message>) against the acceptance stated
   above and this repo's documented standards — never a criterion re-derived
   from the ticket. The worker's account is a lead, not a verdict: check it
   against the frozen diff. Do NOT review the live worktree diff, another worker
   may
   already be changing those files; read worktree files only for surrounding
   context. Do not edit files, and do not spawn your own sub-agents to do any
   of it — report in this thread. This worktree is shared with other items'
   uncommitted work: do not run any command that writes to it — no formatters,
   no `databricks bundle validate` (it reformats YAML on disk), no `git
   checkout`, `git restore` or `git stash`. If you need resolved output or a
   test environment, copy the repo to a scratch dir under `/tmp` and work
   there. If a command you believed read-only turns out to mutate, report it;
   never restore with `git checkout --`, which resets to HEAD and discards the
   concurrent item's edits. The reviewer may read only the dependency
   roots it needs — the bb source checkout, sibling plugins, and the app
   bundle (e.g. under ~/personal_workspace and ~/.bb/plugins) — and must never
   run unbounded scans: never find /, never an unbounded grep -r. A criterion
   needing source you cannot locate is reported unverifiable, not searched
   for. Your FINAL message must be the complete report starting with VERDICT
   CLEAN or VERDICT FINDINGS, and findings must not be recorded as follow-ups
   instead of reported.`

   The reviewer may read only the dependency roots it needs — the bb source
   checkout, sibling plugins, and the app bundle (e.g. under
   `~/personal_workspace` and `~/.bb/plugins`) — and must never run unbounded
   scans: never `find /`, never an unbounded `grep -r`. A criterion needing
   source the reviewer cannot locate is reported **unverifiable**, not
   searched for.

   Findings go back to the same worker (see *Review loops*).

5. **One ponytail pass on the combined diff.** When every item's review is
   clean, spawn a ponytail thread on the full uncommitted diff:

   ```sh
   bb thread spawn --parent-self \
     --project "$BB_PROJECT_ID" \
     --environment "$BB_ENVIRONMENT_ID" \
     --model "<ponytail-model>" \
     --title "PONYTAIL · combined diff" \
     --permission-mode auto --json \
     --prompt "$(cat "$BB_THREAD_STORAGE/prompt-ponytail.txt")"
   ```

   The file holds: `Run /ponytail-review on the full uncommitted diff in this
   worktree (git diff HEAD). Report findings; do not edit files. Scope the
   report to over-engineering findings; anything else you notice goes in the
   same final message labelled out of scope. Your FINAL message must be the
   complete report starting with VERDICT CLEAN or VERDICT FINDINGS, and
   findings must not be recorded as follow-ups instead of reported.`

   **Scope.** The pass reports ponytail findings only. A note that names a
   defect — real behaviour, or a named acceptance criterion — is a finding and
   opens a fix round; a preference, a style choice, or an observation with no
   gate behind it stays out-of-band, reported to the operator in the run summary
   and never fixed in-run. The fix path and the cap are in *Review loops* and
   [review-contract.md](review-contract.md).

   In a multi-repo run (see *Cross-repo runs*) there is no combined diff to
   pass: run one ponytail pass per item diff, none optional — the last
   item's pass is not skippable, and a single combined pass is not a
   substitute.

6. **Commit + open one PR.** Do not open this gate until [run-mode.md](run-mode.md)
   validation exited 0. `land` and `unattended` skip the question: record the
   gate with `auto: true` and the conventional message, then create the run
   branch before pushing and commit. `gated`
   proposes the commit message and file list to the
   user (per repo conventions; detect the PR base branch), and waits for an
   explicit yes. Ask the gate with a pending interaction (`AskUserQuestion`),
   not a plain message — a message can be answered in any thread, and a yes
   relayed through the plan thread never reaches this run's record. If the
   answer arrives out of thread anyway, restate it in this thread before
   committing. On yes: create the run branch first, then commit, push that branch, open exactly one PR
   (`gh pr create`), then post the lm statuses from that repo root. `<base>`
   is the detected PR base:

   ```sh
   lm pr-test --base origin/<base>
   lm report-upload
   ```

   These two commands are for a repo whose PRs publish `lm-build/*` checks.
   Run the upload even when pr-test fails, so GitHub gets a failure instead of
   a missing check. `lm xpush` does not replace this on a first push: the
   pre-push hook's `pr-test --refresh-pr` no-ops until a PR exists, and a
   hook filecheck report is not the required `lm-build/filecheck` context.
   There the PR is done when its head has both `lm-build/filecheck` and
   `lm-build/projectCheck`; if `report-upload` fails for missing AWS or lm
   credentials, say so and hand the two commands to the operator — do not
   treat the PR as check-complete.

   In a repo whose checks come from its own CI workflows instead, there is
   nothing to upload and no `lm-build/*` context will ever appear: the PR is
   done when those workflow checks are green, and until then the run reports
   the PR as **open, checks running**, naming the context it is waiting on —
   never as check-complete. Read the contexts off the open PR before choosing
   (`gh pr checks <n>`); never read absence from the merged history.

   **When a post-PR step fails for an environmental reason** — credentials, a
   repo ruleset, a push permission, an account-level grant — collect every
   operator action it needs and ask once, not once per failure as it surfaces.
   An operator-directed change after the PR is open still runs through a worker
   thread, a frozen diff, and a fresh review before the commit.

   **A question is not a go.** When the operator's message is a question
   ("shouldn't we use X?" / "thoughts?"), answer it in that turn and wait. Do
   not dispatch or commit the change it implies until the operator answers with
   a direction; a question read as consent is a gate opened for them.

   The body carries the closing lines and the intent block below (see *PR body*).

7. **Post-merge cleanup.** `land` and `unattended` do not merge. `gated`
   waits until the user merges on GitHub. Then pull main,
   delete the merged branch, and post a final report (what shipped, per-item
   outcomes). Retiring the worktree is a hand-off, not a manager action:
   `bb environment delete` is refused while any thread in the environment is
   live, and the manager never archives threads (see *Rules*) — tell the
   user the environment id and let them archive the threads and retire it.

## Flow B — PR per item

Trigger: the manifest's flow is `B`. Every worker gets its
own worktree+**branch**. One PR per item. Same models
and review loops as the shared sections above (*Models*, *Review loops*).
Items with no `blockedBy` start together. An item with blockers stays `todo`
until those PRs are merged, then its worktree is created from the updated
target — see [run-mode.md](run-mode.md). Do not review it against a base that
lacks its blockers, and do not rebase it onto them afterwards.

1. **Spawn every item whose blockers are already merged — one worktree+branch each.** Drop
   `--environment "$BB_ENVIRONMENT_ID"` (sharing is the Flow A move) and pass
   `--new-environment worktree --base-branch origin/<target>` so the worktree
   starts at the target the blockers just landed on, not the project default
   from before this run. Fetch first. Record the returned thread id **and its environment id** in the
   ledger — review and ponytail threads reuse that environment to see the
   branch.

   ```sh
   git fetch origin <target>
   bb thread spawn --parent-self \
     --project "$BB_PROJECT_ID" \
     --new-environment worktree \
     --base-branch origin/<target> \
     --model "<worker-model>" \
     --title "<item-id> · <short title>" \
     --permission-mode auto --json \
     --prompt "<the Flow A step 1 worker prompt, unchanged>"
   ```

Then run Flow A steps 2–7 with these deltas:

- **Flow A step 2 — no file-overlap gating.** The disjoint-files rule and the
  review/worker overlap rule do not apply here. Keep every unblocked item
  moving at once. An item stays `todo` until its blockers' PRs are merged, not
  merely `done`.
- **Flow A steps 4–5 — review and ponytail in the item's environment.** Both
  spawn with `--environment "<worker-env-id>"` in place of
  `"$BB_ENVIRONMENT_ID"`, and the ponytail pass runs per branch on that
  branch's uncommitted diff.
- **Flow A step 6 — one PR per item.** The commit gate is [run-mode.md](run-mode.md):
  `gated` asks, `land` and `unattended` do not. Then commit the branch (`bb environment commit
  <env-id>`) and mark that environment's PR ready (`bb environment
  pull-request ready <env-id>` — each worktree environment owns its PR).
  After that PR is open, run Flow A step 6's lm status commands in that
  item's worktree, against the same detected base. Same done check.
  Its body carries the closing lines and the intent block below (see *PR body*).
  Merging items into one PR is the Flow A shape.
- **Merge the wave, then dispatch the next.** Only `gated` merges each ready
  PR, with the `gh pr merge --match-head-commit` command in
  [run-mode.md](run-mode.md). `land` and `unattended` do not merge and do not
  dispatch the next wave. Do not use `bb environment pull-request merge`. After a
  `gated` wave is merged, fetch and spawn the items it unblocked. Hand worktree retirement to the
  user: the manager never archives threads (see *Rules*), and
  `bb environment delete <env-id>` is refused while threads are live.

## Cross-repo runs

When the manifest names the cross-repo shape, the items span more than one
repo: there is no shared worktree and no single PR. Each item gets its own
per-item environment and its own per-repo gate, and no single PR closes the
run. Never treat this shape as `flow: "A"`.

**A tracker repo differing from the code repo is not that shape.** When the
tracker (and spec) lives in one repo but every item's code lands in a single
code repo — a BIT-spec → PLS-code move, say — the run is the Flow A shape:
one shared worktree in the **code repo**, one PR, one combined ponytail pass.
The only delta is the environment: workers, reviews and ponytail spawn against
the code repo's worktree, not `$BB_ENVIRONMENT_ID`; the tracker's issues are
still claimed and commented. A per-item ponytail pass is not required here —
the combined pass covers the single diff.

## The ledger

There is no Tasks panel for this — the manager IS the tracker. When the user
asks for a status view, regenerate the plan diagram with fresh status colors
(done / in review / todo) from the ledger. Keep
`$BB_THREAD_STORAGE/orchestration.json` mapping each item to
`{ threadId, envId, status, blockedBy, reviewCount, fixRounds, prUrl, reviewedHead }` — `threadId` is
always the item's **worker** thread, and the manager's own thread id never
appears in `items` (`envId`, the item's worktree environment, and `prUrl`
belong to Flow B) — plus the run's `mode`, `ciBaseline`, `validationBaseline`, `models`, `managerChain` and `finishedAt`. Statuses: `todo`, `running`, `done`, `failed`, `blocked`. `finishedAt` for `land` and `unattended` is set when the PRs are open, per [run-mode.md](run-mode.md).

`managerChain` lists the manager threads that held this run, oldest first. The
plan thread appends a successor when it replaces a manager whose context ran out
(see `/orchestrate-bb-plan`, *Wait for the run*). The first id is the run's
identity — where this ledger lives — and the retro walks the chain so a
successor's children are not lost from the numbers.

`reviewCount` counts every completed pass; `fixRounds` counts the findings
rounds, and the cap reads off `fixRounds` (see [review-contract.md](review-contract.md)). Write the ledger as you go, never batched at
settlement — `reviewCount` when the iteration completes, `models` and each
item's `status` as the run moves — the ledger must read true mid-run. Set
`reviewThreadId` when a round **completes**; if the spawned round is
interrupted or re-prompted, point it back at the last completed review thread.
`reviewThreadId` must never name a thread that produced no verdict, or the
ledger's primary review pointer reads as a pass that never happened.
Write an item `done` only when the ledger shows a completed review pass **and**
a completed ponytail pass for it, each backed by a child thread id — a `done`
with no review thread behind it is not settlement, however clean the diff
looks. A diff that changes after a `done` write reopens the item explicitly.
Before the step 6 commit gate, assert this from the ledger: an item that
cannot name its review thread and its ponytail thread has not settled. `finishedAt` is set once the run is done by the
definition below — every item terminal **and** the PR opened after the
approval gate — and it is an **ISO-8601 UTC timestamp**, not a marker, a
status word or a sentence: the run corpus reads this field as data. **A turn
that runs after `finishedAt` reopens the run: clear `finishedAt` and set it
again only when the run is terminal once more.** An operator-directed change
after the PR is open is exactly that case. A `finishedAt` earlier than the
manager's last event is ledger drift, and the retro reads it as such.

The run is done when every item carries a terminal status (`done`, `failed`,
or `blocked`), every `done` item's PR is open or merged and handed over, and
the blocked items are surfaced to the user.

## Ticket write-back

Dispatch on the manifest's `tracker:` value:

- `tracker: scratch` (work list from `.scratch/<feature>/issues/NN-*.md`) —
  the manager keeps those ticket files in sync with the ledger as items
  settle; see [TICKET-WRITE-BACK.md](TICKET-WRITE-BACK.md).
- `tracker: github <owner/repo>#<parent>` — claim at dispatch (assignee, drop
  `ready-for-agent` only); settlement is comments only, never a close, never
  any other label. A change after settlement that contradicts a posted comment
  (an operator-directed run-as switch, say) gets a correcting comment as part
  of the landing step — writeback is append-only, so the correction is a new
  comment, never an edit, and it is not optional. See
  [TICKET-WRITE-BACK-GITHUB.md](TICKET-WRITE-BACK-GITHUB.md).

The task record is orthogonal to the tracker value: when the manifest also
names a BB Task, the Task identity line adds the task record on top of the
real tracker above. That task is the run's parent record — comment the run
summary on it and set it to `in_review` the moment every item has settled, at
the commit+PR approval gate, not after the PR merges; the run waiting on a
human is exactly the state `in_review` exists for, and when the PR merges,
set the task to `done`.

The manager owns these writes. The plan thread makes one write of its own —
the Task's `in_progress` at spawn, only when a Task is in play — and writes
nothing after that.

## PR body

Every run's PR body opens with the run's **intent**, before any
tracker-specific closing lines: for each item the PR carries (Flow A: every
item; Flow B: its own), its title, its `acceptance` line and its `out-of-scope`
line from the manifest, verbatim, followed by that item's review verdict. The
operator merges on this block plus the verdicts, not on a diff — the diff is
what the review threads already read and priced, and an operator handed a diff
skim has been given back the cost the run existed to remove.

For a `tracker: github` run the body then carries the closing lines:

- `Closes #n` for every issue that maps to an item — each sub-issue that
  became an item, and the parent itself when the parent *is* the item (a
  parent with no sub-issues).
- A parent that owns sub-issues gets a non-closing `Part of #<parent>` line
  instead — the PR points at the spec without closing a spec that is not the
  work.
- Flow A's single PR lists `Closes` for every item issue; Flow B's per-item PR
  closes only its own item's issue.

Only `tracker: github` adds closing lines: a `.scratch` run's PR body is the
intent block alone, and the Task add-on does not change that.

## Failure handling

- A manager turn that spans the whole run is normal: the manager is blocked
  on `bb thread wait`, not thinking. That is not licence for silence — use
  step 3's bounded waits and report between them.
- A resumed manager re-reads the ledger and the ticket files before acting —
  its own memory of the run may be stale.
- A child reports BLOCKED or its thread dies: read `bb thread log <id>`
  before respawning anything, record the blocker in the ledger, surface it to
  the user, and keep working the rest of the frontier.
- **The manager never dies mid-item.** When its context is nearly full it
  writes the ledger and stops — it does not start an item it cannot finish.
  A manager that stopped with items still `running` or `todo` is replaced by a
  successor that reads that same ledger, which the plan thread spawns (see
  `/orchestrate-bb-plan`, *Wait for the run*). The manager never spawns its own
  replacement, and never forks itself: a fork inherits the context that just
  ran out.

## Rules

- One item per thread, one thread per item — no thread works two items.
- Children (workers, review threads, ponytail) are standard visible threads
  parented to the manager; the manager never archives them, during the run
  or after it — the user keeps the manager and its children visible together
  and archives them themselves.
- The manager never implements items itself — it dispatches, waits, routes
  review findings, and unblocks.