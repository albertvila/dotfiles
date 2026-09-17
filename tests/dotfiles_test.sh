#!/usr/bin/env bash
# Checks that setup never links ~/.cache back into this working tree, and that
# merge dirs and wholesale entries keep being installed.
set -eo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

export HOME="$ROOT/home"
export DOTFILES_DIR="$ROOT/repo"
export DOTFILES_USER=test
mkdir -p "$HOME"

# The user's real ~/.cache (contents irrelevant), which setup must leave alone.
mkdir -p "$HOME/.cache/huggingface"

# Fixture: a .cache dir with content, a merge dir, plus a wholesale file and dir.
mkdir -p \
  "$DOTFILES_DIR/home/.cache/huggingface" \
  "$DOTFILES_DIR/home/.config/app" \
  "$DOTFILES_DIR/home/.vim/bundle"
touch \
  "$DOTFILES_DIR/home/.cache/huggingface/blob" \
  "$DOTFILES_DIR/home/.config/app/conf" \
  "$DOTFILES_DIR/home/.vimrc" \
  "$DOTFILES_DIR/home/.vim/bundle/plug"

# shellcheck source=/dev/null
source "$REPO/lib/echos.sh"
source "$REPO/lib/utils.sh"
source "$REPO/lib/dotfiles.sh"

fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }

check "_is_no_link .cache is true" "_is_no_link .cache"
check "_is_no_link .vimrc is false" "! _is_no_link .vimrc"

# A real ~/.cache must survive the backup step untouched.
_backup_existing_dotfiles
check "backup leaves real ~/.cache in place" "[ -d '$HOME/.cache/huggingface' ]"
check "backup does not stash .cache" "[ ! -e '$HOME/.dotfiles_old/.cache' ]"

# The install step must skip .cache but still link merge files and wholesale entries.
_install_dotfiles
check "install leaves ~/.cache a real dir" "[ -d '$HOME/.cache' ] && [ ! -L '$HOME/.cache' ]"
check "merge file still linked" "[ -L '$HOME/.config/app/conf' ]"
check "wholesale file still linked" "[ -L '$HOME/.vimrc' ]"
check "wholesale dir still linked" "[ -L '$HOME/.vim' ]"

exit "$fail"
