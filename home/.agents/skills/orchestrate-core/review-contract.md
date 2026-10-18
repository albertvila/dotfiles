# Review contract

One review rule, read by both runtimes. The spawn commands, agent names and ledger field names live in each skill; this file owns what a review is, when it ends, and what a fix round costs.

## A finding is a defect

A **finding** is a defect in behaviour, in a named acceptance criterion, or a failure of a gate this run must pass (lint, typecheck, tests). Lint-gate failures are findings: they fail CI. A **nit** is everything else — a preference, a style choice the gate accepts, an observation with no gate behind it.

A finding is **evidenced and classified**, and both are on the report line:

```
<file>:<line> · <class> · <what breaks> · "<the line(s) that prove it>"
```

- **The location and the quotation are the evidence.** A claim with no quotation
  from the code it is about is a nit: it opens no fix round, and it is reported to
  the operator with the rest of them. The quotation is what a fix round reads to
  decide whether to change the code at all, so a finding whose evidence is not in
  the tree is [refuted](#a-findings-round-ends-in-code-a-refutation-or-a-stop), not
  silently dropped.
- **`<class>` is a short kebab-case name for the defect class** —
  `unbounded-retry`, `missing-null-guard`, `unstamped-column`. The brief lists
  every class already recorded in the run's `classFixes`
  ([ledger.md](ledger.md)), and a finding of one of those classes reuses the
  recorded spelling: a class written under two slugs is a class the run pays to
  diagnose twice.
- Two findings with the same file, line and normalized title are **one finding**.

**Four things are not findings**, whatever they are called, and none of them
opens a fix round or counts against the cap — each is a nit:

- a defect in code this item's diff does not touch, which the base already carried
- something the run's own gate already catches — the lint, typecheck or test
  command the validation step runs: that gate is the finding
- something the surrounding code already guards
- a preference with no gate behind it ("consider extracting…", "you might add…")

**Intent comes from the manifest, and it is the plan's.** The item's `acceptance` and `out-of-scope` lines are quoted into the review brief from the approved manifest; a criterion re-derived from the ticket at review time is off-contract, because the ticket was written before the work. The `out-of-scope` line bounds what a reviewer may require — a finding that the item omitted something it declared out of scope is not a finding. Work performed *beyond* that boundary is still reviewable: scope creep is a defect, not an exemption.

**The worker's account is a lead, not a verdict.** Every worker states its hardest decision, the alternatives it rejected, and what it is least confident about; the review brief quotes those lines. They are how a reviewer tells a deliberate choice from a wrong one — a rejected alternative that was correctly rejected is not a finding, and one that was wrongly rejected is. An item the worker flagged `UNSURE:` is checked harder, not excused: if the concern is real it is a finding like any other, and a `UNSURE:` line the reviewer cannot confirm in the code is reported unverifiable rather than accepted.

## CLEAN ends the loop

`VERDICT CLEAN` closes the item's review even when it carries non-blocking nits. Nits go to the operator in the run summary: they are not fixed in-run and never open a re-review. Only `VERDICT FINDINGS` opens a fix round.

The same holds for a ponytail pass whose notes are all out-of-band — a preference, a style choice, an observation with no gate behind it. It returns `VERDICT CLEAN` and lists them as nits. A `VERDICT FINDINGS` with no fix round behind it is a verdict that says a round happened when none did.

Every review and ponytail report ends with `VERDICT CLEAN` or `VERDICT FINDINGS` as its first line, and findings are reported there — never recorded as follow-ups instead.

## The review thread does the pass itself

The review runs in the review thread, from its own context. Do not invoke the two-axis `/code-review` skill: its mandatory Standards and Spec subagents report their tokens nowhere the run can see, so the review goes unpriced and the verdict is not the reviewer's own. The review thread spawns no subagents at all.

Depth scales to the item's risk. A **high-risk** item — real state, logic, or contract surface (RPC schemas, fetch lifecycles, data scoping) — gets the full adversarial prompt in that one thread: every acceptance criterion verified in code, edge cases probed, test fixtures judged for genuine pinning. A **mechanical** item — deletions, renames, rendering-only, docs, config — gets a short pass over the frozen diff. A uniformly maximal checklist wastes 10–30 min per low-risk item; a uniformly minimal one misses the bug only a deep pass catches. An item whose criteria exceed what one thread can hold should have been split at plan time. The call itself is recorded as the item's `risk` ([ledger.md](ledger.md)) when its first review is dispatched, so a reader can tell a deliberate depth and model choice from a forgotten flag instead of inferring one.

## Cap: 3 findings rounds per item

A **findings round** is a pass that returns `VERDICT FINDINGS`. A pass after a `VERDICT CLEAN` — a ponytail re-check, a gate-config change, a post-review change — does not consume the cap. The cap reads off the findings rounds, never off all passes: the review rounds that opened a `fixes` entry ([ledger.md](ledger.md)). A 4th findings round is never spawned: the item is `blocked` with `cause.code: cap_exhausted`, its findings are surfaced to the operator, and the rest of the frontier keeps moving.

**A re-review is scoped to the delta.** Its brief names what changed and only the earlier conclusions that change could have invalidated. A delta that changes no logic, state or contract surface (stylesheets, docs, renames) does not re-open the acceptance criteria at all. A re-check told to re-settle every earlier conclusion is the run's longest and most expensive agent, spent re-deriving a report it already wrote.

**A re-review is gated on the artifact having moved.** Each pass reads its own frozen diff, and the next pass is spawned only when the new freeze differs from **every freeze this item has read**. Identical bytes are not a new round: the fix settled without changing anything, so the item is `blocked` with `cause.code: artifact_unchanged`, its findings are surfaced, and the frontier keeps moving. Re-reading unchanged evidence spends one of the three findings rounds on a verdict that is already written.

**A freeze that repeats an earlier pass's is oscillation, not a new round.** The
new freeze matching any freeze this item has already read — not only the last one
— means the rounds are bouncing the diff between two states. The item is
`blocked` with `cause.code: nonconvergent`, and `detail` names the invariant the
two rounds disagree about. The same holds for a finding: the same file, line and
normalized title returned in **two consecutive** findings rounds is not a
disagreement to spend a third round on, and it stops the item the same way. A
retro reads both of these as the run's failure to hold one story about the
change, which is a plan problem, not a fix-round problem.

## A findings round ends in code, a refutation, or a stop

A fix round is dispatched with the findings, and it has three outcomes. The
coordinator records which one it was, because the re-review's spawn depends on it:

- **The code changed.** The re-review waits on the new freeze, above.
- **`REFUTED:`** — the worker names the finding and quotes the code that
  disproves it. No re-review is spawned: a reviewer handed a delta that does not
  exist re-derives a verdict it already gave. The item is `blocked` with
  `cause.code: finding_refuted`, `detail` naming the finding in one line, and the
  round's `fixes` entry carries `refutation: {finding, evidence}`
  ([ledger.md](ledger.md)) so the retro can count refutations instead of
  inferring them from a stop. A `REFUTED:` with no quotation is not a refutation —
  the round is `artifact_unchanged` like any other no-op, and the finding stands.
- **Neither** — `artifact_unchanged`.

A refutation is a disagreement about the code, handed to the operator with the
finding it answers. It is not a settlement: the item does not become `done`, and
the operator's adjudication is what clears the cause, exactly as it does after
the cap.

## One class fix, one diagnosis

A finding whose `<class>` matches a recorded `classFixes` entry has already been
diagnosed in this run, and the run does not pay for that diagnosis twice. The
coordinator reuses the entry's `brief` verbatim, appends the item to the entry's
`items`, and — when the affected items share a worktree — runs **one** repair
round for the class, as a `FIX · <class>` lane or the first affected item's live
worker, recorded on each affected item's `fixes` round with that lane's `id`. A
shared lane is priced once, because both runtimes' retros count a session once.

Each affected item still gets its own re-review of the repair's delta: a CLEAN
verdict is about an item, not about a class. What is shared is the diagnosis and
the brief, never the verdict — and items that do not share a worktree still
share the diagnosis, each running its own repair from the recorded brief rather
than deriving it again.

A class that comes back after its repair is not another round — it is the run's
finding about the plan, and it belongs to the retro with the same weight as a
repeated freeze.

## Ponytail fixes

A ponytail finding's fix is re-checked by the next ponytail pass. It skips the fresh-eyes review only when its diff adds no executable behaviour — a pure deletion, a comment, a formatting change. A fix that adds or changes behaviour, state or a contract surface gets a fresh-eyes review of the fix delta before the item settles, and that pass does not consume the findings cap. That review, and the fix round it reads, are recorded under the pass that opened them — `ponytail[].fix` and `ponytail[].fix.review` ([ledger.md](ledger.md)) — because a pass that keeps them only in prose is work no retro can price. A ponytail note that names a defect is a finding, not a preference.

## A finding that contradicts the spec

When a review or ponytail finding conflicts with the approved manifest or the tracker spec, that is not a fix round. Quote the finding and the spec clause it contradicts, record it as a follow-up, and do not settle the item `done` — it is `blocked` with `cause.code: spec_conflict`, and that block is the operator's to adjudicate. The check is made when the finding arrives, **before the next fix round is spawned**: a round spent on code the spec says must not change is a round that cannot converge, and it ends at the cap with the wrong code and the wrong operator instruction. `land` and `unattended` still open the PR and do not merge, so the adjudication arrives after the PR is open. An adjudication with no spec citation is a skipped fix round.
