#!/usr/bin/env bash
# setup.sh -c has to answer "does this machine still match the repo?" from the
# same walk that links, so it cannot agree to disagree with what setup does.
# Fresh HOME: every managed target reported missing. After install: clean, and
# a second install is a no-op. One deleted link and one foreign file: exactly
# those two reported, and nothing prompting.
set -eo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

export HOME="$ROOT/home"
export DOTFILES_DIR="$ROOT/repo"
export DOTFILES_USER=test
mkdir -p "$HOME"

# Fixture: a merge dir, a wholesale file, a wholesale dir, and the pruned kinds.
mkdir -p \
  "$DOTFILES_DIR/home/.config/app" \
  "$DOTFILES_DIR/home/.vim/bundle" \
  "$DOTFILES_DIR/home/.cache/huggingface"
touch \
  "$DOTFILES_DIR/home/.config/app/conf" \
  "$DOTFILES_DIR/home/.config/app/.conf.gpui-lock" \
  "$DOTFILES_DIR/home/.vimrc" \
  "$DOTFILES_DIR/home/.vim/bundle/plug" \
  "$DOTFILES_DIR/home/.cache/huggingface/blob"

# shellcheck source=/dev/null
source "$REPO/lib/echos.sh"
# shellcheck source=/dev/null
source "$REPO/lib/utils.sh"
# shellcheck source=/dev/null
source "$REPO/lib/dotfiles.sh"

# Count managed targets independently of the walk, so a walk that silently
# skips half the tree fails here instead of reporting a clean bill of health.
EXPECTED=$(find "$DOTFILES_DIR/home" -mindepth 1 -maxdepth 1 ! -name '.config' ! -name '.cache' -print | wc -l | tr -d ' ')
EXPECTED=$((EXPECTED + $(find "$DOTFILES_DIR/home/.config" -type f ! -name '*.gpui-lock' | wc -l | tr -d ' ')))

count() { printf '%s\n' "$1" | grep -c "$2" || true; }

fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }

# Fresh HOME: everything missing, exit non-zero.
OUT=$(check_dotfiles 2>&1) && status=0 || status=$?
MISSING=$(count "$OUT" 'is missing')
check "fresh HOME reports drift" "[ $status -ne 0 ]"
check "fresh HOME reports every managed target ($MISSING of $EXPECTED)" \
  "[ $MISSING -eq $EXPECTED ]"

# Apply for real, then check: clean.
_install_dotfiles > /dev/null 2>&1
check "converged HOME passes" "check_dotfiles > /dev/null 2>&1"
OUT=$(check_dotfiles 2>&1)
check "converged HOME reports no drift lines ($(count "$OUT" 'drift:'))" \
  "[ $(count "$OUT" 'drift:') -eq 0 ]"

# A second install changes nothing: the target mtime survives.
BEFORE=$(stat -f %m "$HOME/.vimrc")
sleep 1
_install_dotfiles > /dev/null 2>&1
check "second install is a no-op" "[ \"$(stat -f %m "$HOME/.vimrc")\" = \"$BEFORE\" ]"

# One missing link and one foreign file: exactly those two, named.
rm "$HOME/.vimrc"
rm "$HOME/.config/app/conf"
echo handwritten > "$HOME/.config/app/conf"
OUT=$(check_dotfiles 2>&1) && status=0 || status=$?
check "drifted HOME fails" "[ $status -ne 0 ]"
check "reports the deleted link" "printf '%s\n' \"\$OUT\" | grep -q 'vimrc is missing'"
check "reports the foreign file" "printf '%s\n' \"\$OUT\" | grep -q 'conf is foreign'"
check "reports exactly two drifts ($(count "$OUT" 'drift:'))" \
  "[ $(count "$OUT" 'drift:') -eq 2 ]"
check "drift check never prompts" "! printf '%s\n' \"\$OUT\" | grep -q '(y/n)'"

exit "$fail"
