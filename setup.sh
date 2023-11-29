#!/bin/bash

# This is safe to run multiple times and will prompt you about anything unclear
# Check config.sh file to configure dotfiles, plugins and packages

source ./config.sh
source ./lib/echos.sh
source ./lib/utils.sh
source ./lib/dotfiles.sh
source ./lib/os.sh
source ./lib/zsh.sh

# Parameters
#  -u to define a user
#  -f to force and do not ask for confirmation at the beginning
while getopts ":u:f" opt; do
  case $opt in
    u) USER_PARAM="$OPTARG"
    ;;
    f) FORCE=1
    ;;    \?) echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done

# Get current dir (so run this script from anywhere)
DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DOTFILES_USER="default"

start

if ! is_osx; then
  error "Operating System not supported"
  exit;
fi

install_os_packages
setup_os_packages
install_dotfiles
install_zsh

unset DOTFILES_USER
DOTFILES_USER=$USER_PARAM

if [[ $DOTFILES_USER ]]; then
  source $DOTFILES_DIR/config_$DOTFILES_USER.sh
  install_os_packages
fi

cleanup

end
