#!/usr/bin/env bash

function install_linux_packages() {
  error "Linux support not implemented yet, pending to install some packages, see lib/osx.sh"
  error "Check if this could be useful http://linuxbrew.sh/ or just use apt commands"

  _install_atom
}

# # Needed just for linux OS (pending to be tested)
# declare -a APT_GET_APPS=(
#   python-pip # To install the PIP_APPS
#   spotify-client # https://www.spotify.com/ie/download/linux/
#   atom # http://tipsonubuntu.com/2016/08/05/install-atom-text-editor-ubuntu-16-04/
#   zsh # https://gist.github.com/tsabat/1498393
#   intellij-idea-community # https://itsfoss.com/install-intellij-ubuntu-linux/
# )

function _install_atom_packages() {
  for pkg in ${ATOM_PACKAGES[@]}; do
    if [[ ! -d "$HOME/.atom/packages/$pkg" ]]
    then
      warn "[atom] Package '$pkg' is not installed"
      apm install $pkg
    else
      ok "[atom] Package '$pkg' is already installed"
    fi
  done
  unset ATOM_PACKAGES
}

function _install_atom() {
  bot "Checking atom packages ..."

  if ! test $(which atom)
  then
    error "atom not installed"
  else
    _install_atom_packages
  fi

  ok
}
