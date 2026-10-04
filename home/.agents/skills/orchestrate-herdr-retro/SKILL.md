---
name: orchestrate-herdr-retro
description: "Retrospective on a finished Herdr orchestration run: time per phase, tokens and cost per model, what went wrong, and the edits it argues for in /orchestrate-herdr-threads. Use when the user says 'retro the run', '/orchestrate-herdr-retro', 'how did that run go', 'what did that run cost', or when an orchestrate-herdr-threads run reaches its final report."
argument-hint: "[run directory]"
---

# Orchestrate Herdr Retro

A Herdr run is one ledger and the agents it dispatched into their own tabs. The
retro turns that run's records into numbers, then into changes to
`/orchestrate-herdr-threads`. It is read-only against the run: it never writes to
the run, never re-prompts an agent, never edits a skill without an explicit yes,
and its last act is to archive its own record in the corpus.

Two questions decide whether the retro was worth the tokens: did it explain every
number it printed, and did it end in an edit someone can make.

## Steps

1. **Identify the run.** `$RUNDIR` is the run directory the plan wrote —
   `<worktree>/.herdr-runs/<feature>/` — taken from the argument, or found as the
   most recent `.herdr-runs/*/orchestration.json` in this worktree when the
   operator only says "the run that just finished". A ledger whose `finishedAt`
   is null is a **partial retro**: report it as one, and read in-flight agents as
   in flight, not as failures.

2. **Collect the mechanics.** Run the metrics script, which reads the ledger and
   every pi session transcript it names:

   ```sh
   python3 scripts/run-metrics.py <rundir>
   python3 scripts/run-metrics.py <rundir> --json          # full structure
   python3 scripts/run-metrics.py <rundir> --output-dir <dir>   # also writes run.json
   ```

   Then read the ledger itself for what the script does not judge — item
   `blockedBy` edges, `reviewCount`, `prUrl`, gate timestamps, the `models` the
   run claimed. *Reading the numbers* below owns where each figure comes from and
   what it cannot tell you.

3. **Explain every finding.** For each figure that looks wrong, open the record
   it came from — the ledger row, the named pi session transcript, the worker's
   report file under `$RUNDIR/reports/`, the preserved prompt under
   `$RUNDIR/prompts/` — until you can state the cause in one sentence with a
   timestamp or ledger entry behind it. A finding you cannot explain is reported
   as **unexplained** rather than guessed at; an unexplained stall is itself a
   finding.

4. **Judge the run against the skill.** *Where runs go wrong* lists the failures
   a metrics table cannot see on its own. Check every entry and record the ones
   that fired, with the ledger row, report file or transcript event as evidence.

5. **Write the report** to `$RUNDIR/reports/retro-<feature>.md`, in the sections
   under *Report*, and summarise it in the chat: the numbers that moved, what
   broke, and the proposals. The report is done when every finding is explained
   or marked unexplained, and every proposal names the section of
   `/orchestrate-herdr-threads` it would change plus the evidence behind it.

6. **Propose the edits, then ask.** Rank the proposals by the cost or time they
   would have saved in *this* run — that ordering is the one the evidence
   supports. Show them as concrete edits to named sections of the main skill,
   then **end the turn** and wait for a yes before touching it. Applying them is
   one commit on approval; the repo's own commit rules still apply.

7. **Archive the record — the retro's final step.** A partial retro must never
   archive a half-written record: start this only once the report is complete
   (every finding explained or marked unexplained, every proposal named).
   Archive before you return, whether the proposals in step 6 were accepted,
   rejected or left unanswered.

   The **corpus** is `~/personal_workspace/herdr-runs/`, its own git repository,
   one directory per run:

   ```
   runs/<record_dirname>/
     report.md    the report written in step 5
     run.json     the machine record the metrics script produces
   ```

   Fetch the record **once** — the directory name and the archived bytes come
   from the same `--json` call, so they cannot describe two different records:

   ```sh
   python3 scripts/run-metrics.py <rundir> --json > /tmp/herdr-run.json
   name=$(python3 -c "import json;print(json.load(open('/tmp/herdr-run.json'))['record_dirname'])")
   mkdir -p ~/personal_workspace/herdr-runs/runs/$name
   cp /tmp/herdr-run.json ~/personal_workspace/herdr-runs/runs/$name/run.json
   ```

   `record_dirname` is `<date>-<project>-<feature>`, derived from the ledger's
   own `startedAt` — the primary key of the run — so a re-run rewrites this exact
   directory in place rather than adding a second one. Copy the step-5 report in
   as `report.md`.

   Commit the record as **one commit** when `~/personal_workspace/herdr-runs/.git`
   already exists — that corpus is exempt from the ask-first convention, scoped to
   it alone, the way `bb-runs` and `orca-runs` are. If the directory does not
   exist yet, create it, write the record, tell the operator it is uninitialised,
   and ask before running `git init` or committing — a brand-new repository is not
   covered by the exemption. The retro **never pushes** it:

   ```sh
   git -C ~/personal_workspace/herdr-runs add runs/$name
   git -C ~/personal_workspace/herdr-runs commit -m "record: runs/$name"
   ```

   **Pointer.** When the run came from `.scratch/<feature>/`, leave a one-line
   pointer — the record's path — as `.scratch/<feature>/run-record.md`.

## Report

- **Execution plan** — the flow, the items in dispatch order with their
  blocked-by edges, and the wave structure the run actually followed, read from
  the ledger's item order and gate timestamps. Note every place it diverged from
  the plan it approved.
- **Time per phase** — lead with the span and the active sum, then the covered
  wall clock and the overlap (reviews run beside the next worker by design, so
  the sum exceeds the span; report both and never present the sum as elapsed
  time). Break it down by role — workers, reviews, fixes, ponytail, coordinator —
  and name the phase that dominated and the longest single agent span. Gate waits
  (plan approval, commit approval) are human time, reported separately; any other
  human wait is not separable and is marked **partial**. A host suspend inside the
  span is named separately too — it is environment, not work and not a gate, and
  the run's working wall clock is the span with it removed.
- **Cost per model** — tokens and USD per model and per role, from pi's own
  recorded usage. Flag every session whose turns recorded no cost, and say how
  much of the run that leaves unpriced.
- **What to fix** — one line per finding: what happened, the evidence, and the
  smallest change that prevents it next time.
- **Changes to the main skill** — ranked proposals, each naming the section it
  edits.

## Reading the numbers

Every figure comes from two sources: the ledger
(`$RUNDIR/orchestration.json`) and the pi session transcripts the ledger names.
Herdr keeps no turn telemetry, so nothing is read from it after the run.

- **The transcript** is JSONL at the path `herdr agent start` reported as
  `agent_session.value`. Every `message` event carries a timestamp; every
  assistant message carries `model`, `provider` and `usage` —
  `input`/`output`/`cacheRead`/`cacheWrite`/`reasoning`/`totalTokens` plus a
  `cost` breakdown. **Active time** for an agent is its first to last message;
  pi reports no per-turn boundary the script can trust, so do not invent one.
- **Cost is pi's own recorded figure**, not a price-table estimate; where a
  provider returned no cost the entry is `$0.00` for real work, which is reported
  as **unpriced**, never as free.
- **Sessions exist only if the agent ran a turn.** A session path recorded at
  start with no transcript means the agent was started and never prompted, or
  died first — a finding, not a zero.
- **Roles come from the ledger's shape** — workers under `items.*.worker`,
  reviews under `items.*.reviews`, fixes under `items.*.fixes`, plus `ponytail`
  and the `coordinator`. Agent names encode the same convention
  (`item-<slug>`, `review-<slug>-r<n>`, `fix-<slug>-f<n>`, `ponytail`), so an
  agent that fits neither means the run went off-script.
- **Overlap is design, not waste**: in a shared-worktree run reviews run beside
  the next worker. `activeSumSec` − `coveredSec` is that overlap — computed over
  **unique sessions**, because a fix round re-prompts the worker's own session and
  counting that transcript once per role would double its time *and* its price;
  the coordinator is clipped to the ledger's own `startedAt`/`endedAt`, with the
  part outside the run reported as `coordinatorRunSec`/`outsideRunSec` rather
  than absorbed into `covered`.
- **A span is not work, and the script says which is which.** `workSumSec` is
  per-session span minus gaps > 10m, deduped; `quietSumSec` is what that removes
  — a host suspend, or the hours between a re-prompted worker's turns. `ledgerDrift`
  lists every ledger interval its own transcript contradicts (backwards, before
  the session's first message, after its last). Quote it instead of re-deriving it
  by hand: a drifted row is a finding, not arithmetic to redo.
- **Gate waits** come from the ledger's `gates.plan` / `gates.commit`
  `requestedAt` → `approvedAt` pairs (in a Flow B run, each item's own
  `commitGate`). A gate with a request and no approval in a finished run is a
  finding.
- **A ledger that disagrees with the transcripts is a finding in itself** — an
  item `done` with no clean review, a worker session path that never existed, a
  `finishedAt` while an item is still `running`.

## Where runs go wrong

The failures the numbers cannot see. Check each against the skill's own rules;
every one is a candidate for the *What to fix* section.

- **Preflight** — a run dispatched without `herdr integration status` reading
  `pi: current`; a stalled prompt misread as a running worker.
- **Host suspend** — a multi-hour gap written up as a model, provider or
  orchestrator failure without checking the machine's own sleep log. A closed lid
  drops the network and then freezes everything: every in-flight turn dies on
  provider timeouts in the same minute, the run stops dead, and it resumes only
  when the operator wakes the host and prompts `continue`. Check `pmset -g log`
  (macOS: look for `Clamshell Sleep` / `Maintenance Sleep` and the wake, and for
  the last write landing inside a maintenance-sleep window), `journalctl -b` or
  `last` elsewhere, **before** naming a cause. If the host slept, that is the
  finding — the smallest change is a keep-awake or a stated expectation for
  `land`/`unattended` runs, never a model swap.
- **Flow** — Flow A items with overlapping scopes dispatched together; a Flow B
  item started in the wrong workspace, so two items shared one branch; a Flow A
  worker given its own worktree, so the combined diff never existed.
- **Dispatch hygiene** — two items on one agent name; a name collision worked
  around by renaming or stopping an agent the coordinator did not start; a prompt
  re-sent after `timeout` or `agent_prompt_stalled` without inspecting the pane;
  a start refusal retried without reading its error code.
- **Wait discipline** — a worker read as done while still `working`; `idle` read
  as failure; a settle decision made on `unknown`; a `DONE` claim taken as proof.
- **Review** — an item that shipped with no `REVIEW` tab; a review pointed at the
  live worktree instead of `$RUNDIR/diffs/`; a new-file item handed the empty
  `git diff HEAD` and nobody noticed; a non-verdict completion counted as an
  iteration; `reviewCount` at 4 instead of a blocked-and-surfaced item; the
  coordinator reviewing work it dispatched.
- **Release** — a tab closed before its verdict was read; a report that never
  reached disk because the only record was the scrollback; a tab the coordinator
  did not create closed; a dirty worktree removed with `--force`.
- **Model claims** — a role reported on a model that was never passed; a respawn
  that silently inherited different flags; a run that continued past a model
  failure instead of stopping to ask.
- **Gates** — a dispatch before the plan approval when `mode` is `gated` or
  `land`; a commit before the operator's yes when `mode` is `gated`; a
  coordinator that kept working after asking; human wait where the skill
  expects none. A `gated` Flow B merge without `--match-head-commit` of
  `reviewedHead` is a finding. A `land` or `unattended` run that merged, or that
  finished without the verification ask, is a finding. An `unattended` run that
  reduced tickets is a finding.
- **Verification** — a PR opened with checks red; an item marked `done` from a
  claim rather than a clean review; `finishedAt` written while an item was still
  in flight.
- **Respawn fidelity** — a killed worker respawned into a different pane or under
  a different name, or a ledger that still points at the dead pane; a respawned
  agent whose model or worktree silently changed.
- **Ledger drift** — an item whose status contradicts its agents, a missing
  session path for an agent that ran, or threads the ledger never recorded.

## References

`scripts/run-metrics.py` owns the numbers; this file owns the judgement. The
script is read-only against the run, stdlib-only, and safe to re-run — re-run it
after a partial retro finishes to get the closing numbers. `--json` emits the
same data as a structure (`record_dirname` included), `--output-dir DIR` also
writes `run.json` into DIR, and `--self-test` asserts its pure logic (usage
summing, interval union, gate arithmetic, corpus naming) without touching a run.
