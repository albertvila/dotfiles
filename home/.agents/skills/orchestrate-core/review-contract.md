# Review contract

One review rule, read by both runtimes. The spawn commands, agent names and ledger field names live in each skill; this file owns what a review is, when it ends, and what a fix round costs.

## A finding is a defect

A **finding** is a defect in behaviour, in a named acceptance criterion, or a failure of a gate this run must pass (lint, typecheck, tests). Lint-gate failures are findings: they fail CI. A **nit** is everything else — a preference, a style choice the gate accepts, an observation with no gate behind it.

**Intent comes from the manifest, and it is the plan's.** The item's `acceptance` and `out-of-scope` lines are quoted into the review brief from the approved manifest; a criterion re-derived from the ticket at review time is off-contract, because the ticket was written before the work. The `out-of-scope` line bounds what a reviewer may require — a finding that the item omitted something it declared out of scope is not a finding. Work performed *beyond* that boundary is still reviewable: scope creep is a defect, not an exemption.

**The worker's account is a lead, not a verdict.** Every worker states its hardest decision, the alternatives it rejected, and what it is least confident about; the review brief quotes those lines. They are how a reviewer tells a deliberate choice from a wrong one — a rejected alternative that was correctly rejected is not a finding, and one that was wrongly rejected is. An item the worker flagged `UNSURE:` is checked harder, not excused: if the concern is real it is a finding like any other, and a `UNSURE:` line the reviewer cannot confirm in the code is reported unverifiable rather than accepted.

## CLEAN ends the loop

`VERDICT CLEAN` closes the item's review even when it carries non-blocking nits. Nits go to the operator in the run summary: they are not fixed in-run and never open a re-review. Only `VERDICT FINDINGS` opens a fix round.

Every review and ponytail report ends with `VERDICT CLEAN` or `VERDICT FINDINGS` as its first line, and findings are reported there — never recorded as follow-ups instead.

## The review thread does the pass itself

The review runs in the review thread, from its own context. Do not invoke the two-axis `/code-review` skill: its mandatory Standards and Spec subagents report their tokens nowhere the run can see, so the review goes unpriced and the verdict is not the reviewer's own. The review thread spawns no subagents at all.

Depth scales to the item's risk. A **high-risk** item — real state, logic, or contract surface (RPC schemas, fetch lifecycles, data scoping) — gets the full adversarial prompt in that one thread: every acceptance criterion verified in code, edge cases probed, test fixtures judged for genuine pinning. A **mechanical** item — deletions, renames, rendering-only, docs, config — gets a short pass over the frozen diff. A uniformly maximal checklist wastes 10–30 min per low-risk item; a uniformly minimal one misses the bug only a deep pass catches. An item whose criteria exceed what one thread can hold should have been split at plan time.

## Cap: 3 findings rounds per item

A **findings round** is a pass that returns `VERDICT FINDINGS`. A pass after a `VERDICT CLEAN` — a ponytail re-check, a gate-config change, a post-review change — does not consume the cap. The cap reads off the findings rounds, never off all passes: `fixRounds` in the BB ledger, the review rounds that opened a `fixes[]` entry in the Herdr ledger. A 4th findings round is never spawned: the item is `blocked` with `cause.code: cap_exhausted`, its findings are surfaced to the operator, and the rest of the frontier keeps moving.

**A re-review is scoped to the delta.** Its brief names what changed and only the earlier conclusions that change could have invalidated. A delta that changes no logic, state or contract surface (stylesheets, docs, renames) does not re-open the acceptance criteria at all. A re-check told to re-settle every earlier conclusion is the run's longest and most expensive agent, spent re-deriving a report it already wrote.

**A re-review is gated on the artifact having moved.** Each pass reads its own frozen diff, and the next pass is spawned only when the new freeze differs from the one the previous pass read. Identical bytes are not a new round: the fix settled without changing anything, so the item is `blocked` with `cause.code: artifact_unchanged`, its findings are surfaced, and the frontier keeps moving. Re-reading unchanged evidence spends one of the three findings rounds on a verdict that is already written.

## Ponytail fixes

A ponytail finding's fix is re-checked by the next ponytail pass. It skips the fresh-eyes review only when its diff adds no executable behaviour — a pure deletion, a comment, a formatting change. A fix that adds or changes behaviour, state or a contract surface gets a fresh-eyes review of the fix delta before the item settles, and that pass does not consume the findings cap. A ponytail note that names a defect is a finding, not a preference.

## A finding that contradicts the spec

When a review or ponytail finding conflicts with the approved manifest or the tracker spec, that is not a fix round. Quote the finding and the spec clause it contradicts, record it as a follow-up, and do not settle the item `done` — it is `blocked` with `cause.code: spec_conflict`, and that block is the operator's to adjudicate. `land` and `unattended` still open the PR and do not merge, so the adjudication arrives after the PR is open. An adjudication with no spec citation is a skipped fix round.
