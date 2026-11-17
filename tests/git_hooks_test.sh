#!/usr/bin/env bash
# The global hook answers two questions on every commit: is the staged prose over budget, and does
# the repo have an `lm` hook this one replaced and must hand on to. A wrong answer to the second
# silently drops the org's commit-message lint and pre-push PR test, so both directions are pinned
# here: the hook fires where it should and stays out of the way where it should not.
set -eo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS="$REPO/home/.git-hooks"

fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }

# git hands GIT_DIR to hook scripts, so a temp repo created here would write into the caller's index.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
# And the developer's own git config, or the global core.hooksPath runs a hook on these fixtures.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

FAKE_HOME="$WORK/home"
LM_HOOKS="$WORK/lm-hooks"
mkdir -p "$FAKE_HOME/.agents/scripts" "$LM_HOOKS" "$FAKE_HOME/workspace/lm-proj" "$WORK/personal/proj"
ln -s "$REPO/home/.agents/scripts/comment-check" "$FAKE_HOME/.agents/scripts/comment-check"
printf '[core]\n\thooksPath = %s\n' "$LM_HOOKS" > "$FAKE_HOME/.gitconfig-lm"

# An lm hook that records what it was asked, so forwarding is observable.
cat > "$LM_HOOKS/pre-push" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$WORK/lm-called"
exit 0
EOF
chmod +x "$LM_HOOKS/pre-push"

new_repo() { # new_repo <dir>
  cd "$1"
  git init -q -b main && git config user.email t@t && git config user.name t
  printf 'def f():\n    return 1\n' > a.py
  git add a.py && git commit -qm one
}

hook() { (cd "$1" && HOME="$FAKE_HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin" bash "$HOOKS/$2" "${@:3}"); }

# 1. The budget, on a repo of any kind.
new_repo "$WORK/personal/proj"
printf 'def f():\n    # One.\n    # Two.\n    # Three.\n    return 1\n' > a.py
git add a.py
hook "$WORK/personal/proj" pre-commit >/dev/null 2>&1 && code=0 || code=$?
check "a three-line staged block is refused" "[ $code -eq 1 ]"

printf 'def f():\n    # `_` is a character in these codes, so the search escapes it.\n    return 1\n' > a.py
git add a.py
hook "$WORK/personal/proj" pre-commit >/dev/null 2>&1 && code=0 || code=$?
check "a one-line staged block passes" "[ $code -eq 0 ]"

# 2. Forwarding: a repo under ~/workspace runs the lm hook of the same name, with its arguments.
new_repo "$FAKE_HOME/workspace/lm-proj"
rm -f "$WORK/lm-called"
hook "$FAKE_HOME/workspace/lm-proj" pre-push origin git@example:x.git >/dev/null 2>&1 || true
check "an lm repo runs the lm hook" "[ -f '$WORK/lm-called' ]"
check "the lm hook gets the hook's arguments" "grep -q 'origin git@example:x.git' '$WORK/lm-called'"

# 3. Anywhere else, the same name runs nothing — and is not an error.
rm -f "$WORK/lm-called"
hook "$WORK/personal/proj" pre-push origin git@example:x.git >/dev/null 2>&1 && code=0 || code=$?
check "a repo outside ~/workspace runs no lm hook" "[ ! -f '$WORK/lm-called' ] && [ $code -eq 0 ]"

# 4. A hook lm does not install is not an error either. Git only calls a name that exists here, so
# the probe is a name this directory carries and lm's does not.
rm -f "$WORK/lm-called"
mkdir -p "$WORK/extra"
ln -s "$HOOKS/dispatch" "$WORK/extra/prepare-commit-msg"
(cd "$FAKE_HOME/workspace/lm-proj" && HOME="$FAKE_HOME" bash "$WORK/extra/prepare-commit-msg" x) >/dev/null 2>&1 && code=0 || code=$?
check "a hook with no lm counterpart passes" "[ $code -eq 0 ] && [ ! -f '$WORK/lm-called' ]"

# 5. Every hook name git may call is wired, or that hook silently stops running.
for name in commit-msg post-commit post-rewrite pre-auto-gc pre-commit pre-push; do
  check "'$name' is linked to the dispatcher" "[ -L '$HOOKS/$name' ] && [ \"\$(readlink '$HOOKS/$name')\" = dispatch ]"
done

# 6. The global setting points at the directory this repo installs.
check "~/.gitconfig sets core.hooksPath last" \
  "grep -q 'hooksPath = ~/.git-hooks' '$REPO/home/.gitconfig'"

exit "$fail"
