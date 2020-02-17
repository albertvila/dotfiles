#!/usr/bin/env bash

function install_zsh() {
  _install_zsh

  #_install_prezto
  #_setup_prezto

  _setup_zsh
  _setup_zinit
}

function _install_zsh() {
  bot "Installing zsh if needed"

  # Test to see if zshell is installed
  if [ -f /bin/zsh -o -f /usr/bin/zsh ]; then
    ok "zsh is already installed"
  else
    ask_for_confirmation "Zsh not found, zsh installation has not been tested, do you wanna proceed?"
    if answer_is_yes; then
      echo "We'll try to install zsh, then re-run this script!"
      if is_osx; then
        brew install zsh
      elif is_linux; then
        sudo apt-get install zsh
      fi
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
    chsh -s $(which zsh)
  fi

  $DOTFILES_DIR/iterm/powerline/fonts/install.sh

  ok
}

function _setup_zinit() {
  bot "Updating zinit"

  zsh -ic 'zinit self-update; zinit update'

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

    # If we want to uninstall it, just remove the ~/.zprezto folder
  else
    cd $HOME/.zprezto/
    git stash push -q
    git pull && git submodule update --init --recursive
    git stash pop -q
  fi

  ok
}

function _setup_prezto() {
  bot "Setting up prezto"

  # Install Powerline theme
  ln -fs $DOTFILES_DIR/zsh/themes/powerlevel9k $HOME/.zprezto/modules/prompt/external/powerlevel9k
  ln -fs $DOTFILES_DIR/zsh/themes/powerlevel9k/powerlevel9k.zsh-theme $HOME/.zprezto/modules/prompt/functions/prompt_powerlevel9k_setup

  ok
}
