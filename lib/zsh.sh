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
    fi
    echo "Aborting..."
    exit
  fi

  ok
}

function _setup_zsh() {
  bot "Setting up zsh & terminal"

  # Set the default shell to zsh if it isn't currently set to zsh
  if [[ ! $(echo $SHELL) == $(which zsh) ]]; then
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

    # TODO The following commands fail under this bash script, but they work if you run them manually on terminal
    setopt EXTENDED_GLOB

    # The following command fails on Linux, command substitution: syntax error near unexpected token '.N'
    for rcfile in `${ZDOTDIR:-$HOME}/.zprezto/runcoms/^README.md(.N)`; do
      ln -s "$rcfile" "${ZDOTDIR:-$HOME}/.${rcfile:t}"
    done

    # Installing the powerlevel9k theme
    git clone https://github.com/bhilburn/powerlevel9k.git  ~/.zprezto/modules/prompt/external/powerlevel9k

    # If we want to uninstall it, just remove the ~/.zprezto folder
  else
    cd $HOME/.zprezto/
    git pull && git submodule update --init --recursive
  fi

  ok
}
