#!/bin/bash

# This is safe to run multiple times and will prompt you about anything unclear
# Check config.sh file to configure dotfiles, plugins and packages

# Skip brew's interactive install/upgrade confirmation prompts (non-interactive script run)
export HOMEBREW_NO_ASK=1

source ./config.sh
source ./lib/echos.sh
source ./lib/utils.sh
source ./lib/dotfiles.sh
source ./lib/os.sh
source ./lib/fish.sh

# Parameters
#  -u to define a user
#  -f to force and do not ask for confirmation at the beginning
while getopts ":u:f" opt; do
  case $opt in
    u) USER_PARAM="$OPTARG"
    ;;
    f) FORCE=1
    ;;    \?) echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done

# Get current dir (so run this script from anywhere)
DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DOTFILES_USER="default"

# Derived content (CONTEXT.md): bb CLI skills for external agents live in
# ~/.agents/skills and ~/.claude/skills, installed not versioned. Idempotent:
# replaces a previously installed copy, leaves other skills alone.
function install_bb_cli_skills() {
  if ! command -v bb &>/dev/null; then
    warn "bb CLI not on PATH (build from get-bb/bb checkout, link apps/cli/bin/bb), skipping bb CLI skills install"
    return
  fi
  bot "Installing bb CLI skills for external agents ..."
  bb skill install-cli-skills || warn "bb skill install-cli-skills failed, run it manually once bb is running"
  ok
}

# bb plugins from bb-plugins.txt: one source per line (git:/npm:/path:), path:
# entries relative to this repo. Idempotent: skips sources bb already has.
function install_bb_plugins() {
  if ! command -v bb &>/dev/null; then
    warn "bb CLI not on PATH (build from get-bb/bb checkout, link apps/cli/bin/bb), skipping bb plugins install"
    return
  fi
  local manifest="$DOTFILES_DIR/bb-plugins.txt"
  if [[ ! -f $manifest ]]; then
    warn "bb-plugins.txt not found, skipping bb plugins install"
    return
  fi
  bot "Installing bb plugins ..."
  local line source
  local installed
  installed=$(bb plugin list --json 2>/dev/null | jq -r '.plugins[].source')
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z $line || $line == \#* ]] && continue
    source=$line
    [[ $line == path:* ]] && source="path:$DOTFILES_DIR/${line#path:}"
    if grep -qxF "$source" <<< "$installed"; then
      ok "bb plugin already installed: $line"
    else
      execute "bb plugin install --yes ${source#path:}" "bb plugin: $line"
    fi
  done < "$manifest"
  ok
}

# pi itself + its npm: packages on every setup run.
function update_pi() {
  if ! command -v pi &>/dev/null; then
    warn "pi not found, skipping pi update"
    return
  fi
  bot "Updating pi and extensions ..."
  execute "pi update --all" "pi update --all"
  ok
}

start

if ! is_osx; then
  error "Operating System not supported"
  exit;
fi

_install_brew_cask
_install_brew
_install_pip
_install_npm
_install_app_store_apps
_setup_osx
install_dotfiles
install_fish

unset DOTFILES_USER
DOTFILES_USER=$USER_PARAM

if [[ $DOTFILES_USER ]]; then
  if [[ ! -f "$DOTFILES_DIR/config_$DOTFILES_USER.sh" ]]; then
    error "Config file not found: config_${DOTFILES_USER}.sh"
    exit 1
  fi
  source "$DOTFILES_DIR/config_$DOTFILES_USER.sh"
  _install_brew_cask
  _install_brew
  _install_pip
  _install_npm
  _install_app_store_apps
fi

# Agent tooling (bb, pi) is installed by the user config above, so these run last
install_bb_cli_skills
install_bb_plugins
update_pi

cleanup

end
