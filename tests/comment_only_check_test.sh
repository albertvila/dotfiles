#!/usr/bin/env bash
# comment-only-check answers what a reviewer cannot by eye: did anything but prose move? Each
# check below is a way that answer could be wrong, since passing when it should not is the danger.

set -eo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$REPO/home/.agents/scripts/comment-only-check"

fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }
# The checker exits 1 when it finds code, which under `pipefail` would fail the grep beside it:
# this runs it for its output, and the check judges the text.
output() { "$CHECK" "$@" 2>&1 || true; }

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
git init -q -b main && git config user.email t@t && git config user.name t
printf 'def f():\n    """What it does."""\n    return 1\n' > a.py
printf 'echo hi\n# a comment\n' > b.sh
printf 'def f():\n    return 1\n' > c.py
printf 'x = 1\n' > d.zig
printf '/*\n   one line\n   another line\n*/\ncode();\n' > e.js
git add . && git commit -qm one
clean() { git reset -q --hard HEAD; rm -f d.zig e.new; }

# 1. A docstring rewritten is not a code change, and is not silently skipped either.
printf 'def f():\n    """What it does, in one line."""\n    return 1\n' > a.py
git add a.py
check "a rewritten docstring passes" "'$CHECK' --staged >/dev/null"
check "a rewritten docstring is counted" "'$CHECK' --staged | grep -q '1 file(s) checked'"

# 2. A statement changed is a code change, and the message says which.
clean
printf 'def f():\n    """What it does."""\n    return 2\n' > a.py
git add a.py
"$CHECK" --staged >/dev/null 2>&1 && code=0 || code=$?
check "a changed return value fails" "[ $code -eq 1 ]"
check "it names the file and the reason" \
  "output --staged | grep -q 'a.py: a statement, signature or string literal changed'"

# 3. What is not a docstring is code: a new constant, and a literal changed in place.
clean
printf 'def f():\n    """What it does."""\n    return 1\n\nLIMIT = "ten"\n' > a.py
git add a.py
"$CHECK" --staged >/dev/null 2>&1 && code=0 || code=$?
check "a new module constant fails" "[ $code -eq 1 ]"

clean
printf 'def f():\n    return "one"\n' > c.py
git add c.py
"$CHECK" --staged >/dev/null 2>&1 && code=0 || code=$?
check "a changed string literal fails" "[ $code -eq 1 ]"

# 4. Other file types: only comment lines may move.
clean
printf 'echo hi\n# a comment, reworded\n' > b.sh
git add b.sh
check "a reworded shell comment passes" "'$CHECK' --staged >/dev/null"
printf 'echo hi there\n# a comment, reworded\n' > b.sh
git add b.sh
"$CHECK" --staged >/dev/null 2>&1 && code=0 || code=$?
check "a changed shell line fails" "[ $code -eq 1 ]"

# 4b. A block comment is a comment on its middle lines, which carry no marker of their own.
clean
printf '/*\n   one line, reworded\n   another line\n*/\ncode();\n' > e.js
git add e.js
check "a reworded line inside /* */ passes" "'$CHECK' --staged >/dev/null"
git reset -q --hard HEAD
printf '/*\n   one line\n   another line\n*/\ncode(2);\n' > e.js
git add e.js
"$CHECK" --staged >/dev/null 2>&1 && code=0 || code=$?
check "a code line below the block still fails" "[ $code -eq 1 ]"
git reset -q --hard HEAD

# 5. What it cannot judge, it refuses rather than passes.
clean
printf 'x = 1\n# a note\n' > d.zig
git add d.zig
"$CHECK" --staged >/dev/null 2>&1 && code=0 || code=$?
check "an unclassifiable file type fails" \
  "[ $code -eq 1 ] && output --staged | grep -q 'no comment rule'"

clean
printf 'x = 1\n' > e.new
git add e.new
"$CHECK" --staged >/dev/null 2>&1 && code=0 || code=$?
check "an added file fails" "[ $code -eq 1 ] && output --staged | grep -q 'added'"

# 6. The range form agrees with --staged once the change is committed.
clean
printf 'def f():\n    """Reworded."""\n    return 1\n' > a.py
git add a.py && git commit -qm three
check "--base HEAD~1 sees the same change" "'$CHECK' --base HEAD~1 >/dev/null"

# 7. Usage and git errors are errors, not passes.
"$CHECK" >/dev/null 2>&1 && code=0 || code=$?
check "no range exits 2" "[ $code -eq 2 ]"
"$CHECK" --base nope >/dev/null 2>&1 && code=0 || code=$?
check "an unknown ref exits 2" "[ $code -eq 2 ]"
"$CHECK" --staged --base main >/dev/null 2>&1 && code=0 || code=$?
check "two diffs at once exits 2" "[ $code -eq 2 ]"

exit "$fail"
