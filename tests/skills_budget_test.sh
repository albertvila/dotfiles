#!/usr/bin/env bash
# Checks that no orchestrate skill body outgrows its budget. Pi loads a skill by
# reading SKILL.md whole, and the read tool cuts at 50 KiB — announced, so the
# cost is a second read rather than lost content, but a body near the cap is one
# the agent reads in pieces. The budget is well under it: mechanics that only one
# step needs belong in a `references/` file behind a load stub, not in the body.
set -eo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS="$REPO/home/.agents/skills"

BUDGET="${SKILLS_BUDGET:-40960}"   # 40 KiB per body — 80% of the read tool's cap
fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }

shopt -s nullglob
bodies=("$SKILLS"/orchestrate-*/SKILL.md)
[ "${#bodies[@]}" -gt 0 ] || { echo "FAIL - no orchestrate skills found under $SKILLS"; exit 1; }

# Every orchestrate body is a skill, and it is the only thing loaded whole.
check "found the orchestrate skill bodies" "[ '${#bodies[@]}' -ge 6 ]"

for body in "${bodies[@]}"; do
  size=$(wc -c < "$body" | tr -d ' ')
  name=$(basename "$(dirname "$body")")
  if [ "$size" -le "$BUDGET" ]; then
    echo "ok   - $name body is ${size}B (budget ${BUDGET}B)"
  else
    echo "FAIL - $name body is ${size}B, over the ${BUDGET}B budget:"
    echo "       move step mechanics into references/ behind a load stub"
    fail=1
  fi
done

# A reference the body names must exist, and a reference file must name a body
# that links back to it — a stub pointing at nothing is a step the agent skips.
for ref in "$SKILLS"/orchestrate-*/references/*.md; do
  skill=$(basename "$(dirname "$(dirname "$ref")")")
  check "$skill references/$(basename "$ref") is linked from its body" \
    "grep -q 'references/$(basename "$ref")' '$SKILLS/$skill/SKILL.md'"
  check "$skill references/$(basename "$ref") is non-empty" "[ -s '$ref' ]"
done

exit "$fail"
