#!/usr/bin/env bash

function get_os() {
  declare -r OS_NAME="$(uname -s)"

  if [ "$OS_NAME" == "Darwin" ]; then
    echo "osx"
    elif [ "$OS_NAME" == "Linux" ]; then
    echo "linux"
  else
    echo "unknown"
  fi
}

function confirm_execution {
  while true; do
    read -p "Warning: this will overwrite your current dotfiles. Continue? [y/n] " yn
    case $yn in
      [Yy]* ) break;;
      [Nn]* ) exit;;
      * ) echo "Please answer yes or no.";;
    esac
  done
}

function execute() {
  $1 &> /dev/null
  result $? "${2:-$1}"
}

function symbolic_link() {
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

function move_existing_dotfiles() {
  bot "Move any existing dotfiles in homedir to ~/.dotfiles_old directory if needed"

  # Create dotfiles_old for backup in homedir
  DOTFILES_BACKUP_DIR=~/.dotfiles_old
  mkdir -p $DOTFILES_BACKUP_DIR

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

function install_dotfiles() {
  local i=''
  local sourceFile=''
  local targetFile=''

  bot "Creating symbolic links for config files if needed"
  for i in ${FILES_TO_SYMLINK[@]}; do
    sourceFile="$DOTFILES_DIR/$i"
    targetFile="$HOME/.$(printf "%s" "$i" | sed "s/.*\/\(.*\)/\1/g")"

    symbolic_link $sourceFile $targetFile
  done
  ok

  unset FILES_TO_SYMLINK

  # Copy binaries
  mkdir -p $HOME/bin

  bot "Creating symbolic links for binaries in ~/bin if needed"
  for i in ${BINARIES[@]}; do
    sourceFile="$DOTFILES_DIR/bin/$i"
    targetFile="$HOME/bin/$(printf "%s" "$i" | sed "s/.*\/\(.*\)/\1/g")"

    symbolic_link $sourceFile $targetFile

    bot "Changing access permissions for binary script :: ~/bin/${i##*/}"
    chmod +rwx $HOME/bin/${i##*/}
  done
  ok

  unset BINARIES
}

function install_zsh () {
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
