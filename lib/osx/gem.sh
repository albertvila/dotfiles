#!/usr/bin/env bash
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
