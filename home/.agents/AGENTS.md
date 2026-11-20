# Global Conventions

## PySpark Imports

Import PySpark functions by name (`from pyspark.sql.functions import col, when`), never via the module alias. Enforced by linter where configured.

## Bar
- Root cause only: a fix that leaves a sibling caller broken is not done.
- Done means demonstrated: every modified file's tests run (skipped, deselected or xfail is not a pass; report the counts), behavior verified, not just code written. Name what you did not check.
- Skepticism over agreement: critique objectively, flag anything you're not confident about.
- Bugs are fixed autonomously end-to-end: logs, errors, failing CI — no hand-holding requested.
- Replacements delete what they replace: no compat layers, fallbacks, or dead paths left behind.
- When a working solution exists, simplify in place, in the code the task touches: delete dead helpers, over-abstractions, and duplicated logic. Don't rebuild — the tested behavior is the oracle, and a clean rewrite that loses an edge case is worse.
- Minimum code for the task: no speculative features, options, abstractions or "for later" code. Name what you left out in one line.
- Before writing new code, look for an existing helper, component or pattern and use it the way the surrounding code does. List the callers, tests and config your change must reach.
- Follow the codebase's conventions — its layers, names, error handling — even when you disagree; a comment beside the code is not a convention.
- When instructions, docs and code conflict, name the conflict and which side you followed. Never blend them.
- A test is a claim about behavior: it must fail on that behavior's regression and for no other reason — one that breaks on a refactor, asserts a private field or a call count, guards a removed feature's absence, or passes on buggy code proves nothing. If another test guards that behavior, the copy is deleted, not written.
- If a command, type check or test can answer a question, run it instead of reasoning about it.
- State the assumptions you made in the reply; ask only when an ambiguity changes the outcome.
- Broken windows: lint errors, test failures, and flakiness get fixed on sight, even when unrelated to the current task. That means fixing what is broken, not restyling or refactoring working code next to your change.
- Corrected twice on the same mistake → run `/retro`. One correction is a fix, two is a class.
- Before you add code for a race condition or security edge case that is unlikely or purely hypothetical, tell me exactly what would go wrong, how likely that is, and how much complexity the extra code adds, in words a 10-year-old could understand. Then wait for my OK.
- End any turn that reports on long-running or delegated work with a short status: **Goal**, **Done**, **Next**, **Needs you** (or "nothing").

## Comments

- A comment is the exception: it names a constraint the code cannot — the vendor that guesses its own unit, the shape of the data, the ordering a protocol requires — two when the quirk needs an example; docstrings spend the same budget.
- The code says what it does: a comment that says it again, restates the test, or justifies the line just written is deleted, not shortened.
- A decision is not a comment: the choice and what it beat go to the ADR or `CONTEXT.md`, the reasoning to the PR body. The comment points — `# ADR 0005: saves stay in Delta.`
- A workaround is a fix you skipped: rename, extract or type it until no comment is needed.
- State a rationale once, where it is computed; eleven paraphrases are eleven places to go stale, so others name that function.
- A test comment names the trap the test name cannot. A comment the code has moved past dies with that change.

## This machine

- macOS ships BSD tools: bytes and whitespace are `sed -n l` or `od -c`; `cat -A` and `sed ,+N` ranges are GNU and fail here.
- Checkouts: `~/personal_workspace/*` are personal, `~/workspace/*` work — look there before guessing a path.
- The shell already starts in the project directory: `cd` only to reach another checkout.

## Ports
- `8765` is the attention dashboard (`~/personal_workspace/attention-dashboard`) — leave it running. To restart it, `./attention restart` from that checkout, which is what the board's own button runs; a kill by pid or port (`lsof -ti tcp:8765 | xargs kill`) takes the board down and looks like a crash. Kill your own preview server by the pid you started, or use a free port.

## Git

- Run `git push` only when explicitly asked.

### History — Never Rewrite Pushed Commits

A pushed commit is shared state: someone may have branched from it, reviewed it, or linked it. Amending or rebasing it rewrites history that others may already hold.

- Commit a fix on top: a new commit is the default, even when it would be tidier folded into the previous one.
- Reach for history rewriting only when it is the only way: a secret committed and not yet public, a commit that must not exist on a protected branch, or a branch you are certain nobody else has.
- Even then, ask first and say which commits would be rewritten and why the new-commit route does not work. Never run `--force` to get past a rejected push.
- `--force-with-lease`, never bare `--force`, and only after that yes.

### Commit Messages — Conventional Commits

Format: `<type>: <description>` — types: `build`, `chore`, `ci`, `docs`, `feat`, `fix`, `perf`, `refactor`, `revert`, `style`, `test`.

Ticket number goes in the description: `refactor: RBT-778 move …`, not `RBT-778: move …`.

### Pull Requests

When asked to open a pull request, read and follow the `pr` skill before writing the body. The body carries the reasoning the code no longer repeats — what you rejected, what you measured, what you could not check — under Summary, since the template has no section for it.

Before `gh pr create`, find the base branch that shows only your commits ahead (`git log --oneline develop..HEAD`, also `main`/`master`); don't assume `main`.

### AWS Credentials / Git Push

AWS sessions expire silently, and when they do `direnv`, the repo hooks and the push all fail with messages that never name the cause. Before pushing — or committing in a repo that has an `.envrc` — run `~/.agents/scripts/aws-check`. Exit 1 means the session for that repo's `AWS_PROFILE` is dead: stop and ask the user to run `aws sso login --sso-session lm-global`, then retry. A `DENIED` line instead of `STALE` means the profile's `sso_role_name` in `~/.aws/config` is not a role the user holds, and no login fixes that: report it. Exit 2 means it could not tell: push and report the real error. The same login covers `git push` failing with `AWS credentials: Missing suitable credentials`.

## Grill Sessions

When running /grill-with-docs or /grilling: interview only. Never implement code, skill, or config edits during the session — capturing CONTEXT.md / ADR docs inline is allowed. When the frontier empties, summarize the settled decisions and hand off to /to-spec or /to-tickets. Never implement directly.
