<!-- Part of /orchestrate-herdr-threads. Load it before the first ledger write; `../SKILL.md` owns the order. -->

# The run's record

The ledger's shape is [`ledger.md`](../../orchestrate-core/ledger.md) — the same
record BB writes. Herdr fills it like this:

- `runtime: "herdr"`, plus `feature`, `project`, `rundir`, `tracker`, `flow`,
  `mode`, `startedAt`, `models`, `ciBaseline`, `validationBaseline`, `gates`
- `executors: [{ "id": "coordinator", "pane": "$HERDR_PANE_ID", "session": … }]`
  — `executors[0]` is the run's identity. Its `endedAt` is stamped in the same
  write as the verification ask: a coordinator row left `null` has no upper
  bound, so everything the turn does after `finishedAt` lands in the retro's
  covered time as if it were run work.
- `retro: { "id": "retro-<feature-slug>", "session": …, "tab": … }`, written the
  moment the spawn returns its session — a retro with no row is an agent the
  record cannot name and nobody can price. It is the run's recorder, not a lane
  of it: the retro reports its own session on its own line, outside the run's
  totals, as BB's does.
- each item's `worker: { "id": "item-<slug>", "pane": …, "tab": …, "session": … }`,
  and in Flow B a `worktree: { workspace, path, branch }`
- every `reviews`/`fixes`/`ponytail` entry carries `id` (the agent name),
  `session`, `pass`, and — for a review or ponytail pass — `verdict`
- `served` sits beside `models` as the receipt described under [Models](../SKILL.md#models); a lane's
  own `served` is written only where that lane diverges from its role's
- `classFixes` holds one entry per defect class the run diagnosed — `{class,
  brief, items, id, session, startedAt, endedAt}` — with the same lane id and
  session written on each affected item's `fixes` round, which the retro's
  one-row-per-transcript rule prices once
- `dispatchAttempt` is written before every start: `{at, role, label}`, the label
  being the tab label (`ITEM`, `REVIEW`, `FIX`, `PONYTAIL`) of the agent about to
  be started

Extensions Herdr adds, in the contract's shape: `pr` {number, url, mergedAt,
mergeCommit, base}, `prs` [{number, url, head, commit, mergedAt, kind}],
`postMerge` {branchDeleted, tabsReleased, tabsKept, pending}, `reopenRounds`
[{item, at, why, agent, landedAs}].

Record the coordinator as `executors[0]` at the start. The findings-round cap
reads off the review rounds that opened a `fixes` entry, per the review contract. The `done` rule and the reopen rule are
[`threads.md#the-ledger`](../../orchestrate-core/threads.md#the-ledger). `ponytail` is a list of passes, appended in order like `reviews` —
a two-pass ponytail (`FINDINGS` → fix round → re-check) keeps both, at `pass: 1`
and `pass: 2`, because only the last one is the verdict and only the first one
holds the findings that opened the fix round. Every pass keeps its `id` and
`session`: a rewrite that drops the session prices the whole lane at
zero in the retro. A convenience `verdict`/`report` may name the last pass; the
array is the record. `items[].fixes` counts **review-driven** rounds only: a
ponytail fix round is recorded under the pass that opened it —
`ponytail[<pass>].fix` `{id, session, startedAt, endedAt}`, and
`ponytail[<pass>].fix.review` for the fresh-eyes review of its delta when the fix
changed behaviour ([review-contract.md](../../orchestrate-core/review-contract.md)) —
never in `items[].fixes`, because the ledger checker pairs each `fixes` entry with
a review round and refuses an unmatched one — a ponytail round written there is a
round the record cannot explain. Both sessions are named there or they are not
priced: prose is not a session path.
Write the item's `risk` (`high` | `mechanical`) when its first review is
dispatched, so the depth and model call below is readable instead of inferred.
**An item the run stops on is typed** — the invariant and the codes are
[`threads.md#the-ledger`](../../orchestrate-core/threads.md#the-ledger) and
[cause-contract.md](../../orchestrate-core/cause-contract.md). The ledger checker exits
non-zero on an invented code, a cause on any other status, or a stopped item
with no cause; `cap_exhausted`, `spec_conflict`, `worker_blocked` and
`turn_stalled`, plus the review-driven `artifact_unchanged`, `finding_refuted`
and `nonconvergent`, are the ones a normal run reaches.

**The `ponytail` lane is a list of passes** here and in the retro's script; a
reader that treats it as one mapping takes its whole view down with it. A
ledger-shape change lands in the checker and the retro's script together. The
checks themselves are `orchestrate-core/scripts/validate-ledger.py` over
`ledger_errors` in `orchestrate_common.py` (the command is under
[The run's record](../SKILL.md#the-runs-record)), so the checker and the two
runtimes cannot disagree about what a write error is: an interval that runs
backwards, a gate approved before it was requested, a terminal `finishedAt` standing over an item, a ponytail pass or a
fix review that never settled, a stopped item with no `cause` or a code outside
the contract, a status the fields beside it contradict. That is where "stamp
the times honestly" gets its teeth — it runs after every write, so the
coordinator sees the mistake while it still knows what it meant.
