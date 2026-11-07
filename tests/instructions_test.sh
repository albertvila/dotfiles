#!/usr/bin/env bash
# One file, two aliases: the agent instructions.
#
# Measured 2026-11-07 with `pi -p` and `claude -p` run from /tmp and from a repo
# under $HOME, each asked which AGENTS.md/CLAUDE.md blocks it was given:
#
#   pi     -> ~/.pi/agent/AGENTS.md (the agent dir), plus context files walking
#             up from the working directory
#   claude -> ~/.claude/CLAUDE.md (its user memory), plus CLAUDE.md/AGENTS.md
#             walking up
#
# Neither reads the other's directory, and Claude does *not* fall back to
# AGENTS.md in its own config dir: with ~/.claude/CLAUDE.md moved aside and
# ~/.claude/AGENTS.md present, Claude loaded nothing at all. So the alias has to
# be called CLAUDE.md, and the text therefore lives once, at
# ~/.agents/AGENTS.md, with both harness names symlinked to it.
#
# That is what this test holds, because a symlink tree is invisible in review: a
# second copy dropped into ~/ or ~/.bb/ costs a session three loads of the same
# text and nothing else would notice. Adding a harness means adding its alias
# here (Codex: ~/.codex/AGENTS.md, Gemini: ~/.gemini/GEMINI.md).
set -eo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MASTER="$REPO/home/.agents/AGENTS.md"
WORD_BUDGET="${AGENTS_BUDGET:-1200}"

fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }

words=$(wc -w < "$MASTER" | tr -d ' ')
check "the global rules fit in ${WORD_BUDGET} words (${words})" "[ '$words' -le '$WORD_BUDGET' ]"

master_real=$(readlink -f "$MASTER")
for alias in home/.pi/agent/AGENTS.md home/.claude/CLAUDE.md; do
  check "$alias resolves to the master" "[ '$(readlink -f "$REPO/$alias")' = '$master_real' ]"
done

expected=$(printf '%s\n' .agents/AGENTS.md .claude/CLAUDE.md .pi/agent/AGENTS.md | sort)
found=$(cd "$REPO/home" && find . \( -name AGENTS.md -o -name CLAUDE.md \) -print | sed 's|^\./||' | sort)
stray=$(comm -13 <(printf '%s\n' "$expected") <(printf '%s\n' "$found"))
check "nothing else under home/ carries instructions (${found//$'\n'/, })" "[ -z '$stray' ]"

exit "$fail"
