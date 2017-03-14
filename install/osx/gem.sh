#!/usr/bin/env bash
bot "Checking gem packages ..."

# Install gem apps
gem_apps=(
  tmuxinator # https://github.com/tmuxinator/tmuxinator
)

for pkg in ${gem_apps[@]}; do
  if gem list | grep "^${pkg}"; then
    ok "[gem] Package '$pkg' is already installed"
  else
    warn "[gem] Package '$pkg' is not installed"
    gem install "$pkg"
  fi
done

ok
