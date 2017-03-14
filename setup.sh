#!/bin/bash

# It symlinks all the dotfiles to ~/, also some binaries to ~/bin
# This is safe to run multiple times and will prompt you about anything unclear
# A backup is kept under ~/.dotfiles_old

# include my library helpers for colorized echo and require_brew, etc
source ./lib/echos.sh

###############################################################################
# Utils                                                                       #
###############################################################################
get_os() {
  declare -r OS_NAME="$(uname -s)"

  if [ "$OS_NAME" == "Darwin" ]; then
    echo "osx"
    elif [ "$OS_NAME" == "Linux" ]; then
    echo "linux"
  else
    echo "unknown"
  fi
}

execute() {
  $1 &> /dev/null
  result $? "${2:-$1}"
}

symbolic_link() {
  sourceFile=$1
  targetFile=$2

  if [ ! -e "$targetFile" ]; then
    execute "ln -fs $sourceFile $targetFile" "$targetFile → $sourceFile"
    elif [ "$(readlink "$targetFile")" == "$sourceFile" ]; then
    ok "Link already exists for $targetFile"
  else
    ask_for_confirmation "'$targetFile' already exists, do you want to overwrite it?"
    if answer_is_yes; then
      rm -rf "$targetFile"
      execute "ln -fs $sourceFile $targetFile" "$targetFile → $sourceFile"
    else
      error "$targetFile → $sourceFile"
    fi
  fi
}

move_existing_dotfiles() {
  echo "Move any existing dotfiles in homedir to ~/.dotfiles_old directory if needed"
  # Move any existing dotfiles in homedir to dotfiles_old directory
  for i in ${FILES_TO_SYMLINK[@]}; do
    file="$HOME/.${i##*/}"

    # Only move the file if it's not a symbolic link
    if [ -f $file ] && [ ! -L $file ]; then
      mv $file $DOTFILES_BACKUP_DIR
      if [ ! $? ]; then
        ok "$file moved to $DOTFILES_BACKUP_DIR"
      else
        error "Error moving $file to $DOTFILES_BACKUP_DIR"
      fi
    fi
  done
  ok
}

install_dotfiles() {
  local i=''
  local sourceFile=''
  local targetFile=''

  echo "Creating symbolic links for config files if needed"
  for i in ${FILES_TO_SYMLINK[@]}; do
    sourceFile="$DOTFILES_DIR/$i"
    targetFile="$HOME/.$(printf "%s" "$i" | sed "s/.*\/\(.*\)/\1/g")"

    symbolic_link $sourceFile $targetFile
  done
  ok

  unset FILES_TO_SYMLINK

  # Copy binaries
  mkdir -p $HOME/bin

  echo "Creating symbolic links for binaries in ~/bin if needed"
  for i in ${BINARIES[@]}; do
    sourceFile="$DOTFILES_DIR/bin/$i"
    targetFile="$HOME/bin/$(printf "%s" "$i" | sed "s/.*\/\(.*\)/\1/g")"

    symbolic_link $sourceFile $targetFile

    echo "Changing access permissions for binary script :: ~/bin/${i##*/}"
    chmod +rwx $HOME/bin/${i##*/}
  done
  ok

  unset BINARIES
}

install_zsh () {
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
}

###############################################################################
# Execution starts here                                                       #
###############################################################################

# Warn user this script will overwrite current dotfiles
while true; do
  read -p "Warning: this will overwrite your current dotfiles. Continue? [y/n] " yn
  case $yn in
    [Yy]* ) break;;
    [Nn]* ) exit;;
    * ) echo "Please answer yes or no.";;
  esac
done

# Get current dir (so run this script from anywhere)
DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Create dotfiles_old for backup in homedir
DOTFILES_BACKUP_DIR=~/.dotfiles_old
echo "Creating $DOTFILES_BACKUP_DIR for backup of any existing dotfiles in ~..."
mkdir -p $DOTFILES_BACKUP_DIR
ok

declare -a FILES_TO_SYMLINK=(
  'vim'
  'vim/vimrc'
  'git/gitignore'
  'misc/isort.cfg'
  'zsh/zshrc'
  'tmux/tmux.conf'
  'tmux/tmuxinator.zsh'
)

declare -a BINARIES=(
)

move_existing_dotfiles

# Package managers & packages
os=$(get_os)
if [ $os == "blaosx" ]; then
  . "$DOTFILES_DIR/install/osx/brew.sh"
  . "$DOTFILES_DIR/install/osx/brew_cask.sh"
  . "$DOTFILES_DIR/install/osx/gem.sh"
  . "$DOTFILES_DIR/install/osx/pip.sh"
  . "$DOTFILES_DIR/install/osx/atom.sh"
else
    error "Not implemented yet, pending to install some packages, see install/osx folder"
fi

install_dotfiles
install_zsh

###############################################################################
# Zsh                                                                         #
###############################################################################

# Install Zsh settings
ln -fs $DOTFILES_DIR/zsh/themes/powerlevel9k $HOME/.oh-my-zsh/themes/powerlevel9k

DOTFILES_CUSTOM_DIR="$DOTFILES_DIR/zsh/custom/"
for entry in `ls $DOTFILES_CUSTOM_DIR`; do
    ln -fs $DOTFILES_DIR/zsh/custom/$entry $HOME/.oh-my-zsh/custom/$entry
done

###############################################################################
# Git                                                                         #
###############################################################################

git config --global push.default simple
git config --global core.editor /usr/bin/vim
git submodule update --init
git config --global core.excludesfile '~/.gitignore'

###############################################################################
# Terminal & iTerm 2 & tmuxinator                                             #
###############################################################################

mkdir -p $HOME/.tmuxinator
ln -fs "$DOTFILES_DIR/tmux/titi.yml" $HOME/.tmuxinator/titi.yml

./iterm/powerline/fonts/install.sh

# initialize Vim plugins
echo "Installing vim plugins"
vim +PluginInstall +qall > /dev/null 2>&1
ok
mkdir -p $HOME/.vim/colors
ln -fs $HOME/.vim/bundle/vim-colors-solarized/colors/solarized.vim $HOME/.vim/colors/solarized.vim

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

# Reload zsh settings
#source ~/.zshrc
