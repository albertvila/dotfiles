#!/bin/bash

# It symlinks all the dotfiles (and .atom/) to ~/, also some binaries to ~/bin
# This is safe to run multiple times and will prompt you about anything unclear
# A backup is kept under ~/.dotfiles_old

###############################################################################
# Utils                                                                       #
###############################################################################
get_os() {
  declare -r OS_NAME="$(uname -s)"

  if [ "$OS_NAME" == "Darwin" ]; then
    echo "osx"
    elif [ "$OS_NAME" == "Linux" ] && [ -e "/etc/lsb-release" ]; then
    echo "linux"
  fi
}

answer_is_yes() {
  [[ "$REPLY" =~ ^[Yy]$ ]] && return 0 || return 1
}

ask_for_confirmation() {
  print_question "$1 (y/n) "
  read -n 1
  printf "\n"
}

execute() {
  $1 &> /dev/null
  print_result $? "${2:-$1}"
}

print_error() {
  # Print output in red
  printf "\e[0;31m  [✖] $1 $2\e[0m\n"
}

print_question() {
  # Print output in yellow
  printf "\e[0;33m  [?] $1\e[0m"
}

print_success() {
  # Print output in green
  printf "\e[0;32m  [✔] $1\e[0m\n"
}

print_result() {
  [ $1 -eq 0 ] \
  && print_success "$2" \
  || print_error "$2"

  [ "$3" == "true" ] && [ $1 -ne 0 ] \
  && exit
}

# donut \xf0\x9f\x8d\xa9
# penguin \xf0\x9f\x90\xa7\x31
# apple \xf0\x9f\x8d\x8f
print_done() {
  icon=$'\xf0\x9f\x8d\xa9'
  printf "$icon  done\n"
}

symbolic_link() {
  sourceFile=$1
  targetFile=$2

  if [ ! -e "$targetFile" ]; then
    execute "ln -fs $sourceFile $targetFile" "$targetFile → $sourceFile"
    elif [ "$(readlink "$targetFile")" == "$sourceFile" ]; then
    print_success "$targetFile → $sourceFile"
  else
    ask_for_confirmation "'$targetFile' already exists, do you want to overwrite it?"
    if answer_is_yes; then
      rm -rf "$targetFile"
      execute "ln -fs $sourceFile $targetFile" "$targetFile → $sourceFile"
    else
      print_error "$targetFile → $sourceFile"
    fi
  fi
}

move_existing_dotfiles() {
  echo "Move any existing dotfiles in homedir to ~/.dotfiles_old directory if needed"
  # Move any existing dotfiles in homedir to dotfiles_old directory
  for i in ${FILES_TO_SYMLINK[@]}; do
    file=${i##*/}

    # Only move the file if it's not a symbolic link
    if [ ! -h "$HOME/.$file" ]; then
      echo "Moving the .$file dotfile from ~ to $DOTFILES_BACKUP_DIR"
      mv ~/.$file $DOTFILES_BACKUP_DIR
    fi
  done
  print_done
}

install_dotfiles() {
  local i=''
  local sourceFile=''
  local targetFile=''

  echo "Creating symbolic links for config files"
  for i in ${FILES_TO_SYMLINK[@]}; do
    sourceFile="$DOTFILES_DIR/$i"
    targetFile="$HOME/.$(printf "%s" "$i" | sed "s/.*\/\(.*\)/\1/g")"

    symbolic_link $sourceFile $targetFile
  done
  print_done

  unset FILES_TO_SYMLINK

  # Copy binaries
  mkdir -p $HOME/bin

  echo "Creating symbolic links for binaries in ~/bin"
  for i in ${BINARIES[@]}; do
    sourceFile="$DOTFILES_DIR/bin/$i"
    targetFile="$HOME/bin/$(printf "%s" "$i" | sed "s/.*\/\(.*\)/\1/g")"

    symbolic_link $sourceFile $targetFile

    echo "Changing access permissions for binary script :: ~/bin/${i##*/}"
    chmod +rwx $HOME/bin/${i##*/}
  done
  print_done

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
    echo "TODO PENDING, use the get_os method"

    # If zsh isn't installed, get the platform of the current machine
    platform=$(uname);
    # If the platform is Linux, try an apt-get to install zsh and then recurse
    if [[ $platform == 'Linux' ]]; then
      if [[ -f /etc/redhat-release ]]; then
        echo "linux"
        #sudo yum install zsh
        #install_zsh
      fi
      if [[ -f /etc/debian_version ]]; then
        echo "debian"
        #sudo apt-get install zsh
        #install_zsh
      fi
      # If the platform is OS X, tell the user to install zsh :)
      elif [[ $platform == 'Darwin' ]]; then
      echo "We'll install zsh, then re-run this script!"
      #brew install zsh
      exit
    fi
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
print_done

# Atom editor settings
#echo "Copying Atom settings.."
#mv -f ~/.atom ~/dotfiles_old/
#ln -s $HOME/dotfiles/atom ~/.atom
#print_done

declare -a FILES_TO_SYMLINK=(
  #'shell/shell_aliases'
  #'shell/shell_config'
  #'shell/shell_exports'
  #'shell/shell_functions'
  #'shell/bash_profile'
  #'shell/bash_prompt'
  #'shell/bashrc'
  #'shell/zshrc'
  #'shell/ackrc'
  #'shell/curlrc'
  #'shell/gemrc'
  #'shell/inputrc'
  #'shell/screenrc'

  #'git/gitattributes'
  #'git/gitconfig'
  #'git/gitignore'
  'vim'
  'vim/vimrc'
  'git/gitignore'
  'misc/isort.cfg'
  'zsh/zshrc'
  'tmux/tmux.conf'
  'tmux/tmuxinator.zsh'
)

declare -a BINARIES=(
  'batcharge.py'
)

# FILES_TO_SYMLINK="$FILES_TO_SYMLINK .vim bin" # add in vim and the binaries

move_existing_dotfiles

# Package managers & packages

# . "$DOTFILES_DIR/install/brew.sh"
# . "$DOTFILES_DIR/install/npm.sh"

os=$(get_os)
#if [ $os == "osx" ]; then
#  . "$DOTFILES_DIR/install/brew_osx.sh"
#fi

install_dotfiles
install_zsh

###############################################################################
# Atom                                                                        #
###############################################################################

# Copy over Atom configs
##cp -r atom/packages.list $HOME/.atom

# Install community packages
##apm list --installed --bare - get a list of installed packages
##apm install --packages-file $HOME/.atom/packages.list

###############################################################################
# Zsh                                                                         #
###############################################################################

# Install Zsh settings
ln -fs $DOTFILES_DIR/zsh/themes/agnoster-albert.zsh-theme $HOME/.oh-my-zsh/themes
ln -fs $DOTFILES_DIR/zsh/custom/zshrc $HOME/.oh-my-zsh/custom/zshrc.zsh

###############################################################################
# Git                                                                         #
###############################################################################

git config --global push.default simple
git config --global alias.dag "log --graph --format='format:%C(yellow)%h%C(reset) %C(blue)\"%an\" <%ae>%C(reset) %C(magenta)%ar%C(reset)%C(auto)%d%C(reset)%n%s' --date-order"
git config --global core.editor /usr/bin/vim
git submodule update --init
git config --global core.excludesfile '~/.gitignore'

###############################################################################
# Terminal & iTerm 2 & tmuxinator                                             #
###############################################################################

ln -fs "$DOTFILES_DIR/tmux/titirrineta.yml" $HOME/.tmuxinator/titirrineta.yml

# initialize Vim plugins
vim +PluginInstall +qall

# Only use UTF-8 in Terminal.app
#defaults write com.apple.terminal StringEncodings -array 4

# Install the Solarized Dark theme for iTerm
#open "${DOTFILES_DIR}/iterm/themes/Solarized Dark.itermcolors"

# Don’t display the annoying prompt when quitting iTerm
#defaults write com.googlecode.iterm2 PromptOnQuit -bool false

# Reload zsh settings
#source ~/.zshrc
