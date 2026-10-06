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

# The bb app ships its CLI in the bundle; link it so setup and agents can
# drive the running server. A bb already on PATH (dev checkout) is left alone,
# and a machine without the app just skips the link.
function link_bb_cli() {
  if command -v bb &>/dev/null; then
    ok "bb CLI already on PATH: $(command -v bb)"
    return
  fi
  local bundle_cli="/Applications/bb.app/Contents/Resources/app.asar.unpacked/node_modules/bb-app/dist/bb.js"
  if [[ ! -x $bundle_cli ]]; then
    return
  fi
  bot "Linking bb CLI ..."
  mkdir -p "$HOME/.local/bin"
  ln -sfn "$bundle_cli" "$HOME/.local/bin/bb"
  ok
}

# Derived content (CONTEXT.md): bb CLI skills for external agents live in
# ~/.agents/skills and ~/.claude/skills, installed not versioned. Idempotent:
# replaces a previously installed copy, leaves other skills alone.
function install_bb_cli_skills() {
  if ! command -v bb &>/dev/null; then
    warn "bb CLI not on PATH (install the bb cask, or link a get-bb/bb checkout's apps/cli/bin/bb), skipping bb CLI skills install"
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
    warn "bb CLI not on PATH (install the bb cask, or link a get-bb/bb checkout's apps/cli/bin/bb), skipping bb plugins install"
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
    # bb records resolved absolute paths, so a relative manifest entry with a
    # `..` segment would never match without canonicalizing it.
    [[ $line == path:* ]] && source="path:$(realpath "$DOTFILES_DIR/${line#path:}" 2>/dev/null || echo "$DOTFILES_DIR/${line#path:}")"
    if grep -qxF "$source" <<< "$installed"; then
      ok "bb plugin already installed: $line"
    else
      execute "bb plugin install --yes ${source#path:}" "bb plugin: $line"
    fi
  done < "$manifest"
  ok
}

# twg CLI (Teamwork Graph): Atlassian's own installer drops the binary into
# ~/.local/bin (no brew formula), already on fish's PATH. Login stays manual
# (see README): the token prompt needs the user's terminal.
function install_twg_cli() {
  local twg="$HOME/.local/bin/twg"
  bot "Installing/updating the twg CLI and its agent skills ..."
  if [[ -x $twg ]]; then
    execute "$twg update --yes" "twg update"
  else
    curl -fsSL --retry 2 https://teamwork-graph.atlassian.com/cli/install | bash -s -- --yes --skip-login --skip-skills &>/dev/null
    result $? "twg install"
  fi
  execute "$twg skills install --yes --all-agents" "twg skills install"
  ok
}

# herdr shows which agent is working in a pane by installing a status hook
# into each agent's own config. Keep those hooks current for the agents this
# machine has; `herdr integration install` is idempotent, so rerun it.
function install_herdr_integrations() {
  if ! command -v herdr &>/dev/null; then
    warn "herdr not found, skipping herdr integrations"
    return
  fi
  bot "Updating herdr agent integrations ..."
  local target
  for target in pi claude opencode; do
    command -v "$target" &>/dev/null || continue
    execute "herdr integration install $target" "herdr integration: $target"
  done
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

# Agent tooling (bb, pi, herdr) is installed by the user config above, so these run last
link_bb_cli
install_bb_cli_skills
install_bb_plugins
install_twg_cli
update_pi
install_herdr_integrations

cleanup

end
