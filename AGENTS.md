# AGENTS.md

## Working conventions

### Bar
- Root cause only: a fix that leaves a sibling caller broken is not done.
- Done means demonstrated: every modified file's tests run, behavior verified, not just code written.
- Skepticism over agreement: critique objectively, flag anything you're not confident about.
- Bugs are fixed autonomously end-to-end: logs, errors, failing CI — no hand-holding requested.
- Replacements delete what they replace: no compat layers, fallbacks, or dead paths left behind.
- Broken windows: lint errors, test failures, and flakiness get fixed on sight, even when unrelated to the current task.

### Git

**Commits — Always Ask First**
- Show the intended commit message and file list, then wait for a clear "yes" before running `git commit`.
- Run `git push` only when explicitly asked.
- No exceptions across repos, branches, or situations.

**Commit Messages — Conventional Commits**

Format: `<type>: <description>` — types: `build`, `chore`, `ci`, `docs`, `feat`, `fix`, `perf`, `refactor`, `revert`, `style`, `test`.

Ticket number goes in the description, not the type:

```
# Wrong
RBT-778: move exception classes to shared/

# Correct
refactor: RBT-778 move exception classes to shared/
```

**Pull Requests — Detect the Base Branch**

The `Main branch` field in gitStatus defaults to `master`/`main` and is wrong for repos that integrate via `develop`. Before `gh pr create`, check which branch shows only your feature commits ahead:

```bash
git log --oneline develop..HEAD   # also master..main..HEAD
```

Open the PR against that branch, not the assumed default.

**AWS Credentials / Git Push**

If `git push` fails with `AWS credentials: Missing suitable credentials`, stop and ask the user to connect their **Leapp** app to refresh AWS credentials before retrying.

## Agent skills

### Issue tracker

Issues live as local markdown files under `.scratch/<feature-slug>/` in this repo. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical roles map to `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` plus `docs/adr/` at the repo root. See `docs/agents/domain.md`.