#!/usr/bin/env bash
# The skill listing is context every turn: Pi puts each visible skill's name and
# description in the system prompt and loads the body only when the work calls
# for it. So a description is a per-turn cost paid in every session, in every
# agent. Measured 2026-11-07: 85 visible skills, 23,781 characters of
# name + description, about 8.5k tokens a turn (Pi's listing runs near 2.8
# characters a token, not 4; 56 more skills already carry
# `disable-model-invocation: true` and cost nothing).
#
# The budget is a ratchet, not a target: it is today's total, so nothing fails
# now, and a new skill has to pay for itself by shortening something else. Lower
# the number as you trim; never raise it without saying why in the commit.
#
# `disable-model-invocation: true` takes a skill out of the listing entirely, and
# is right for one that only ever starts from its typed command
# (`orchestrate-bb-plan`, `orchestrate-herdr-plan` do this today). It is wrong for
# any skill whose description carries a second trigger ("or the prompt carries a
# manifest", "or asks to share a markdown file"): those must stay visible.
set -eo pipefail

BUDGET="${SKILLS_LISTING_BUDGET:-23781}"

fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }

out=$(python3 - "$BUDGET" <<'PY'
import glob, os, re, sys

budget = int(sys.argv[1])
roots = ["~/.pi/agent/skills", "~/.agents/skills", "~/.bb/runtime/global-skills/*/skills"]
# Pi keeps the first skill of a name it discovers and warns about the rest, so a
# name that exists in two roots is listed once. Counting it twice would budget a
# cost nobody pays.
seen = {}
for base in roots:
    for path in sorted(glob.glob(os.path.join(os.path.expanduser(base), "*", "SKILL.md"))):
        frontmatter = re.search(r"^---\n(.*?)\n---", open(path, encoding="utf-8", errors="ignore").read(), re.S)
        if not frontmatter or "disable-model-invocation" in frontmatter.group(1):
            continue
        description = re.search(r"description:\s*(.*?)(?=\n[a-z_-]+:|\Z)", frontmatter.group(1), re.S)
        name = re.search(r"^name:\s*(.+)$", frontmatter.group(1), re.M)
        name = (name.group(1) if name else os.path.basename(os.path.dirname(path))).strip().strip('"')
        description = re.sub(r"\s+", " ", description.group(1)).strip().strip('"') if description else ""
        seen.setdefault(name, len(name) + len(description))

total = sum(seen.values())
print(f"TOTAL {total} {len(seen)}")
for size, name in sorted(((size, name) for name, size in seen.items()), reverse=True)[:5]:
    print(f"BIGGEST {size} {name}")
PY
)
total=$(awk '$1 == "TOTAL" {print $2}' <<<"$out")
count=$(awk '$1 == "TOTAL" {print $3}' <<<"$out")

check "the skill listing stays within ${BUDGET} characters (${total} over ${count} skills)" "[ '${total:-0}' -le '$BUDGET' ]"
if [ "${total:-0}" -gt "$BUDGET" ]; then
  awk '$1 == "BIGGEST" {printf "       %5d  %s\n", $2, $3}' <<<"$out"
  echo "       trim a description, or hide a skill that only starts from its typed command"
fi

exit "$fail"
