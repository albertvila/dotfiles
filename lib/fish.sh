#!/usr/bin/env bash

function install_fish() {
  _install_fish_binary

  _install_fasd

  _setup_fish
}

# fasd powers `z` in fish (conf.d/30-shell.fish); no longer on Homebrew — install from GitHub
function _install_fasd() {
  bot "Checking fasd ..."

  if command -v fasd &>/dev/null; then
    ok "fasd is already installed"
    return
  fi

  warn "fasd not found, installing from GitHub ..."
  curl -sL https://raw.github.com/clvv/fasd/master/fasd -o /opt/homebrew/bin/fasd \
    && chmod 755 /opt/homebrew/bin/fasd \
    && ok "fasd installed" \
    || error "Failed to install fasd"
}

function _install_fish_binary() {
  bot "Installing fish if needed"

  if command -v fish &>/dev/null; then
    ok "fish is already installed, checking if we need to upgrade it using brew upgrade command ..."
    brew upgrade fish
  else
    brew install fish
  fi

  # chsh refuses shells outside /etc/shells; needs a one-time sudo, so just warn
  if ! grep -qx "$(command -v fish)" /etc/shells; then
    warn "$(command -v fish) is not in /etc/shells — run once: echo $(command -v fish) | sudo tee -a /etc/shells"
  fi

  ok
}

function _setup_fish() {
  bot "Setting up fish as the default shell"

  # Fish config lives in the home mirror (home/.config/fish) and is linked by install_dotfiles
  if [[ "$(echo $SHELL)" != "$(command -v fish)" ]]; then
    chsh -s "$(command -v fish)"
  fi

  ok
}
