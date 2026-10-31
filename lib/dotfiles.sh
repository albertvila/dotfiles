#!/usr/bin/env bash

function install_dotfiles() {
  _backup_existing_dotfiles

  _install_dotfiles
  _setup_git
  _setup_vim
}

# Reports every target that is missing or points somewhere else, and changes
# nothing. Same walk as _install_dotfiles, so the drift report and the install
# can never disagree about what should be linked.
function check_dotfiles() {
  bot "Checking the symlink tree under $HOME"
  DOTFILES_DRIFT=0
  _each_managed_target _check_target
  if [ $DOTFILES_DRIFT -eq 0 ]; then
    ok "no drift"
  fi
  return $DOTFILES_DRIFT
}

# It does a cleanup every 30 days
function cleanup() {
  export LC_ALL=C
  if [ ! -e "$HOME/.dotfiles_cleanup" ]; then
    # First execution, doing nothin
    echo $(date) >> "$HOME/.dotfiles_cleanup"
    return
  else
    lastCleanup=$(tail -n 1 "$HOME/.dotfiles_cleanup")
    cyan=$(cyan "$lastCleanup")
  fi

  if ! command -v gdate &>/dev/null; then
    warn "gdate (coreutils) not found, skipping cleanup"
    return
  fi

  todayMinus30Days=$(gdate -d "30 days ago" +"%Y%m%d")
  lastCleanupFormatted=$(gdate -d "${lastCleanup}" +%Y%m%d)

  if [[ "$todayMinus30Days" > "$lastCleanupFormatted" ]]; then
    freeSpaceBeforeCleaning=$(df -Ph | awk 'NR==2 {print $4}')
    bot "Last cleanup done at $cyan, doing another clean up now ..."

    if [ -e "$HOME/.gradle" ]; then
      # Cleaning up gradle cache (https://github.com/gradle/gradle/issues/2304)
      bot "Starting gradle cache cleaning, please be patient..."
      find ~/.gradle -type f -atime +30 -delete
      find ~/.gradle -type d -mindepth 1 -empty -delete
      ok "Gradle cache cleaned"
    fi

    if [ -x "$(command -v docker)" ]; then
      bot "Starting docker system prune, please be patient..."
      docker system prune -a -f --volumes
      ok "Docker imge pruned"
    fi

    if [ -x "$(command -v yarn)" ]; then
      bot "Starting yarn cache clean, please be patient..."
      yarn cache clean
      ok "Yarn cache cleaned"
    fi

    bot "Running brew cleanup ..."
    brew cleanup --prune=30
    ok "Brew cleanup done"

    sleep 2
    freeSpaceAfterCleaning=$(df -Ph | awk 'NR==2 {print $4}')
    blue=$(blue "$freeSpaceBeforeCleaning")
    cyan=$(cyan "$freeSpaceAfterCleaning")
    ok "Cleaning done, free space before was $blue and now $cyan"

    echo $(date) >> "$HOME/.dotfiles_cleanup"
  fi
}

# Config --global entries configured using the git/gitconfig file
function _setup_git() {
  bot "Setting up git config"

  git submodule update --init --recursive

  ok
}

function _setup_vim() {
  bot "Installing vim plugins and fonts"

  vim +PluginInstall +qall > /dev/null 2>&1

  ok
}

function _symbolic_link() {
  sourceFile=$1
  targetFile=$2
  local state
  state=$(_link_state "$sourceFile" "$targetFile")

  case $state in
  missing)
    execute "ln -fs $sourceFile $targetFile" "$targetFile → $sourceFile"
  ;;
  linked)
    ok "Link already exists for $targetFile"
  ;;
  foreign)
    ask_for_confirmation "'$targetFile' already exists, do you want to overwrite it?"
    if answer_is_yes; then
      rm -rf "$targetFile"
      execute "ln -fs $sourceFile $targetFile" "$targetFile → $sourceFile"
    else
      error "$targetFile → $sourceFile"
    fi
  ;;
  esac
}

function _backup_existing_dotfiles() {
  bot "Backup any existing dotfiles in homedir to ~/.dotfiles_old directory if needed"

  # Create dotfiles_old for backup in homedir
  DOTFILES_BACKUP_DIR=~/.dotfiles_old
  mkdir -p "$DOTFILES_BACKUP_DIR"

  # Move any existing dotfiles in homedir to dotfiles_old directory.
  # Merge dirs are skipped: they host manager-written content and are linked
  # per-file; backing them up wholesale would relocate real skills/config.
  while IFS= read -r -d '' sourceFile; do
    relative="${sourceFile#$DOTFILES_DIR/home/}"
    if _is_merge_dir "$relative" || _is_no_link "$relative"; then
      continue
    fi
    file="$HOME/$relative"

    # Only move the file if it exists (as a file or dir) and is not a symlink
    if [ -e "$file" ] && [ ! -L "$file" ]; then
      mv "$file" "$DOTFILES_BACKUP_DIR"
      if [ $? -eq 0 ]; then
        ok "$file moved to $DOTFILES_BACKUP_DIR"
      else
        error "Error moving $file to $DOTFILES_BACKUP_DIR"
      fi
    fi
  done < <(find "$DOTFILES_DIR/home" -mindepth 1 -maxdepth 1 -not -name '.DS_Store' -print0)

  ok
}

# Depth-1 dirs that host manager-written content beyond what we version:
# only their files are symlinked, never the dir as a whole.
function _is_merge_dir() {
  case "$1" in
    .config|.claude|.pi|.agents|.bb|.gnupg) return 0 ;;
    *) return 1 ;;
  esac
}

# Depth-1 entries never installed: regenerable cache that must stay a real
# directory in $HOME, not a symlink back into this working tree.
function _is_no_link() {
  case "$1" in
    .cache) return 0 ;;
    *) return 1 ;;
  esac
}

# How a target sits relative to its source: linked, missing, or foreign (a real
# file or a link to something else). Both install and check branch on this.
function _link_state() {
  local sourceFile=$1 targetFile=$2
  if [ ! -e "$targetFile" ] && [ ! -L "$targetFile" ]; then
    echo missing
  elif [ "$(readlink "$targetFile")" == "$sourceFile" ]; then
    echo linked
  else
    echo foreign
  fi
}

# Every managed target, handed to $1 as (source, relative) in install order:
# merge-dir files first, then wholesale entries. Both _install_dotfiles and
# check_dotfiles walk this, so the drift report cannot disagree with the install.
# Keep comments out of the <(...) body below: bash 3.2 (macOS /bin/bash, the
# shell the setup.sh shebang picks) reads an apostrophe in a comment as a
# quote and then fails the whole install with "bad substitution".
function _each_managed_target() {
  local handler=$1
  local sourceFile
  local relative
  while IFS= read -r -d '' sourceFile; do
    relative="${sourceFile#$DOTFILES_DIR/home/}"
    "$handler" "$sourceFile" "$relative"
  done < <(
    find "$DOTFILES_DIR/home" -mindepth 1 -maxdepth 1 -type d -print0 | while IFS= read -r -d '' d; do
      if _is_merge_dir "$(basename "$d")"; then
        find "$d" \( -name __pycache__ -o -name '*.gpui-lock' \) -prune -o \( -type f -o -type l \) -print0
      fi
    done
    find "$DOTFILES_DIR/home" -mindepth 1 -maxdepth 1 -not -name '.DS_Store' -print0 | while IFS= read -r -d '' entry; do
      if _is_merge_dir "${entry#$DOTFILES_DIR/home/}" || _is_no_link "${entry#$DOTFILES_DIR/home/}"; then
        continue
      fi
      printf '%s\0' "$entry"
    done
  )
}

function _install_target() {
  local targetFile="$HOME/$2"
  mkdir -p "$(dirname "$targetFile")"
  _symbolic_link "$1" "$targetFile"
}

function _check_target() {
  local targetFile="$HOME/$2"
  local state
  state=$(_link_state "$1" "$targetFile")
  if [ "$state" = linked ]; then
    return 0
  fi
  error "drift: $targetFile is $state, want a link to $1"
  DOTFILES_DRIFT=1
}

function _install_dotfiles() {
  bot "Creating symbolic links for config files if needed"

  _each_managed_target _install_target

  ok
}
