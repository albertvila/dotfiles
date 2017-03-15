#!/usr/bin/env bash

function install_zsh() {
  _install_zsh
  _setup_zsh
}

function _setup_zsh() {
  bot "Setting up zsh & terminal"
  # Install Zsh settings
  ln -fs $DOTFILES_DIR/zsh/themes/powerlevel9k $HOME/.oh-my-zsh/themes/powerlevel9k

  DOTFILES_CUSTOM_DIR="$DOTFILES_DIR/zsh/custom/"
  for entry in `ls $DOTFILES_CUSTOM_DIR`; do
    ln -fs $DOTFILES_DIR/zsh/custom/$entry $HOME/.oh-my-zsh/custom/$entry
  done

  mkdir -p $HOME/.tmuxinator
  ln -fs "$DOTFILES_DIR/tmux/titi.yml" $HOME/.tmuxinator/titi.yml

  $DOTFILES_DIR/iterm/powerline/fonts/install.sh

  ok
}

function _install_zsh () {
  bot "Installing zsh if needed"

  # Test to see if zshell is installed.  If it is:
  if [ -f /bin/zsh -o -f /usr/bin/zsh ]; then
    # Install Oh My Zsh if it isn't already present
    if [[ ! -d $HOME/.oh-my-zsh/ ]]; then
      sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"

      # If we want to uninstall it
      #sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/uninstall.sh)"
    fi

    # Set the default shell to zsh if it isn't currently set to zsh
    if [[ ! $(echo $SHELL) == $(which zsh) ]]; then
      chsh -s $(which zsh)
    fi
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
