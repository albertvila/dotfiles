# Cause contract

One vocabulary, read by both runtimes. An item a run stops on carries a `cause`,
and its code comes from this closed set — so the retro explains a run instead of
re-deriving why each item stopped, and the operator's next move is a lookup
rather than a reading exercise.

The field lives in each runtime's ledger, on the item:

```jsonc
"cause": { "code": "worker_blocked", "detail": "the worker asks which retry budget applies" }
```

- `code` — one of the codes below. Not a sentence, not a slug the coordinator
  invented.
- `detail` — **one line, this instance's specifics.** The code names the class,
  the detail names what happened here. Both are required: a code with no detail
  tells the operator which aisle the problem is in and nothing else.
- Present **iff** `status` is `blocked` or `failed`. A `todo`, `running` or `done`
  item carrying a `cause` is a write error, and so is a `blocked` or `failed` item
  without one. Both runtimes' ledgers are held to that: the Herdr projection
  checks it on every ledger write, and both retro scripts read it.

## The codes

| code | the path that ends the item | the operator's move |
|---|---|---|
| `worker_blocked` | the worker reported `BLOCKED`, or sits at a dialog the coordinator will not answer out of the approved manifest | answer it |
| `turn_stalled` | a turn ended with no report and the same agent stalled again when re-prompted | inspect the pane and the transcript |
| `artifact_unchanged` | the fix round settled without moving the frozen diff, so the re-review was not spawned | inspect why the fix produced nothing |
| `cap_exhausted` | the item's findings rounds reached the cap — three — and a fourth would have been needed | adjudicate the disagreement |
| `spec_conflict` | a finding contradicts the approved manifest or the tracker spec | adjudicate the spec |
| `model_unavailable` | the role's model is missing from `pi --list-models`, was refused at start, or died on its first turn | name a model |
| `dispatch_failed` | the item's agent could not be started — `herdr agent start` or `bb thread spawn` exited non-zero | fix the environment |
| `unclassified` | none of the above names it | treat it as a finding — see below |

An item whose only blocker is an unmet dependency is **not** in this set: it stays
`todo`, and both runtimes render that as a wait rather than a block. These codes
are for an item the run itself stopped on.

A pause **before a merge** — a red check the change caused, a head that moved,
missing `lm` or AWS credentials — is not an item cause either. By then the item
has settled and the pause is the run's, so it belongs to the run summary and not
to the ledger.

`unclassified` is a last resort and it is a **finding**: a run that needed it has
a failure path neither skill names. It exists so that a coordinator never invents
a code — an invented code is worse than an honest `unclassified`, because the
retro's lookup would miss it silently while the ledger still looked typed.

## Where it is read

[review-contract.md](review-contract.md) owns what a review is;
[run-mode.md](run-mode.md) owns the mode and the merge; this file owns why an item
stopped. The retro's report pairs every code present with the operator's move
above, and reports an item with no cause, or an `unclassified` one, under *What to
fix*. A change to this set is a change to both runtimes' ledger sections and both
retro scripts in the same commit.
