#!/usr/bin/env bash
# comment-dupe exists for one failure the budget cannot see: the same decision stated twice, which
# stays readable and stays wrong — the second copy is a second edit. Each check pins one half of
# that: a real copy is caught, and the noise it would drown in (short labels, a shared prefix) is not.
set -eo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DUPE="$REPO/home/.agents/scripts/comment-dupe"

fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }
# The tool exits 1 when it finds copies, which under pipefail would fail the grep beside it.
output() { "$DUPE" "$@" 2>&1 || true; }

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
git init -q -b main && git config user.email t@t && git config user.name t

# 1. The same decision in two files is one decision too many.
cat > a.py <<'PY'
def find():
    # The token is a digest of the four fields a save compares, and nothing about the table's shape,
    # so a row read from the copy carries the token a row read from Delta does.
    return 1
PY
cat > b.py <<'PY'
def save():
    # The token is a digest of the four fields a save compares, and nothing about the table's shape, so
    # a row read from the copy carries the token a row read from Delta does too.
    return 2
PY
git add . && git commit -qm one
"$DUPE" >/dev/null 2>&1 && code=0 || code=$?
check "a decision written twice fails" "[ $code -eq 1 ]"
check "it names both places" "output | grep -q 'a.py:2' && output | grep -q 'b.py:2'"

# 2. Two sentences that merely share a word are not a copy.
cat > a.py <<'PY'
def find():
    # The token is a digest of the four fields a save compares, and nothing about the table's shape.
    return 1
PY
cat > b.py <<'PY'
def save():
    # A save asks the warehouse to re-read the row from Delta before it decides there is a conflict.
    return 2
PY
git add . && git commit -qm two
check "two different decisions pass" "'$DUPE' >/dev/null"

# 3. A phrase is not a decision: short comments repeat by accident.
printf 'def f():\n    # The key of the row.\n    return 1\n' > a.py
printf 'def g():\n    # The key of the row.\n    return 2\n' > b.py
git add . && git commit -qm three
check "a four-word phrase is not flagged" "'$DUPE' >/dev/null"

# 4. One copy in a docstring counts too, or a rationale migrates between forms to escape the check.
cat > c.py <<'PY'
"""The token is a digest of the four fields a save compares, and nothing about the table's shape."""
PY
cat > d.py <<'PY'
def save():
    # The token is a digest of the four fields a save compares, and nothing about the table's shape.
    return 2
PY
git add . && git commit -qm four
"$DUPE" c.py d.py >/dev/null 2>&1 && code=0 || code=$?
check "a docstring copy is caught" "[ $code -eq 1 ]"

# 5. Directives and licence headers are not decisions.
printf '# Copyright 2026 Launchmetrics\n# SPDX-License-Identifier: MIT\n' > e.py
printf '# Copyright 2026 Launchmetrics\n# SPDX-License-Identifier: MIT\n' > f.py
git add . && git commit -qm five
check "headers are ignored" "'$DUPE' e.py f.py >/dev/null"

# 6. Silence is not success: it says what it read.
check "it reports what it read" "'$DUPE' >/dev/null 2>&1; output | grep -q 'decisions read'"

# 7. The staged mode: what this commit adds, against what the repo already says. It is a warning in
# the hook, so --warn must pass while the same finding without it fails.
git checkout -q -b staged-case HEAD~1 2>/dev/null || git switch -q -c staged-case
printf 'def k():
    # The token is a digest of the four fields a save compares, and nothing about the shape.\n    return 1\n' > s1.py
git add s1.py && git commit -qm six
printf 'def m():\n    # The token is a digest of the four fields a save compares, and nothing about the shape.\n    return 2\n' > s2.py
git add s2.py
"$DUPE" --staged >/dev/null 2>&1 && code=0 || code=$?
check "--staged fails on a copy" "[ $code -eq 1 ]"
"$DUPE" --staged --warn >/dev/null 2>&1 && code=0 || code=$?
check "--warn passes with the same copy" "[ $code -eq 0 ]"
check "--warn names the copy and its twin" "output --staged --warn | grep -q 's2.py:2 says what s1.py:2 already says'"
git reset -q s2.py && rm -f s2.py
printf 'def n():\n    # A save asks the warehouse to re-read the row before it decides there is a conflict.\n    return 3\n' > s3.py
git add s3.py
check "--staged is silent on a new decision" "'$DUPE' --staged --warn >/dev/null"
git reset -q s3.py && rm -f s3.py

exit "$fail"
