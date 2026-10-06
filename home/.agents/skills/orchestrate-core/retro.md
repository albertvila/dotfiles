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
  edits.

The report is done when every finding is explained or marked **unexplained**, and
every proposal names the section of the threads skill it would change plus the
evidence that motivates it.
