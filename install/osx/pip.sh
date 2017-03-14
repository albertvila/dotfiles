#!/usr/bin/env bash
bot "Checking pip packages ..."

# Install pip apps
pip_apps=(
  isort # Needed by atom if we want to sort python imports
  beautysh # Beautifier for sh files (used by atom)
  flake8 # Python code checker
)

for pkg in ${pip_apps[@]}; do
  if pip list --format=legacy | grep "^${pkg}"; then
    ok "[pip] Package '$pkg' is already installed"
  else
    warn "[pip] Package '$pkg' is not installed"
    pip install "$pkg"
  fi
done

ok
