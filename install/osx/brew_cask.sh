#!/usr/bin/env bash
echo "Checking brew cask packages ..."

# Install Caskroom
brew tap caskroom/cask
brew tap caskroom/versions

# Install brew cask packages
brew_cask_apps=(
  iterm2
  sshfs
  google-chrome
  atom
)

for pkg in ${brew_cask_apps[@]}; do
  if brew cask list -1 | grep -q "^${pkg}"; then
    print_success "[brew cask] Package '$pkg' is already installed"
  else
    echo "[brew cask] Package '$pkg' is not installed"
    brew cask install "$pkg"
  fi
done

ok
