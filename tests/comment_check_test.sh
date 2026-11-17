#!/usr/bin/env bash
# comment-check decides one thing per block: is this prose over budget, or a why
# the code cannot say? Both directions are pinned here, because a check that fires
# on a two-line vendor quirk teaches you to ignore it, and one that misses a
# six-line essay is the reason the check exists. The last two cases are the ones
# that matter most: a diff may only judge the lines it added.
set -eo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$REPO/home/.agents/scripts/comment-check"

fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# 1. A two-line why passes: the budget is one line, two when the quirk needs one.
printf 'def f():\n    # icontains, not ilike: `_` is a character in these codes.\n    # A search for READY_ must not match everything after it.\n    return 1\n' > "$WORK/two.py"
check "a two-line comment passes" "bash '$CHECK' '$WORK/two.py' >/dev/null"

# 2. A six-line essay fails, and the message names where the prose belongs.
printf 'def f():\n    # One.\n    # Two.\n    # Three.\n    return 1\n' > "$WORK/three.py"
out=$(bash "$CHECK" "$WORK/three.py" 2>&1) && code=0 || code=$?
check "a three-line comment fails" "[ $code -eq 1 ]"
check "it names the file, the line, and where the reasoning goes" \
  "printf '%s\n' \"\$out\" | grep -q 'three.py:2: 3 comment lines' && printf '%s\n' \"\$out\" | grep -q 'ADR or the PR body'"

# 3. Docstrings are the same budget: 443 of the lines in DEN-tachyon #51 were here.
printf 'def f():\n    \"\"\"One sentence about what this returns.\"\"\"\n    return 1\n' > "$WORK/short_doc.py"
check "a one-line docstring passes" "bash '$CHECK' '$WORK/short_doc.py' >/dev/null"
printf 'def f():\n    """A store over the synced copy.\n\n    ADR 0005: reads come from a copy, saves stay in Delta. Nothing here writes Postgres,\n    and nothing here takes a lock: a copy is not the master, and a stale read is safe\n    by the token, which is why no read has to be rechecked against Delta either.\n    """\n    return 1\n' > "$WORK/long_doc.py"
out=$(bash "$CHECK" "$WORK/long_doc.py" 2>&1) && code=0 || code=$?
check "a six-line docstring fails" "[ $code -eq 1 ] && printf '%s\n' \"\$out\" | grep -q '6-line docstring'"

# A multi-line SQL literal is not a docstring: the warehouse keeps its statements in f-strings.
printf 'def merge():\n    return f"""MERGE INTO t AS t\nUSING (SELECT 1) AS s\nON t.a = s.a\nWHEN MATCHED THEN UPDATE SET\n  t.value = :value,\n  t.status = :status,\n  t.audit.by = :by\n"""\n' > "$WORK/sql_literal.py"
check "a multi-line f-string passes" "bash '$CHECK' '$WORK/sql_literal.py' >/dev/null"

# 4. Exempt blocks: a licence header, notebook cells, tool directives, dividers.
printf '# Copyright 2026 Launchmetrics\n# SPDX-License-Identifier: MIT\n# Licensed under the Apache License\n\n# MAGIC | code table | the DataOps group, the Product group, and the\n# MAGIC | and the Tachyon taxonomy editor, which writes them through the\n# MAGIC | warehouse. This is documentation of the notebook, not a comment.\n\n# ---------------------------------------------------------------------------\n\ndef f():\n    return 1\n' > "$WORK/exempt.py"
check "headers, MAGIC cells and dividers pass" "bash '$CHECK' '$WORK/exempt.py' >/dev/null"

# git hands GIT_DIR to hook scripts, so a temp repo created here would otherwise
# write into the caller's index. Every GIT_* variable is dropped first.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES

# 5. The diff modes judge only what the diff added.
mkdir -p "$WORK/repo" && cd "$WORK/repo"
git init -q -b main && git config user.email t@t && git config user.name t
printf 'def f():\n    # Pre-existing one.\n    # Pre-existing two.\n    # Pre-existing three.\n    # Pre-existing four.\n    return 1\n' > legacy.py
printf 'def g():\n    return 2\n' > fresh.py
git add . && git commit -qm one
check "the pre-existing block is a finding in a whole-file pass" \
  "! bash '$CHECK' legacy.py >/dev/null"

printf 'def g():\n    # One.\n    # Two.\n    # Three.\n    return 2\n' > fresh.py
git add fresh.py
out=$(bash "$CHECK" --staged 2>&1) && code=0 || code=$?
check "a new three-line block is caught in --staged" \
  "[ $code -eq 1 ] && printf '%s\n' \"\$out\" | grep -q 'fresh.py'"
check "the pre-existing block is not re-reported" "! printf '%s\n' \"\$out\" | grep -q legacy.py"

git commit -qm two
printf 'def f():\n    # Pre-existing one.\n    # Pre-existing two.\n    # Pre-existing three.\n    # Pre-existing four.\n    return 1\n\ndef h():\n    return 3\n' > legacy.py
printf 'def g():\n    return 2\n' > fresh.py
git add . && git commit -qm three
check "--base sees only the branch's added lines" \
  "bash '$CHECK' --base HEAD~1 >/dev/null"

printf 'def g():\n    # One.\n    # Two.\n    # Three.\n    return 2\n' > fresh.py
git add . && git commit -qm four
check "--base catches the branch's own essay" \
  "! bash '$CHECK' --base HEAD~1 >/dev/null"

# 6. A usage error is an error, not a pass — a typo must not read as clean.
check "--help says how to run it" "bash '$CHECK' --help | grep -q -- --base"
check "a missing file exits 2" "! bash '$CHECK' nope.py >/dev/null 2>&1"
check "an unknown flag exits 2" "! bash '$CHECK' --nope >/dev/null 2>&1"

exit "$fail"
