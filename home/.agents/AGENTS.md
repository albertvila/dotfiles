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
- A new or changed test must fail without the change; one that passes on buggy code proves nothing.
- If a command, type check or test can answer a question, run it instead of reasoning about it.
- State the assumptions you made in the reply; ask only when an ambiguity changes the outcome.
- Broken windows: lint errors, test failures, and flakiness get fixed on sight, even when unrelated to the current task. That means fixing what is broken, not restyling or refactoring working code next to your change.
- Corrected twice on the same mistake → run the `correct` skill. One correction is a fix, two is a class.
- Before you add code for a race condition or security edge case that is unlikely or purely hypothetical, tell me exactly what would go wrong, how likely that is, and how much complexity the extra code adds, in words a 10-year-old could understand. Then wait for my OK.
- End any turn that reports on long-running or delegated work with a short status: **Goal**, **Done**, **Next**, **Needs you** (or "nothing").

## Comments

- One line for the constraint the code cannot change — the vendor that guesses its own unit, the shape of the data, the ordering a protocol requires — two when the quirk needs its example. Docstrings spend the same budget, saying what the thing does.
- A surprise in our own design is a rename or an ADR, not prose: a justification either names a constraint we cannot change or it goes, and six lines cut to two is the same alibi, shorter.
- Everything else has a home: the decision in an ADR, the reasoning in the PR body. The comment states it once and points — `# ADR 0005: saves stay in Delta.`
- State a rationale where it is computed: eleven paraphrases of one decision are eleven places to go stale, so the other sites name that function.
- A test comment states the trap its name cannot: the fixture that makes two rows collide, not what the assert checks. The comment dies with the code it explained.
- `~/.agents/scripts/comment-check --base <branch>` before a PR: it names every block over the budget.

## Ports
- `8765` is the attention dashboard (`~/personal_workspace/attention-dashboard`) — leave it running: never kill it, by pid, port or name (`lsof -ti tcp:8765 | xargs kill` takes it down and looks like a crash); kill your own preview server by the pid you started, or use a free port.

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

AWS sessions expire silently, and when they do `direnv`, the repo hooks and the push all fail with messages that never name the cause. Before pushing — or committing in a repo that has an `.envrc` — run `~/.agents/scripts/aws-check`. Exit 1 means the session for that repo's `AWS_PROFILE` is dead: stop and ask the user to run `aws sso login --sso-session lm-global`, then retry. A `DENIED` line instead of `STALE` means the profile's `sso_role_name` in `~/.aws/config` is not a role the user holds, and no login fixes that: report it. Exit 2 means it could not tell: push and report the real error.

The login is not enough for the `lm` pre-push hook: `LM::Builder::API::Paws` reads `AWS_ACCESS_KEY_ID` and `~/.aws/credentials` and nothing else, so an SSO session is invisible to it and `git push` is refused with `AWS credentials: Missing suitable credentials` however fresh the login is. Push through `~/.agents/scripts/aws-env <command>`, which exports the session for one command: `aws-env git push -u origin <branch>`.

## Grill Sessions

When running /grill-with-docs or /grilling: interview only. Never implement code, skill, or config edits during the session — capturing CONTEXT.md / ADR docs inline is allowed. When the frontier empties, summarize the settled decisions and hand off to /to-spec or /to-tickets. Never implement directly.
