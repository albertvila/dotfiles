---
name: orchestrate-bb-threads
description: "Execute an approved orchestration plan as the manager thread: dispatch the workers, keep the ledger, route reviews, land the run. Use when the user says '/orchestrate-bb-threads', or the prompt carries a manifest from /orchestrate-bb-plan."
---

# Orchestrate BB Threads

Execute an approved plan. This thread is the manager: it dispatches one visible
child thread per item, keeps the ledger, routes review findings, and lands the
run. It does not plan.

**A manifest in the prompt is the approved plan.** The manifest carries the
items with their file scopes and blockers, the flow, the waves, and any run
notes or model overrides (see `/orchestrate-bb-plan`, *The manifest*). Start
from it immediately — never re-derive the graph and never re-ask what was
already approved. With no manifest, do not derive one: say the plan is missing
and point the operator at `/orchestrate-bb-plan`.

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
| code-review | `openrouter/anthropic/claude-sonnet-5`    |
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

- A worker's DONE is a claim, not proof. Every code-changing item gets a
  separate fresh-eyes review thread; a worker or the manager reviewing its
  own work does not count. The manager never substitutes its own reading of
  a diff for this review thread. When the manager judges the findings, it
  reads the frozen diff or a bounded path only — never an unbounded scan;
  an unlocatable criterion is reported unverifiable.
- **`VERDICT CLEAN` ends the loop.** A clean verdict closes the item's
  review even when it carries non-blocking nits: nits go to the operator in
  the run summary — they are not fixed in-run and never trigger a re-review.
  Only `VERDICT FINDINGS` opens a fix round.
- Findings loop back to the **same worker**: queue them as a follow-up
  message to the worker's thread (`bb thread queue create <id> "<findings>"`,
  then `bb thread queue send`); if the thread is dead, respawn the item's
  worker with the findings in the prompt. Re-review. **Cap: 3 review passes
  per item** (`reviewCount` reaching 3). A 4th pass is never spawned: the
  item is marked `blocked`, its findings are surfaced to the user, and the
  rest of the frontier keeps moving.
  **Flow B respawn:** when the worker's thread is dead, respawn with
  `--environment "<worker-env-id>"` (the item's recorded environment from
  the ledger), **never** `--new-environment worktree` — a fresh worktree
  would orphan the item's branch and desync the ledger's `envId`.
- Ponytail fixes are **not** code-reviewed: ponytail findings → a **new
  worker** (a fresh child thread running `/implement` in the same worktree,
  titled `FIX · <finding>` on the worker model — a `PONYTAIL …` title is
  reserved for a ponytail pass) implements them → ponytail re-checks only.
  Same cap of 3, same blocked-and-surfaced outcome.
- Scale review depth to the item's risk. Mechanical items (deletions,
  renames, rendering-only, docs, config) get a short prompt: verify the
  change is complete, nothing out of scope was touched, tests/typecheck
  pass. Items with real state, logic, or contract surface (RPC schemas,
  fetch lifecycles, data scoping) get the full adversarial pass: every
  acceptance criterion verified in code, edge cases probed, test fixtures
  judged for genuine pinning. A uniformly maximal checklist wastes 10–30
  min per low-risk item; a uniformly minimal one misses the bug only a deep
  pass catches.
- Every review and ponytail thread's FINAL message must be the complete
  report starting with `VERDICT CLEAN` or `VERDICT FINDINGS`; findings must
  not be recorded as follow-ups instead of reported.
- A completion whose final message does not start with `VERDICT CLEAN` or
  `VERDICT FINDINGS` is not a pass and not a findings round. Re-prompt that
  thread once with the contract. Do not increment `reviewCount` for it. A
  second non-verdict completion is surfaced, not treated as clean.

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

1. **Spawn every ready item's worker**, each to its own visible child thread:

   ```sh
   bb thread spawn --parent-self \
     --project "$BB_PROJECT_ID" \
     --environment "$BB_ENVIRONMENT_ID" \
     --model "<worker-model>" \
     --title "<item-id> · <short title>" \
     --permission-mode auto --json \
     --prompt "Work this item only: <self-contained instructions>. You are in the manager's shared worktree — leave your changes uncommitted and do NOT commit or push. When done, your final message must state DONE or BLOCKED and a 3-line summary of what changed / what blocks you."
   ```

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
   bb thread wait <id> --status idle --timeout 3600 --json
   bb thread output <id>
   ```

   The command after a successful spawn is `bb thread wait`. Stay on that
   wait until it matches idle — no `sleep`, and no `bb thread show` or
   `bb thread output` while the child is active. A wait that returns before
   idle is not a failure — check `bb thread show <id> --json`; if the thread
   is still working, wait again. Collect the final output and mark the item
   `done` or `blocked`/`failed` from the worker's DONE/BLOCKED report.

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
   schemas, fetch lifecycles, data scoping) — runs `/code-review` and keeps
   the whole-directory snapshot; a **mechanical** item — deletions, renames,
   rendering-only, docs, config — skips `/code-review` and gets a diff scoped
   to that item's files with the same final-message contract:

   ```sh
   bb thread spawn --parent-self \
     --project "$BB_PROJECT_ID" \
     --environment "$BB_ENVIRONMENT_ID" \
     --model "<reviewer-model>" \
     --title "REVIEW <item-id> · <short title>" \
     --permission-mode auto --json \
     --prompt "Fresh-eyes code review. Run /code-review on the frozen diff at $BB_THREAD_STORAGE/diffs/<item-id>.diff (item <item-id>: <item scope>) — do NOT review the live worktree diff, another worker may already be changing those files; read worktree files only for surrounding context. Report findings against the item's acceptance criteria. Do not edit files. Your FINAL message must be the complete report starting with VERDICT CLEAN or VERDICT FINDINGS, and findings must not be recorded as follow-ups instead of reported."
   ```

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
     --prompt "Run /ponytail-review on the full uncommitted diff in this worktree (git diff HEAD). Report findings; do not edit files. Scope the report to over-engineering findings; anything else you notice goes in the same final message labelled out of scope. Your FINAL message must be the complete report starting with VERDICT CLEAN or VERDICT FINDINGS, and findings must not be recorded as follow-ups instead of reported."
   ```

   **Scope.** The pass reports ponytail findings only. Anything else it
   notices — a correctness note outside over-engineering — is an out-of-band
   note the manager surfaces to the operator: never a fix round, never a
   re-review.

   The fix path and the cap are in *Review loops*.

   In a multi-repo run (see *Cross-repo runs*) there is no combined diff to
   pass: run one ponytail pass per item diff, none optional — the last
   item's pass is not skippable, and a single combined pass is not a
   substitute.

6. **Commit + open one PR.** Propose the commit message and file list to the
   user (per repo conventions; detect the PR base branch), and wait for an
   explicit yes. Ask the gate with a pending interaction (`AskUserQuestion`),
   not a plain message — a message can be answered in any thread, and a yes
   relayed through the plan thread never reaches this run's record. If the
   answer arrives out of thread anyway, restate it in this thread before
   committing. On yes: commit, push the branch, open exactly one PR
   (`gh pr create`), then post the lm statuses from that repo root. `<base>`
   is the detected PR base:

   ```sh
   lm pr-test --base origin/<base>
   lm report-upload
   ```

   Run the upload even when pr-test fails, so GitHub gets a failure instead of
   a missing check. `lm xpush` does not replace this on a first push: the
   pre-push hook's `pr-test --refresh-pr` no-ops until a PR exists, and a
   hook filecheck report is not the required `lm-build/filecheck` context.
   Done when the PR head has both `lm-build/filecheck` and
   `lm-build/projectCheck`. If `report-upload` fails for missing AWS or lm
   credentials, say so and hand the two commands to the operator — do not
   treat the PR as check-complete. The body carries the closing lines below
   (see *PR body closing lines*).

7. **Post-merge cleanup.** After the user merges on GitHub: pull main,
   delete the merged branch, and post a final report (what shipped, per-item
   outcomes). Retiring the worktree is a hand-off, not a manager action:
   `bb environment delete` is refused while any thread in the environment is
   live, and the manager never archives threads (see *Rules*) — tell the
   user the environment id and let them archive the threads and retire it.

## Flow B — PR per item

Trigger: the manifest's flow is `B`. Every worker gets its
own worktree+**branch**; all items run fully **parallel** — isolation means
they never clobber each other, so there is no file-overlap gating and no
shared worktree. One PR per item, reviewed by the user on GitHub. Same models
and review loops as the shared sections above (*Models*, *Review loops*).

1. **Spawn every ready item's worker — one worktree+branch each.** Drop
   `--environment "$BB_ENVIRONMENT_ID"` (sharing is the Flow A move) and pass
   `--new-environment worktree` so each worker provisions its own
   worktree+branch off the project base branch; all ready items spawn at
   once. Record the returned thread id **and its environment id** in the
   ledger — review and ponytail threads reuse that environment to see the
   branch.

   ```sh
   bb thread spawn --parent-self \
     --project "$BB_PROJECT_ID" \
     --new-environment worktree \
     --model "<worker-model>" \
     --title "<item-id> · <short title>" \
     --permission-mode auto --json \
     --prompt "<the Flow A step 1 worker prompt, unchanged>"
   ```

Then run Flow A steps 2–7 with these deltas:

- **Flow A step 2 — no file-overlap gating.** The disjoint-files rule and the
  review/worker overlap rule do not apply here. Keep every item moving at once
  with short waits. Cross-item dependencies still gate dispatch: an item stays
  `todo` until its `blockedBy` items settle.
- **Flow A steps 4–5 — review and ponytail in the item's environment.** Both
  spawn with `--environment "<worker-env-id>"` in place of
  `"$BB_ENVIRONMENT_ID"`, and the ponytail pass runs per branch on that
  branch's uncommitted diff.
- **Flow A step 6 — one PR per item.** Same commit-message approval and
  base-branch detection, then commit the branch (`bb environment commit
  <env-id>`) and mark that environment's PR ready (`bb environment
  pull-request ready <env-id>` — each worktree environment owns its PR).
  After that PR is open, run Flow A step 6's lm status commands in that
  item's worktree, against the same detected base. Same done check.
  Its body carries the closing lines below (see *PR body closing lines*).
  Merging items into one PR is the Flow A shape.
- **Flow A step 7 — merge and clean up N PRs.** Merge in dependency order:
  first the items whose `blockedBy` list is already fully settled (base
  items), then the items that name them in their `blockedBy`, working outward
  through the dependency graph — `bb environment pull-request merge <env-id>`
  (merge/squash/rebase per repo convention). Resolve cross-PR conflicts that
  appear as later branches land: rebase/merge the conflicting branch onto the
  now-merged base and re-run its checks (the branch is yours to fix; its item
  already proved the diff). Then delete the merged branches (provider
  teardown keeps the branch; remove local + remote per repo convention) and
  hand worktree retirement to the user: the manager never archives threads
  (see *Rules*), and `bb environment delete <env-id>` is refused while
  threads are live — once the user archives the item's threads, they (or a
  later cleanup pass) retire each worktree.

## Cross-repo runs

When the manifest names the cross-repo shape, the items span more than one
repo: there is no shared worktree and no single PR. Each item gets its own
per-item environment and its own per-repo gate, and no single PR closes the
run. Never treat this shape as `flow: "A"`.

## The ledger

There is no Tasks panel for this — the manager IS the tracker. When the user
asks for a status view, regenerate the plan diagram with fresh status colors
(done / in review / todo) from the ledger. Keep
`$BB_THREAD_STORAGE/orchestration.json` mapping each item to
`{ threadId, envId, status, blockedBy, reviewCount, prUrl }` — `threadId` is
always the item's **worker** thread, and the manager's own thread id never
appears in `items` (`envId`, the item's worktree environment, and `prUrl`
belong to Flow B) — plus the run's `models` and `finishedAt`. Statuses: `todo`, `running`, `done`, `failed`, `blocked`.

`reviewCount` counts completed review iterations: the initial review is `1`
and each re-review adds `1`. Write the ledger as you go, never batched at
settlement — `reviewCount` when the iteration completes, `models` and each
item's `status` as the run moves — the ledger must read true mid-run.
Write an item `done` only when its review is clean **and** the ponytail pass
over its files has settled; a diff that changes after a `done` write reopens
the item explicitly. `finishedAt` is set once the run is done by the
definition below — every item terminal **and** the PR opened after the
approval gate.

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
  any other label. See
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

## PR body closing lines

For a `tracker: github` run the PR body carries the closing lines:

- `Closes #n` for every issue that maps to an item — each sub-issue that
  became an item, and the parent itself when the parent *is* the item (a
  parent with no sub-issues).
- A parent that owns sub-issues gets a non-closing `Part of #<parent>` line
  instead — the PR points at the spec without closing a spec that is not the
  work.
- Flow A's single PR lists `Closes` for every item issue; Flow B's per-item PR
  closes only its own item's issue.

Only `tracker: github` adds closing lines: a `.scratch` run keeps the PR body
it has today, and the Task add-on does not change that.

## Failure handling

- A manager turn that spans the whole run is normal: the manager is blocked
  on `bb thread wait`, not thinking.
- A resumed manager re-reads the ledger and the ticket files before acting —
  its own memory of the run may be stale.
- A child reports BLOCKED or its thread dies: read `bb thread log <id>`
  before respawning anything, record the blocker in the ledger, surface it to
  the user, and keep working the rest of the frontier.

## Rules

- One item per thread, one thread per item — no thread works two items.
- Children (workers, review threads, ponytail) are standard visible threads
  parented to the manager; the manager never archives them, during the run
  or after it — the user keeps the manager and its children visible together
  and archives them themselves.
- The manager never implements items itself — it dispatches, waits, routes
  review findings, and unblocks.