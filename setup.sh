#!/bin/bash

# This is safe to run multiple times and will prompt you about anything unclear
# Check config.sh file to configure dotfiles, plugins and packages

source ./config.sh
source ./lib/echos.sh
source ./lib/utils.sh
source ./lib/dotfiles.sh
source ./lib/zsh.sh

# Get current dir (so run this script from anywhere)
DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

start

install_os_packages
install_dotfiles
install_zsh
setup_git
setup_vim
cleanup

end
