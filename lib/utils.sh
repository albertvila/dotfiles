#!/usr/bin/env bash

function start() {
  if [ ! -e "$HOME/.dotfiles" ]; then
    bot "Installing dotfiles for the first time"
  else
    last_updated=$(tail -n 1 "$HOME/.dotfiles")
    blue=$(blue "$last_updated")
    bot "Dotfiles already installed/updated at $blue"
  fi

  if [ ! $FORCE ]; then
    _confirm_execution
  fi
}

function end() {
  echo $(date) >> "$HOME/.dotfiles"
}

function is_osx() {
  [ "$(uname -s)" = "Darwin" ]
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
