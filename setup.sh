#!/bin/bash

# This is safe to run multiple times and will prompt you about anything unclear
# Check config.sh file to configure dotfiles, plugins and packages

source ./config.sh
source ./lib/echos.sh
source ./lib/utils.sh

confirm_execution

# Get current dir (so run this script from anywhere)
DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

move_existing_dotfiles

# Package managers & packages
os=$(get_os)
if [ $os == "osx" ]; then
  source ./lib/osx.sh
  install_osx_packages
else
  error "Not implemented yet, pending to install some packages, see lib/osx folder"
fi

install_dotfiles
install_zsh

###############################################################################
# Zsh                                                                         #
###############################################################################

bot "Setting up zsh & terminal"
# Install Zsh settings
ln -fs $DOTFILES_DIR/zsh/themes/powerlevel9k $HOME/.oh-my-zsh/themes/powerlevel9k

DOTFILES_CUSTOM_DIR="$DOTFILES_DIR/zsh/custom/"
for entry in `ls $DOTFILES_CUSTOM_DIR`; do
  ln -fs $DOTFILES_DIR/zsh/custom/$entry $HOME/.oh-my-zsh/custom/$entry
done

mkdir -p $HOME/.tmuxinator
ln -fs "$DOTFILES_DIR/tmux/titi.yml" $HOME/.tmuxinator/titi.yml

./iterm/powerline/fonts/install.sh

ok

###############################################################################
# Git                                                                         #
###############################################################################

bot "Setting up git config"
git config --global push.default simple
git config --global core.editor /usr/bin/vim
git submodule update --init
git config --global core.excludesfile '~/.gitignore'
ok

# initialize Vim plugins
bot "Installing vim plugins and fonts"
vim +PluginInstall +qall > /dev/null 2>&1
mkdir -p $HOME/.vim/colors
ln -fs $HOME/.vim/bundle/vim-colors-solarized/colors/solarized.vim $HOME/.vim/colors/solarized.vim
ok

os=$(get_os)
if [ $os == "osx" ]; then
  # show full pathes in Finder
  defaults write com.apple.finder _FXShowPosixPathInTitle -bool YES

  # Disable and kill Dashboard
  # Can be reverted with:
  # defaults write com.apple.dashboard mcx-disabled -boolean NO; killall Doc
  #defaults write com.apple.dashboard mcx-disabled -boolean YES; killall Dock

  # Install the Solarized Dark theme for iTerm
  #open "${DOTFILES_DIR}/iterm/themes/Solarized Dark.itermcolors"
fi
