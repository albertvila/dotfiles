# AGENTS.md

## The agent rules themselves

They live outside this repo, in `~/.agents/AGENTS.md`, with each harness's own
name symlinked to it (`~/.pi/agent/AGENTS.md`, `~/.claude/CLAUDE.md`). No other
instruction file may exist: `tests/instructions_test.sh` holds the word budget,
the two aliases and the absence of a third copy. Its header records which harness
loads which path, and how to add the next one.

## Agent skills

### Issue tracker

Issues live as local markdown files under `.scratch/<feature-slug>/` in this repo. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical roles map to `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` plus `docs/adr/` at the repo root. See `docs/agents/domain.md`.
