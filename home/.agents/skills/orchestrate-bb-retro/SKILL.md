---
name: orchestrate-bb-retro
description: "Retrospective on a finished BB orchestration run: time per phase, tokens and cost per model, what went wrong, and the edits it argues for in /orchestrate-bb-threads. Use when the user says 'retro the run', '/orchestrate-bb-retro', 'how did that run go', 'what did that run cost', or when an orchestrate-bb-threads run reaches its final report."
argument-hint: "[manager thread id]"
---

# Orchestrate BB Retro

A run is one manager thread and the children it dispatched. The retro turns
that run's event log into numbers, then into changes to
`/orchestrate-bb-threads`. Read-only against the run: it never writes to the
run, never re-runs a worker, never edits a skill without an explicit yes, and
its last act is to archive its own record in the corpus.

Two questions decide whether the retro was worth the tokens: did it explain
every number it printed, and did it end in an edit someone can make.

## Steps

1. **Identify the run.** The user names a manager thread, a run name, or
   "the run that just finished" — a thread id, or a `…/threads/thr_…` URL you
   strip back to the id. Without a name, find the candidates in
   `bb thread list --json` as threads whose children are titled `REVIEW …` or
   `PONYTAIL …`. A run that has not reached its terminal state is a **partial
   retro**: report it as one and read in-flight threads as in flight, not as
   failures.

2. **Collect the mechanics.** Run the metrics script, which pages every
   child's log and prints phases, threads, cost and findings:

   ```sh
   python3 scripts/run-metrics.py <manager-thread-id>
   python3 scripts/run-metrics.py <manager-thread-id> --json   # full structure
   ```

   Then read the ledger for the plan the run was executing — item ids,
   `blockedBy`, `reviewCount`, `attempts`, PR URLs. *Reading the numbers*
   below owns where each figure comes from and what it cannot tell you.

3. **Explain every finding.** For each line the script prints, open the
   thread it names and read the events around it (`bb thread log <id>`, or
   the stored JSON) until you can state the cause in one sentence with a
   timestamp or ledger entry behind it. A finding you cannot explain is
   reported as **unexplained** rather than guessed at; an unexplained stall
   is itself a finding.

4. **Judge the run against the skill.** *Where runs go wrong* lists the
   failures a metrics table cannot see on its own. Check every entry and
   record the ones that fired, with the event or ledger row as evidence.

5. **Write the report** to `$BB_THREAD_STORAGE/reports/retro-<run>.md`, in
   the four sections under *Report*, and summarise it in the chat: the
   numbers that moved, what broke, and the proposals. The report is done when
   every metrics finding is explained or marked unexplained, and every
   proposal names the section of `/orchestrate-bb-threads` it would change
   plus the evidence that motivates it.

6. **Propose the edits, then ask.** Rank the proposals by the cost or time
   they would have saved in *this* run — that ordering is the one the
   evidence supports. Show them as concrete edits to named sections of the
   main skill, then wait for a yes before touching it. Applying them is one
   commit on approval; the repo's own commit rules still apply.

7. **Archive the record — the retro's final step.** A partial retro must
   never archive a half-written record: start this only once the report is
   complete (every finding explained or marked unexplained, every proposal
   named). Archive before you return, whether the proposals in step 6 were
   accepted, rejected or left unanswered — the record must not depend on that
   answer.

   The **corpus** is `~/personal_workspace/bb-runs/`, its own git repository,
   one directory per run:

   ```
   runs/<date>-<project>-<slug>-<threadId>/
     report.md    the report written in step 5
     run.json     the machine record the metrics script produces
   ```

   Derive the directory name from the script's own `record_dirname()` so the
   naming can never drift from the writer: load `scripts/run-metrics.py` with
   `importlib.util.spec_from_file_location` (the filename has a dash, so it
   cannot be imported by name) and give it the record from `--json`.

   Fetch the record **once**. The name and the archived `run.json` come from
   that same fetch, so the directory's name and its bytes cannot describe two
   different records:

   ```sh
   python3 scripts/run-metrics.py <manager-thread-id> --json > /tmp/run.json  # --ledger / --no-pricing go HERE
   name=$(python3 - <<'PY'
   import importlib.util, json
   spec = importlib.util.spec_from_file_location("run_metrics", "scripts/run-metrics.py")
   metrics = importlib.util.module_from_spec(spec); spec.loader.exec_module(metrics)
   print(metrics.record_dirname(json.load(open("/tmp/run.json"))))
   PY
   )
   mkdir -p ~/personal_workspace/bb-runs/runs/$name
   cp /tmp/run.json ~/personal_workspace/bb-runs/runs/$name/run.json
   ```

   Add `--ledger PATH` if the run's ledger is not at the default
   `orchestration.json`, and `--no-pricing` when the price table cannot be
   reached — the record then says `unpriced`/`unmeasured` rather than `0.00`.
   Both flags belong on the single `--json` call above, alongside the fetch
   whose record they shape. Copy the step-5 report in as `report.md`.

   The record is a **snapshot, not a log**: the manager thread id is the
   primary key and `record_dirname()` is stable for the same run, so a re-run
   rewrites this exact directory in place rather than adding a second one.

   Commit the record as **one commit**, then stop — the corpus is **never
   pushed** by the retro:

   ```sh
   git -C ~/personal_workspace/bb-runs add runs/$name
   git -C ~/personal_workspace/bb-runs commit -m "record: runs/$name"
   ```

   That repository's own commits are exempt from the ask-first convention,
   scoped to it alone; its README records why.

   **Pointer.** When the run came from `.scratch/<feature>/` in a project
   checkout, leave a one-line pointer — the record's path — in that feature
   directory as `.scratch/<feature>/run-record.md`. Resolve the checkout from
   the project's default source, the pattern `scratch-sweep.sh` already uses:

   ```sh
   bb project list --include-personal --json \
     | jq -r '.[] | select(.name == "<project>") | .sources[] | select(.isDefault) | .path'
   ```

   A project with no source path (the `Personal` project has none) is skipped
   without error — the corpus record is still written.

## Report

- **Execution plan** — the flow, the items in dispatch order with their
  blocked-by edges, and the wave structure the run actually followed. Note
  every place it diverged from the plan it approved.
- **Time per phase** — lead with orchestrator time (span minus human wait
  that overlaps no work). Then the span, each phase's summed active time,
  and the overlap between them. Name the phase that dominated. A wait for
  the human is not time the run spent working.
- **Cost per model** — tokens and estimated USD per model and per role.
  Flag every thread the pricing table could not cover, and say how much of
  the run that leaves unpriced.
- **What to fix** — one line per finding: what happened, the evidence, and
  the smallest change that prevents it next time.
- **Changes to the main skill** — ranked proposals, each naming the section
  it edits.

## Reading the numbers

Every figure comes from `bb thread log <id> --json --all`; `bb guide json`
documents the shapes.

- **Active time** is `turn/started` to `turn/completed`. Between turns a
  thread is idle — usually waiting on the manager or on the human, not
  working. A turn that never completed still counts, and is marked.
- **Failed turns** are `turn/completed` with a status other than
  `completed`, plus `system/error` events and a thread status of `error`.
  A failed turn is what a respawn follows, so pair it with the ledger's
  `attempts` before calling an item flaky.
- **The model** comes from `client/turn/requested` →
  `data.execution.model`, per turn. More than one model in a thread means
  the model changed mid-thread.
- **Tokens exist only on pi threads**, in `thread/tokenUsage/updated` →
  `data.tokenUsage.total`. `acp-*` and `claude-code` threads report model
  and timing but no token events, so their cost is unknown — never estimate
  it from the context window. In the pi payload
  `totalTokens = inputTokens + cachedInputTokens + outputTokens`, and
  `cachedInputTokens = cacheReadInputTokens + cacheWriteInputTokens`.
- **Cost is an estimate**: tokens multiplied by OpenRouter's advertised
  per-token prices from `https://openrouter.ai/api/v1/models`, cached a day
  in `<dataDir>/cache/openrouter-models.json`. Prices move, and a provider's
  own billing can differ.
- **Waiting on the human** is a pending question, a question that timed out,
  and the idle tail until the human replies — a message that arrives two days
  later included. That wait is excluded from **orchestrator time**
  (`orchestratorMs` = span minus the part of the wait that overlaps no
  thread's active turn). Span stays the wall clock. Do not quote span as how
  long the orchestrator took.
- **Roles come from titles** — `REVIEW …`, `PONYTAIL …`, everything else a
  worker. Those titles are `/orchestrate-bb-threads`' own convention, so a
  thread that fits none of them means the run went off-script.
- **Phases overlap by design** in a shared-worktree run: reviews run beside
  the next worker. Summed active time therefore exceeds the run's span, and
  that excess is overlap, not waste. Report both, and never present the sum
  as elapsed time.
- **The ledger** is at `<dataDir>/thread-storage/<manager>/orchestration.json`
  (`dataDir` from `bb status --json`). Its `items` is a list in some runs and
  a dict keyed by item id in others; both are read. A ledger that disagrees
  with the threads is a finding in itself.

## Where runs go wrong

The failures the numbers cannot see. Check each against the skill's own
rules; every one is a candidate for the *What to fix* section.

- **Flow** — a shared worktree running items whose file scopes overlap, or a
  PR-per-item run serializing on files it was free to parallelize.
- **Models** — a route other than openrouter; a role on a model nobody asked
  for (the skill says a model that does not work stops the run and asks);
  one item split across two models.
- **Review** — an item that shipped with no review thread; a review read
  from the live worktree rather than the frozen diff or branch; the manager
  reviewing work it dispatched.
- **Iterations** — `reviewCount` of 2 or more means a fix round happened;
  at the cap the item should have been surfaced as blocked. An item that
  moved on after its third failure is a rule violation, not a success.
- **Dispatch** — a long stretch between the run's start and the first
  dispatch; a wave that went out one thread at a time when the plan called
  for parallel lanes.
- **Gates** — human wait where the skill expects none, or none where it
  expects a plan approval and a commit approval. A run that committed
  without asking is the expensive version of this finding.
- **Verification** — a worker's DONE taken as proof, a PR opened with
  checks red, an item marked done from a claim rather than a clean review.
- **Ledger drift** — items whose status contradicts their threads, threads
  the ledger never recorded, or a `prUrl` that never arrived.

## References

`scripts/run-metrics.py` owns the numbers; this file owns the judgement. The
script is read-only against the run, stdlib-only, and safe to re-run —
re-run it after a partial retro finishes to get the closing numbers.
`--json` emits the same data as a structure, `--output-dir DIR` also writes
`run.json` into DIR, and `--self-test` asserts its pure logic (pricing map,
cost arithmetic, ledger shapes) without touching the CLI.

The corpus the archived records live in, and the vocabulary around it, are
defined in `~/personal_workspace/bb-runs/CONTEXT.md`.
