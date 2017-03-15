#!/usr/bin/env bash

function install_osx_packages() {
  _install_brew
  _install_brew_cask
  _install_gem
  _install_pip
  _install_atom
}

function _install_brew() {
  bot "Checking brew packages ..."

  # install homebrew
  which -s brew
  if [[ $? != 0 ]] ; then
    /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
  else
    brew update
  fi

  # Install brew packages
  for pkg in ${BREW_APPS[@]}; do
    if brew list -1 | grep -q "^${pkg}\$"; then
      ok "[brew] Package '$pkg' is already installed"
    else
      warn "[brew] Package '$pkg' is not installed"
      if [ $pck == "vim" ]; then
        brew install "$pkg" --with-lua
      fi
      brew install "$pkg"
    fi
  done

  if vim --version | egrep -q '\-lua'; then
    error "[brew] Vim package installed without lua support. Lua support is needed for some plugins. Run:"
    error "brew unlink vim"
    error "brew install vim --with-lua"
  fi

  ok
}
#brew install pkg-config
#brew install pandoc
#brew install chrome-cli

function _install_brew_cask() {
  bot "Checking brew cask packages ..."

  # Install Caskroom
  brew tap caskroom/cask
  brew tap caskroom/versions

  # Install brew cask packages
  for pkg in ${BREW_CASK_APPS[@]}; do
    if brew cask list -1 | grep -q "^${pkg}"; then
      ok "[brew cask] Package '$pkg' is already installed"
    else
      warn "[brew cask] Package '$pkg' is not installed"
      brew cask install "$pkg"
    fi
  done

  ok
}

function _install_gem() {
  bot "Checking gem packages ..."

  # Install gem apps
  for pkg in ${GEM_APPS[@]}; do
    if gem list | grep "^${pkg}"; then
      ok "[gem] Package '$pkg' is already installed"
    else
      warn "[gem] Package '$pkg' is not installed"
      gem install "$pkg"
    fi
  done

  ok
}

function _install_pip() {
  bot "Checking pip packages ..."

  # Install pip apps
  for pkg in ${PIP_APPS[@]}; do
    if pip list --format=legacy | grep "^${pkg}"; then
      ok "[pip] Package '$pkg' is already installed"
    else
      warn "[pip] Package '$pkg' is not installed"
      pip install "$pkg"
    fi
  done

  ok
}

function _install_atom_packages() {
  for pkg in ${ATOM_PACKAGES[@]}; do
    if [[ ! -d "$HOME/.atom/packages/$package" ]]
    then
      warn "[atom] Package '$pkg' is not installed"
      apm install $package
    else
      ok "[atom] Package '$pkg' is already installed"
    fi
  done
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
