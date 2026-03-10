#!/usr/bin/env bash

function install_zsh() {
  _install_zsh

  _install_prezto

  _setup_zsh
}

function _install_zsh() {
  bot "Installing zsh if needed"

  # Test to see if zshell is installed
  if [ -f /bin/zsh -o -f /usr/bin/zsh ]; then
    ok "zsh is already installed, checking if we need to upgrade it using brew upgrade command ..."
    brew upgrade zsh
  else
    ask_for_confirmation "Zsh not found, zsh installation has not been tested, do you wanna proceed?"
    if answer_is_yes; then
      echo "We'll try to install zsh, then re-run this script!"
      brew install zsh
    else
      echo "Aborting..."
      exit
    fi
  fi

  ok
}

function _setup_zsh() {
  bot "Setting up zsh & terminal"

  # Set the default shell to zsh if it isn't currently set to zsh
  if [[ ! ($(echo $SHELL) == $(which zsh) || "/opt/homebrew/bin/zsh" == $(which zsh)) ]]; then
    # If you receive this error `chsh: /usr/local/bin/zsh: non-standard shell`, then run the following command
    # sudo sh -c "echo $(which zsh) >> /etc/shells"
    chsh -s $(which zsh)
  fi

  $DOTFILES_DIR/iterm/powerline/fonts/install.sh

  ok
}

# https://github.com/sorin-ionescu/prezto
function _install_prezto() {
  bot "Intalling/Updating prezto if needed"

  # Install Prezo if it isn't already present
  if [[ ! -d $HOME/.zprezto/ ]]; then
    git clone --recursive https://github.com/sorin-ionescu/prezto.git "${ZDOTDIR:-$HOME}/.zprezto"

    # Symlink all runcom files except README.md into the home directory
    for rcfile in "${ZDOTDIR:-$HOME}/.zprezto/runcoms/"*; do
      [[ "${rcfile##*/}" == "README.md" ]] && continue
      ln -sf "$rcfile" "${ZDOTDIR:-$HOME}/.${rcfile##*/}"
    done

    # If we want to uninstall it, just remove the ~/.zprezto folder
  else
    git -C $HOME/.zprezto pull && git -C $HOME/.zprezto submodule update --init --recursive --remote
  fi

  ok
}
