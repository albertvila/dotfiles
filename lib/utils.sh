#!/usr/bin/env bash

INSTALLATION_MODE='update'

function start() {
  if [ ! -e "$HOME/.dotfiles" ]; then
    bot "Installing dotfiles for the first time"
    INSTALLATION_MODE='install'
  else
    last_updated=$(sed = $HOME/.dotfiles | sed -n '$p')
    blue=$(blue "$last_updated")
    bot "Dotfiles alreay installed/updated at $blue"
  fi

  _confirm_execution
}

function end() {
  echo $(date) >> "$HOME/.dotfiles"
}

function get_installation_mode() {
  echo $INSTALLATION_MODE
}

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

function execute() {
  $1 &> /dev/null
  result $? "${2:-$1}"
}

function install_os_packages() {
  os=$(get_os)
  if [ $os == "osx" ]; then
    source ./lib/osx.sh
    install_osx_packages
  elif [ $os == "linux"]; then
    source ./lib/osx.sh
    install_linux_packages
  else
    error "OS $os not supported"
    exit;
  fi
}

# Config --global entries configured using the git/gitconfig file
function setup_git() {
  bot "Setting up git config"

  git submodule update --init

  ok
}

function setup_vim() {
  bot "Installing vim plugins and fonts"

  vim +PluginInstall +qall > /dev/null 2>&1
  mkdir -p $HOME/.vim/colors
  ln -fs $HOME/.vim/bundle/vim-colors-solarized/colors/solarized.vim $HOME/.vim/colors/solarized.vim

  ok
}

function _confirm_execution() {
  while true; do
    read -p "Warning: this will overwrite your current dotfiles. Continue? [y/n] " yn
    case $yn in
      [Yy]* ) break ;;
      [Nn]* ) exit ;;
      * ) echo "Please answer yes or no." ;;
    esac
  done
}
