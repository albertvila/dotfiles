# Run mode

The manifest line `mode:` is `gated`, `land`, or `unattended`. A missing line is `gated`. The threads skill does not invent a mode. Both flags at once is a stop.

| mode | plan yes | commit yes | who merges |
|---|---|---|---|
| gated | required | required | Flow A: the operator. Flow B: this run, after that yes |
| land | required | skipped | this run, after green checks |
| unattended | skipped | skipped | this run, after green checks |

`unattended` does not reduce tickets. One ticket, one item. Reduction is the judgment the plan yes exists to check.

`land` and `unattended` are refused when the flow is `cross-repo` or `A+cross-repo`. Those shapes have a human gate. Stop and name the shape.

## Ledger

Write `mode` on the ledger before the first spawn. An automatic gate sets `requestedAt` and `approvedAt` to the same ISO-8601 UTC timestamp and `auto: true`. A human yes leaves `auto` unset. `approvedAt` is always a timestamp, never the word `auto`.

Also write `ciBaseline`, and per item `reviewedHead`: the sha the review and the validation passed on.

## CI baseline

Before the first worker, record the target branch's check-runs:

```sh
gh api "repos/<owner>/<repo>/commits/<target-sha>/check-runs" \
  --jq '.check_runs[] | {name, conclusion}'
```

Store that list as `ciBaseline`. An empty list means every later red is caused. A check whose name concluded failing there is inherited, reported, and not a reason to pause.

## Validation

The worker's test report is a claim. Before the commit gate, run the command the worker named.

1. The first time that command string appears, run it in a detached worktree at the run's base sha. Record the exit code under `validationBaseline`.
2. Run it again in a scratch worktree that is that base plus this item's files only. Copy changed and untracked files from the item worktree. Do not copy other items' uncommitted files.
3. Base exit was 0 and the item exit is non-zero: that is a findings round, not a note. Do not open the commit gate.
4. Base exit was already non-zero: report it. Do not blame the item for that same command.

Flow A, once every item has passed: run the command on a scratch copy of the whole dirty tree. Non-zero pauses the run. Do not guess which item.

## Flow B bases

An item with `blockedBy` stays `todo` until those items' PRs are merged to the target. Fetch, then create its worktree from that updated target (`--base-branch origin/<target>` on BB, `--base <target>` on Herdr). Do not branch it from the pre-merge target and rebase later. Items with no blockers start together from the target.

## Commit and merge

`gated` asks for the commit message and waits. `land` and `unattended` do not ask. The message is a conventional commit built from the item titles, written into the ledger. Then commit and push. Flow A creates the run branch before anything is pushed: a bare push of `HEAD` lands the commit on the base.

Record `reviewedHead` as the sha just pushed. Merge only when `gh pr view --json headRefOid` equals that sha, checks are green net of `ciBaseline`, and the PR is not a draft (`gh pr ready` if it is).

```sh
gh pr merge <url> --<method> --match-head-commit <reviewedHead> --delete-branch
```

`<method>` is the first the repo allows of squash, merge, rebase. Do not use `bb environment pull-request merge`. It cannot pin the head.

Pause, and do not merge, on any of these: a red check the change caused, a head that moved, a spec-conflict finding, a findings cap, a `BLOCKED` worker, a model that did not start, missing `lm` or AWS credentials. Do not revert. Name the sha and stop.

After a merge, if the target's new check-runs add a failure that is not in `ciBaseline`, pause and name the merge commit. Do not revert it.

`finishedAt` for `land` and `unattended` waits until that merge has happened, or the run is paused. An open PR is not finished.
