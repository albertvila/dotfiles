#!/usr/bin/env bash
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
