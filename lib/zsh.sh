#!/usr/bin/env bash

function install_zsh() {
  _install_zsh

  # Pending to ask if user wants to install oh-my-zsh or prezto
  #_install_oh_my_zsh
  #_setup_oh_my_zsh

  _install_prezto
  _setup_prezto

  _setup_zsh
}

function _install_zsh() {
  bot "Installing zsh if needed"

  # Test to see if zshell is installed.  If it is:
  if [ -f /bin/zsh -o -f /usr/bin/zsh ]; then
    ok "zsh is already installed"
  else
    ask_for_confirmation "Zsh not found, zsh installation has not been tested, do you wanna proceed?"
    if answer_is_yes; then
      echo "We'll try to install zsh, then re-run this script!"
      os=$(get_os)
      if [ $os == "osx" ]; then
        brew install zsh
        elif [ $os == "linux" ]; then
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

  # mkdir -p $HOME/.tmuxinator
  # ln -fs "$DOTFILES_DIR/tmux/titi.yml" $HOME/.tmuxinator/titi.yml

  $DOTFILES_DIR/iterm/powerline/fonts/install.sh

  ok
}

# https://github.com/robbyrussell/oh-my-zsh
function _install_oh_my_zsh() {
  bot "Installing oh_my_zsh if needed"

  # Install Oh My Zsh if it isn't already present
  if [[ ! -d $HOME/.oh-my-zsh/ ]]; then
    sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"

    # If we want to uninstall it
    #sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/uninstall.sh)"
  fi

  ok
}

function _setup_oh_my_zsh() {
  bot "Setting up oh_my_zsh"

  # Install Zsh settings
  ln -fs $DOTFILES_DIR/zsh/themes/powerlevel9k $HOME/.oh-my-zsh/themes/powerlevel9k

  ok
}

# https://github.com/sorin-ionescu/prezto
function _install_prezto() {
  bot "Intalling prezto if needed"

  # Install Prezo if it isn't already present
  if [[ ! -d $HOME/.zprezto/ ]]; then
    git clone --recursive https://github.com/sorin-ionescu/prezto.git "${ZDOTDIR:-$HOME}/.zprezto"

    # TODO The following commands fail under this bash script, but they work if you run them manually on terminal
    setopt EXTENDED_GLOB
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
