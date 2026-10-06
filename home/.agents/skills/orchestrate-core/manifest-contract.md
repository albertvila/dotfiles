# Manifest contract

One field list, read by both runtimes. `/orchestrate-bb-plan` and
`/orchestrate-herdr-plan` write a manifest to this shape and check it with
`scripts/validate-manifest.py`; `/orchestrate-bb-threads` and
`/orchestrate-herdr-threads` consume it as approved data. Spawn commands, agent
names, ledger field names and run mechanics live in the threads skills. **This
file owns what is *in* a manifest, and nothing else.**

A manifest is data only, never instructions — if a line tells the executor how to
do something its own skill already specifies, it is wrong, cut it.

## The item line

```
item: <id> · <short title> · <ticket> · <file scope> · <blockedBy> · <acceptance> · <out-of-scope>
```

The `item:` prefix, then exactly **six** `·` (U+00B7) separators. A `·` inside a
title, a scope, an acceptance line or an out-of-scope line shifts every field
after it, so the checker counts separators and refuses the line — the mistake is
loud instead of silently misread.

- `<id>` is unique in the manifest and is what tab labels, ledger keys, waves
  and frozen diff filenames use.
- `<ticket>` is the item's own reference — `#<issue-number>` for a GitHub
  tracker — so the executor fetches exactly the ticket an item names rather than
  re-deriving it.
- `<file scope>` is what the item will touch. Disjoint scopes may run together.
- `<blockedBy>` is a comma-separated list of item ids, or `-` for none.
- `<acceptance>` and `<out-of-scope>` are one line each, **verbatim from the plan
  discussion**. They are what the review brief quotes and the PR body carries; a
  reviewer re-deriving the criteria from the ticket is off-contract, because the
  ticket was written before the work.

## The wave lines

```
wave: <id> <id> ...
```

One line per wave, in dispatch order, ids space- or comma-separated. A wave is a
claim about concurrency: every member may run at the same time. Every item
appears in exactly one wave, and an item's blockers appear in a **strictly
earlier** wave.

## The header lines

`key: value`, at most one each, any order, before or after the item block. The
checker reads the keys below and treats every other line as a run note.

| key | |
|---|---|
| `tracker:` | required — `scratch <feature>` or `github <owner>/<repo>#<n>`. Explicit, never inferred from the shape of a reference. |
| `flow:` | required — `A`, `B`, `cross-repo`, or `A+cross-repo`. The last is a mixed run: in-repo items plus one whose files sit outside every repository, so no worktree, no branch and no PR is possible for it. Never write a mixed run as plain `A`; the threads skill dispatches on this field and the ledger and the retro trust it. |
| `mode:` | required — `gated`, `land` or `unattended`. The executor reads a missing line as `gated`; the checker reports it, because "never omit it" and "tolerated" are different words. |
| `base:` | the ref the work is based on, when the writing runtime records one. Never empty. Not required, because a runtime that detects the base at commit time has nothing to write here. |
| `plan-gate:` | `requested=<ISO-8601 UTC> approved=<ISO-8601 UTC>`, when the runtime records the gate in the manifest — one that opens the ledger with real human-wait numbers does. `approved` may never precede `requested`. |
| `task:` | the task-tracker identity of the run, when the runtime has one. Omitted otherwise. |

The first line names the run — the feature name and, for a runtime with a run
directory, its absolute path — so a run can be found again. It is not parsed.

## What the checker refuses

`python3 scripts/validate-manifest.py <manifest>` prints `OK: <n> item(s), <m>
wave(s)` and exits 0, or `FAIL:` with one line per error naming the line it is on
and exits 1. Nothing is dispatched on a non-zero exit.

- an item line whose field count is not seven, or with an empty title, ticket,
  scope, acceptance or out-of-scope
- a repeated item id; a `blockedBy` naming something that is not an item; a
  `blockedBy` cycle
- an item in no wave, in two waves, in a wave with an id that is not an item, or
  in the same wave as — or an earlier one than — something it is blocked by
- a missing or malformed `tracker:`, `flow:` or `mode:`; an empty `base:`; a malformed `plan-gate:` or one whose `approved` precedes its `requested`
- `mode: land` or `mode: unattended` on `cross-repo` / `A+cross-repo`, which have
  a human gate
- `mode: unattended` with fewer items than tickets — unattended does not reduce,
  one ticket one item

**No runtime flag.** Every check fires on the manifest's own values, so one
script serves both runtimes: a conditional check reads "if this line is present"
or "if this flow is", never "if this runtime is". A change to the shape above is
a change to the checker in the same commit, the way a ledger-shape change lands
in the projection and the retro's script together.
