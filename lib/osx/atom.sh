#!/usr/bin/env bash
bot "Checking atom packages ..."

function install_atom_packages() {
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

if ! test $(which atom)
then
  error "atom not installed"
else
  install_atom_packages
fi

ok
