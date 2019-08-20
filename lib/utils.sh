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

function is_first_execution() {
  if [ $INSTALLATION_MODE == "install" ]; then
    return
  fi

  false
}

function is_osx() {
  declare -r OS_NAME="$(uname -s)"
  if [ $OS_NAME == "Darwin" ]; then
    return
  fi

  false
}

function is_linux() {
  declare -r OS_NAME="$(uname -s)"
  if [ $OS_NAME == "Linux" ]; then
    return
  fi

  false
}

function execute() {
  $1 &> /dev/null
  result $? "${2:-$1}"
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
