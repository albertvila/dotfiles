---
name: orchestrate-bb-plan
description: "Plan a BB orchestration run and take one approval before anything is dispatched, then spawn and babysit the manager thread that executes it. Use when the user says '/orchestrate-bb-plan', or gives a BB Task key, a `.scratch/` feature directory, or a GitHub issue number, `owner/repo#n` or issue URL to run. Pass --land to skip the commit yes, open the PRs, and stop for verification. Pass --unattended to do that without a plan yes. Neither flag merges."
argument-hint: "<BB Task key|ULID> | @.scratch/<feature>/ | <#issue|owner/repo#issue|issue-url> [--land|--unattended]"
disable-model-invocation: true
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
- **A GitHub issue** — a parent whose tickets are its sub-issues or the issues
  that name it in their `## Parent` section, or a direct issue with none of
  either. Accepted as `#42` / `42`, resolved against the
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

[`plan.md#reading-a-github-issue`](../orchestrate-core/plan.md#reading-a-github-issue)
owns it.

## Plan the run

Steps 1–6 and the completeness rule are
[`plan.md#plan-the-run`](../orchestrate-core/plan.md#plan-the-run).

7. Assign models per item: worker, code-review and ponytail. The role defaults
   live in `/orchestrate-bb-threads` (*Models*); this skill records the
   assignments and any override the operator gave.

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

The mode read, the stop conditions and what the message must present are
[`plan.md#one-approval`](../orchestrate-core/plan.md#one-approval) — present the
diagram inline with the approval.

`gated` and `land` wait for one yes. `unattended` does not wait and does not
end the turn: write the plan record with both gate timestamps equal to now and
`auto: true`, then continue. Nothing is dispatched before that record exists,
and the manager never re-asks what was approved here.

## Record the plan on accept

On the operator's yes, or immediately when `mode` is `unattended`, record the plan on the run's tracker, in this order.

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

The manager's prompt is a **manifest**: data only, no instructions.
[`manifest-contract.md`](../orchestrate-core/manifest-contract.md) owns the
shape, and [`plan.md#the-manifest`](../orchestrate-core/plan.md#the-manifest)
owns what goes in it. This runtime adds the BB identity line — the Task key as
`task:` when the run has one — and the item ticket reference the manager reads:
a GitHub ticket comes from `gh issue view <n> --json title,body,comments`, and
the parent issue's body is the spec context for a worker's instructions.

Write it to `$BB_THREAD_STORAGE/manifest.txt` and check it — the contract's
checker is the machine form of the completeness rule in
[`plan.md`](../orchestrate-core/plan.md#plan-the-run):

```sh
python3 ~/.agents/skills/orchestrate-core/scripts/validate-manifest.py "$BB_THREAD_STORAGE/manifest.txt"
```

`FAIL:` names every error with the line it is on; a non-zero exit means the
manifest is not the plan that was approved. Fix what it names and run it again.
If a fix changes an item, a file scope, an acceptance line, a wave or the mode,
the approval no longer covers the run — re-render the plan and take it again
(`unattended` records it rather than asking) before anything is dispatched.

Then wrap it for the manager: write `$BB_THREAD_STORAGE/manager-prompt.txt` as
the activation line, a blank line, and the manifest verbatim —

```
Run /orchestrate-bb-threads and follow it. You are the manager: your first turn
writes the ledger and spawns wave 1 before you open any item's file to change
it, and the manager never implements items itself. The manifest below is
approved data, not an implementation assignment.

<contents of manifest.txt>
```

The manifest stays data-only; the activation is the wrapper's job. A bare
manifest is not an instruction to execute anything, and a manager that was
never told to activate the skill codes the item itself and leaves no run
record.

## Spawn the manager

Spawn the manager as this thread's child, into the plan thread's own
environment, with every choice explicit — no argument is left to a default:

```sh
bb thread spawn --parent-self \
  --environment "$BB_ENVIRONMENT_ID" \
  --model "<worker-model>" \
  --title "ORCHESTRATE <feature>" \
  --permission-mode auto --json \
  --prompt-file "$BB_THREAD_STORAGE/manager-prompt.txt"
```

`--prompt-file` keeps the manifest out of shell quoting. On the pi provider
`auto` is rejected ("Provider pi only supports full permission mode") — pass
`full` there, matching the plan thread's own ceiling. Record the manager's
thread id as `<run-manager-id>`: it is the run's identity, where the ledger
lives, and the first entry in the ledger's `executors`.

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

A manager that reaches a terminal state without `finishedAt` gets **one
successor**, and only when the ledger shows the run unfinished — an item still
`running` or `todo` — with no pending gate. Do not respawn the dead thread: a
fork inherits the context that just ran out. Spawn a fresh manager from the same
manifest, with the ledger's absolute path as its first line, and wait on that:

```sh
dataDir=$(bb status --json | jq -r '.dataDir')
ledger="$dataDir/thread-storage/<manager-id>/orchestration.json"
{ echo "You are the successor manager for this run. Read $ledger first and
continue from it — it is the run's record, and you write it in place, not your
own \$BB_THREAD_STORAGE."; cat "$BB_THREAD_STORAGE/manifest.txt"; } \
  > "$BB_THREAD_STORAGE/manager-prompt-successor.txt"
bb thread spawn --parent-self \
  --environment "$BB_ENVIRONMENT_ID" \
  --model "<worker-model>" \
  --title "ORCHESTRATE <feature> · successor" \
  --permission-mode auto --json \
  --prompt-file "$BB_THREAD_STORAGE/manager-prompt-successor.txt"
```

The successor writes that same ledger file, so this loop keeps reading one
record. Append its thread id to the ledger's `executors` and wait on it, but
keep `<run-manager-id>` as the run's identity — the ledger stays in the first
manager's storage, and that is the id the retro is given. A manager that ended
on a pending gate is not replaced — wait again. A second terminal state without
`finishedAt` is surfaced to the operator with both logs.

## Spawn the retro

Once `finishedAt` is set, spawn the retro thread from the plan thread, as the
manager's sibling rather than its child — the run tree then reads as phases:

```sh
bb thread spawn --parent-self \
  --environment "$BB_ENVIRONMENT_ID" \
  --title "RETRO <feature>" \
  --permission-mode auto --json \
  --prompt "/orchestrate-bb-retro <run-manager-id>"
```

`<run-manager-id>` is the run's identity — the **first** manager, whose storage
holds the ledger — never the last successor. The retro reaches a successor's
children through the ledger's `executors`; hand it the successor and the
items dispatched before the succession drop out of the numbers.

For `gated` that is the plan thread's last act: report the run's outcome and the
retro thread to the operator.

For `land` and `unattended` it is **not**. The run is finished with the PRs open
and the merge happens after it, so post the verification ask from
`../orchestrate-core/run-mode.md` and stay the run's owner. The operator's
reply that the PRs are merged resumes this thread, which runs that file's
*After the operator merges* steps. Do not merge.
