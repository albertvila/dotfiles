# The run ledger

One record, written by both runtimes. The storage path is the runtime's own — BB
writes `<dataDir>/thread-storage/<executors[0].id>/orchestration.json`, Herdr
writes `<worktree>/.herdr-runs/<feature>/orchestration.json` — and the contents
are this shape. A reader never needs to know which runtime wrote it, and no
older shape is read: there is no back-compat.

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
  "ciBaseline": [], "validationBaseline": {},
  "executors": [
    { "id": "<handle>", "pane": null, "session": null, "startedAt": null, "endedAt": null }
  ],
  "gates": { "plan": { "requestedAt": null, "approvedAt": null, "auto": null },
             "commit": { "requestedAt": null, "approvedAt": null, "auto": null } },
  "items": { "<id>": { /* item, below */ } },
  "ponytail": [
    { "pass": 1, "id": "<handle>", "session": null, "verdict": "CLEAN|FINDINGS",
      "report": null, "startedAt": null, "endedAt": null }
  ],
  // Runtime extensions, in this shape, never merged in:
  //   bb: "task" (BB Task key), "pr"
  //   herdr: "rundir", "pr" {number,url,mergedAt,mergeCommit,base}, "prs" [...],
  //          "postMerge" {branchDeleted,tabsReleased,tabsKept,pending}, "reopenRounds" [...]
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
  "worker": { "id": "<handle>", "session": null, "worktree": null,
              "startedAt": null, "endedAt": null },
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
    { "pass": 1, "id": "<handle>", "session": null, "startedAt": null, "endedAt": null }
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
- `attempts` is **not** stored — the dagr projection derives it from
  `reviews`/`fixes`.
