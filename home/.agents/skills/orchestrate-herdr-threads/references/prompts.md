<!-- Part of /orchestrate-herdr-threads. Load it before writing the first prompt file; `../SKILL.md` owns the order. -->

# Prompt contracts

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
> human input: if something blocks you, stop and report — `BLOCKED` with what
> remains, or `ESCALATE:` when a single decision would unblock you — one
> question, the options you see, the one you recommend. Run the item's tests
> and name the command in your report. Write your report to
> `$RUNDIR/reports/item-<slug>.md`: what changed, the acceptance evidence, the
> exact test command and result, then three one-line answers — `HARDEST:` the
> hardest decision you made, `REJECTED:` the alternatives you rejected and why,
> `UNSURE:` what you are least confident about. Your final message is three
> lines — `DONE`, `BLOCKED` or `ESCALATE`, one line of what changed, one line of
> what remains (for `ESCALATE`, the question).

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
> criterion needing source you cannot locate is reported **unverifiable**. The
> `<class>` names already recorded in this run's `classFixes` are listed above:
> reuse one of those spellings when the finding is that class, and coin a
> kebab-case one when it is new. Write
> your full report to `$RUNDIR/reports/review-<slug>-r<n>.md` whose FIRST line is
> `VERDICT CLEAN` or `VERDICT FINDINGS`. Your final message must be the complete
> report, starting with that verdict line. Write each finding as one line —
> `<file>:<line> · <class> · <what breaks> · "<the quoted code>"` — because a
> claim with no quotation from the code it is about is a nit, opens no fix round,
> and is reported to the operator with the rest:
>
> ```
> retry.ts:12 · unbounded-retry · the loop has no cap, so a 500 replays forever
>   · "for (let i = 0; ; i++) { await post(url) }"
> ```
>
> Reuse a `<class>` named above when the finding is that class. Two findings on
> the same file, line and normalized title are one finding.

**Ponytail** (`ponytail-<n>.txt`) — ends with:

> Run `/ponytail-review` on the full uncommitted diff (`git diff HEAD` plus
> `git status --porcelain` so new files are not invisible). Report over-
> engineering findings only; anything else you notice goes in the same report
> labelled out of scope — no class list is quoted on this pass, so coin a
> kebab-case `<class>` if a finding names a defect. Do not edit
> files. Write your report to `$RUNDIR/reports/ponytail-<n>.md` whose FIRST line
> is `VERDICT CLEAN` or `VERDICT FINDINGS`; your final message starts with that
> verdict line. A finding that names a defect is written like a review finding —
> `<file>:<line> · <class> · <what breaks> · "<the quoted code>"` — because it
> opens a fix round, and a claim with no quotation is only a nit.

**Fix** (`fix-<slug>-f<n>.txt`) — the findings verbatim, the item's file scope,
and the worker contract above, plus one outcome the worker contract does not
carry: **if the finding is wrong, say so and prove it.**

> If a finding does not hold, do not change the code to satisfy it and do not
> change it to make the complaint go away: reply `REFUTED: <the finding>` and
> quote the code that disproves it (`<file>:<line> "<the quoted code>"`). A
> `REFUTED:` with no quotation is not a refutation and the finding stands, so
> either prove it or fix it.

A fix round to a live worker re-prompts its own agent; a fresh `fix-<slug>-f<n>`
agent starts only when the worker's pane is gone.

