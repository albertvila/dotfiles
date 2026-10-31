# Global Conventions

## PySpark Imports

Import PySpark functions explicitly, one name per function used:

```python
from pyspark.sql.functions import col, lit, when
col("x"), lit(None), when(...)
```

Enforced by linter where configured — the module-alias form is banned project-wide.

## Bar
- Root cause only: a fix that leaves a sibling caller broken is not done.
- Done means demonstrated: every modified file's tests run, behavior verified, not just code written. Name what you did not check.
- Skepticism over agreement: critique objectively, flag anything you're not confident about.
- Bugs are fixed autonomously end-to-end: logs, errors, failing CI — no hand-holding requested.
- Replacements delete what they replace: no compat layers, fallbacks, or dead paths left behind.
- Broken windows: lint errors, test failures, and flakiness get fixed on sight, even when unrelated to the current task.
- Corrected twice on the same mistake → run the `correct` skill. One correction is a fix, two is a class.
- Before you add code for a race condition or security edge case that is unlikely or purely hypothetical, tell me exactly what would go wrong, how likely that is, and how much complexity the extra code adds, in words a 10-year-old could understand. Then wait for my OK. Don't quietly widen the scope to guard against problems that only exist in theory.
- End any turn that reports on long-running or delegated work with a short status: **Goal**, **Done**, **Next**, **Needs you** (or "nothing").

## Ports
- `8765` is the attention dashboard (`~/personal_workspace/attention-dashboard`) — leave it running: never kill it, by pid, port or name (`lsof -ti tcp:8765 | xargs kill` takes it down and looks like a crash); kill your own preview server by the pid you started, or use a free port.

## Git

### Commits — Always Ask First
- Show the intended commit message and file list, then wait for a clear "yes" before running `git commit`.
- Run `git push` only when explicitly asked.
- No exceptions across repos, branches, or situations.

### Commit Messages — Conventional Commits

Format: `<type>: <description>` — types: `build`, `chore`, `ci`, `docs`, `feat`, `fix`, `perf`, `refactor`, `revert`, `style`, `test`.

Ticket number goes in the description, not the type:

```
# Wrong
RBT-778: move exception classes to shared/

# Correct
refactor: RBT-778 move exception classes to shared/
```

### Pull Requests

When asked to open a pull request, read and follow the `pr` skill before writing the body.

**Detect the base branch.** The `Main branch` field in gitStatus defaults to `master`/`main` and is wrong for repos that integrate via `develop`. Before `gh pr create`, check which branch shows only your feature commits ahead:

```bash
git log --oneline develop..HEAD   # also master..HEAD / main..HEAD
```

Open the PR against that branch, not the assumed default.

### AWS Credentials / Git Push

AWS sessions expire silently, and when they do `direnv`, the repo hooks and the push all fail with messages that never name the cause. Before pushing — or committing in a repo that has an `.envrc` — run `~/.agents/scripts/aws-check`. Exit 1 means the session for that repo's `AWS_PROFILE` is stale: stop and ask the user to refresh it in **Strider**, our in-house tool, then retry. Exit 2 means it could not tell: push and report the real error.

The same refresh applies when `git push` fails with `AWS credentials: Missing suitable credentials`.

## Grill Sessions

When running /grill-with-docs or /grilling: interview only. Never implement code, skill, or config edits during the session — capturing CONTEXT.md / ADR docs inline is allowed. When the frontier empties, summarize the settled decisions and hand off to /to-spec or /to-tickets. Never implement directly.
