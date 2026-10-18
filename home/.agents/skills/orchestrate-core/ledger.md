# The run ledger

One record, written by both runtimes. The storage path is the runtime's own — BB
writes `<dataDir>/thread-storage/<executors[0].id>/orchestration.json`, Herdr
writes `<worktree>/.herdr-runs/<feature>/orchestration.json` — and the contents
are this shape. A reader never needs to know which runtime wrote it, and no
older shape is read: there is no back-compat. The one reader is
`scripts/ledger_read.py`: a ledger plus each runtime's telemetry lanes become
the shared run record (`schemaVersion` 2), so a BB record and a Herdr record are
comparable field for field.

The write invariants (write-as-you-go, the typed cause, the `done` rule,
`finishedAt`) are [threads.md](threads.md#the-ledger); the cause codes are
[cause-contract.md](cause-contract.md); this file owns the fields.

## Run

```jsonc
{
  "runtime": "bb" | "herdr",
  "feature": "<feature>",
  "project": "<project or repo name>",
  "tracker": "scratch <feature>" | "github <owner/repo>#<parent>",
  "flow": "A" | "B" | "cross-repo" | "A+cross-repo",
  "mode": "gated" | "land" | "unattended",
  "startedAt": "<ISO-8601 UTC>", "finishedAt": null,
  "models": { "worker": "…", "code-review": "…", "ponytail": "…" },
  // what actually served each role, read from the lane's own record; a role or
  // lane whose record names no model is left out and reads as unverified
  "served": { "worker": … , "code-review": … , "ponytail": … },
  "ciBaseline": [], "validationBaseline": {},
  "executors": [
    { "id": "<handle>", "pane": null, "session": null, "startedAt": null, "endedAt": null }
  ],
  "gates": { "plan": { "requestedAt": null, "approvedAt": null, "auto": null },
             "commit": { "requestedAt": null, "approvedAt": null, "auto": null } },
  "items": { "<id>": { /* item, below */ } },
  // one entry per defect class the run diagnosed and repaired, recorded once
  // however many items it reached (review-contract.md)
  "classFixes": [
    { "class": "<kebab-case>", "brief": "<one line, reused verbatim>",
      "items": ["<id>", …], "id": "<handle>", "session": null,
      "startedAt": null, "endedAt": null }
  ],
  "ponytail": [
    { "pass": 1, "id": "<handle>", "session": null, "verdict": "CLEAN|FINDINGS",
      "report": null, "startedAt": null, "endedAt": null,
      // the round this pass's findings opened, and the fresh-eyes review of its
      // delta when the fix changed behaviour (review-contract.md)
      "fix": { "id": "<handle>", "session": null, "startedAt": null, "endedAt": null,
               "review": { "id": "<handle>", "session": null,
                           "verdict": "CLEAN|FINDINGS", "report": null,
                           "startedAt": null, "endedAt": null } } }
  ],
  // Runtime extensions, in this shape, never merged in:
  //   bb: "task" (BB Task key), "pr", "runBranch" (Flow A),
  //       "retro" {id, session, startedAt} when the manager spawned one,
  //       "notes" [one line per plan-time note the coordinator carries],
  //       "wholeTree" {at, suites, scope} (run-mode.md § Validation)
  //   herdr: "rundir", "retro" {id,session,tab,startedAt},
  //          "pr" {number,url,mergedAt,mergeCommit,base}, "prs" [...],
  //          "postMerge" {branchDeleted,tabsReleased,tabsKept,pending}, "reopenRounds" [...]
  //   `gates.plan` owns the plan gate. A second top-level copy of it (an old run
  //   wrote `planGate`) is drift, not shape — a reader cannot tell which one is
  //   authoritative, and both can be right.
}
```

**`executors` is ordered, and `executors[0]` is the run's identity** — where the
ledger lives, and the handle the retro is given. On BB each entry is a manager
thread, the first plus one successor per context exhaustion. On Herdr there is
one, the coordinator. This is the `executors` field BB used to call
`managerChain` and Herdr `coordinator`.

## Item

```jsonc
{
  "title": "…", "slug": "…", "ticket": "<ref>",
  "criteria": "…",                     // the manifest's acceptance line, verbatim
  "outOfScope": "…",                   // the manifest's out-of-scope line, verbatim
  "risk": "high" | "mechanical",       // the review's depth class — see the bullets
  "worker": { "id": "<handle>", "session": null, "worktree": null,
              "startedAt": null, "endedAt": null },
  // the last dispatch this item began, written before the spawn and left in
  // place: the role plus the label are how a resume finds the lane an
  // interrupted spawn may already have produced (threads.md)
  "dispatchAttempt": { "at": "<ISO-8601 UTC>", "role": "worker", "label": "<label>" },
  "status": "todo" | "running" | "done" | "failed" | "blocked",
  "blockedBy": [], "prUrl": null, "reviewedHead": null,
  "startedAt": null, "endedAt": null,
  "unblock": null,                     // only when a block is not a dependency's to clear
  "cause": null,                       // {code, detail} — cause-contract.md
  "reviews": [
    { "pass": 1, "id": "<handle>", "session": null, "verdict": "CLEAN|FINDINGS",
      "report": null, "startedAt": null, "endedAt": null }
  ],
  "fixes": [
    { "pass": 1, "id": "<handle>", "session": null, "startedAt": null, "endedAt": null,
      // only when the round returned REFUTED: with the code that disproves the
      // finding (review-contract.md) — the item is then blocked on it
      "refutation": { "finding": "<the finding, one line>", "evidence": "<file>:<line> \"<quote>\"" } }
  ],
  "commitGate": null                   // Flow B per-item gate
}
```

**`id` is the work unit's identifier, and the value is the one thing that varies
by runtime** — the worker/reviewer thread id on BB, the pi agent name on Herdr.
The field name does not: everything around it is identical.

- `worker.worktree` — BB's Flow B `envId`, or Herdr's
  `{workspace, path, branch}`.
- `reviewCount` is `len(reviews)` and the findings-round cap reads off the review
  rounds that opened a `fixes` entry ([review-contract.md](review-contract.md)).
  BB's old `reviewCount`/`reviewThreadId`/`fixRounds` fields are gone.
- `criteria` and `outOfScope` are quoted verbatim; they are what a review checks.
- `status` moves only along the transitions in
  [threads.md#the-item-lifecycle](threads.md#the-item-lifecycle), and
  `scripts/validate-ledger.py` refuses a write the record contradicts — a status
  the fields beside it disagree with, a `done` that never carried a clean review.
- `risk` is the class the review's depth is scaled to
  ([review-contract.md](review-contract.md)) and — in a runtime whose skill carries
  the rule — which reviewer model the item's passes get. It is written when the
  item's first review is dispatched. A run that never wrote it leaves it out; the
  retro then reports the model choice as unexplained rather than guessing one.
- `served` is the **receipt**, not the request: `models` is what the run asked
  for, `served` is what the lanes' own records name. It is keyed by role and
  written when that role's first lane settles on a model the lane's record names,
  and a lane whose record names a different one carries its own `served` on its
  entry. A role or lane the record cannot name is **absent**, never guessed — an
  absent `served` reads as unverified, and the retro says so instead of pricing an
  intention as a fact.
- `classFixes` is run-level and not per item: one entry is one diagnosis, however
  many items the class reached ([review-contract.md](review-contract.md)). Each
  affected item's `fixes` round still names the lane that ran — a shared lane is
  named by several items and priced once, since both retros count a session once.
- `dispatchAttempt` is the one write that **precedes** the action it records: the
  coordinator writes `{at, role, label}` before it spawns, so a manager that dies
  between the spawn and the lane's own write leaves a record naming what it may
  already have started ([threads.md](threads.md#the-ledger)). It is not cleared —
  it is the item's last dispatch, and a reader compares it with the lanes beside
  it rather than treating it as in-flight.
- A ponytail pass records the round its own findings opened under the pass —
  `ponytail[].fix`, and `ponytail[].fix.review` for the fresh-eyes review a
  behaviour-changing fix gets ([review-contract.md](review-contract.md)). Neither
  belongs in `items[].fixes`: that array is review-scoped. Both are sessions like
  any other, and a lane whose sessions are not written here is a lane no retro can
  price.
- `attempts` is **not** stored — a reader derives it from the `reviews` and
  `fixes` written beside it.
