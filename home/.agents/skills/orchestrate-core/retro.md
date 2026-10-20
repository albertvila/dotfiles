# The retro phase

The retrospective contract shared by `/orchestrate-bb-retro` and
`/orchestrate-herdr-retro`. Two questions decide whether the retro was worth the
tokens: did it explain every number it printed, and did it end in an edit someone
can make. Each runtime's skill owns where its numbers come from (*Reading the
numbers*), its own failure catalogue, and the corpus the record is archived in.

## Report

The report has five sections. This file owns three of them; each runtime's skill
owns *Time per phase* and *Cost per model*, whose figures come from its own
records.

- **Execution plan** — the flow, the items in dispatch order with their
  blocked-by edges, and the wave structure the run actually followed. Note
  every place it diverged from the plan it approved.
- **What to fix** — one line per finding: what happened, the evidence, and the
  smallest change that prevents it next time.
- **Changes to the main skill** — ranked proposals, each naming the section it
  edits; at most three, and `no skill change is argued` when the rules explained
  the run.

The report is done when every finding is explained or marked **unexplained**, and
every proposal names the section of the threads skill it would change plus the
evidence that motivates it and the check that decides it landed.

## What earns a proposal

Default to **none**. As the rules settle, most runs diverge from them somewhere
and still argue no edit: say `no skill change is argued` and let the report end
there. A retro that always proposes trains its reader to skim it.

A candidate becomes a proposal only when all five hold:

1. **A defect of the rules, not of the run.** The run broke a written rule — that
   is a *What to fix* finding. The rules are silent or contradict each other —
   that is a candidate. A run's own wobble is neither.
2. **Not already answered in the corpus.** Search the corpus records
   (`runs/*/report.md`, `runs/*/run.json`) for the class *before* proposing. A
   class an earlier record proposed and marked applied is a **recurrence**, not a
   proposal: report it against that record, name what did not take, and propose
   the missing half — usually who writes it, who reads it, or what fails without
   it. A recurrence is the only evidence that an earlier fix was wrong, and it is
   worth more than a new idea.
3. **It names its check, and its saving.** One line each: the command, field or
   absence by which the next retro sees the change landed; and the minutes or
   dollars it would have saved in *this* run. `0m — a wrong number in every
   record` is a legitimate answer, but it is stated, not implied.
4. **A change that only prints another number pays for itself.** The retro's own
   output is what such a change costs on every future run, so in one run it earns
   an edit only as a recurrence, or as a defect that stopped the retro producing
   a figure it must print. A first wish for a new figure is an observation.
5. **Ranked, and at most three.** A fourth argument is still reported, as an
   observation with its evidence. Findings are never suppressed; only the ranked
   list of edits is capped.
