#!/usr/bin/env bash
echo "Checking brew cask/brew/pip packages ..."

# install homebrew
which -s brew
if [[ $? != 0 ]] ; then
  /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
else
  brew update
fi

# Install Caskroom
brew tap caskroom/cask
brew tap caskroom/versions

# Install brew cask packages
brew_cask_apps=(
  iterm2
  sshfs
  google-chrome
)

for pkg in ${brew_cask_apps[@]}; do
  if brew cask list -1 | grep -q "^${pkg}"; then
    print_success "[brew cask] Package '$pkg' is already installed"
  else
    echo "[brew cask] Package '$pkg' is not installed"
    brew cask install "$pkg"
  fi
done

# Install brew packages
brew_apps=(
  coreutils
  vim
  htop
  wget
  gnupg2 # To generate GPG keys for github (https://help.github.com/articles/generating-a-new-gpg-key/)
  tmux
)

for pkg in ${brew_apps[@]}; do
  if brew list -1 | grep -q "^${pkg}\$"; then
    print_success "[brew] Package '$pkg' is already installed"
  else
    echo "[brew] Package '$pkg' is not installed"
    brew install "$pkg"
  fi
done

# Install pip apps
pip_apps=(
  isort # Needed by atom if we want to sort python imports
  beautysh # Beautifier for sh files
  flake8 # Python code checker
)

for pkg in ${pip_apps[@]}; do
  if pip list --format=legacy | grep "^${pkg}"; then
    print_success "[pip] Package '$pkg' is already installed"
  else
    echo "[pip] Package '$pkg' is not installed"
    pip install "$pkg"
  fi
done

# Install gem apps
gem_apps=(
  tmuxinator # https://github.com/tmuxinator/tmuxinator
)

for pkg in ${gem_apps[@]}; do
  if gem list | grep "^${pkg}"; then
    print_success "[gem] Package '$pkg' is already installed"
  else
    echo "[gem] Package '$pkg' is not installed"
    gem install "$pkg"
  fi
done

print_done
#brew install pkg-config
#brew install pandoc
#brew install chrome-cli
#brew cask install google-drive
#brew cask install transmit
#brew cask install spectacle
#brew cask install flycut # Clipboard manager for copy/paste (https://github.com/TermiT/Flycut)
#brew cask install java
#brew cask install paintbrush
#brew cask install the-unarchiver
#brew tap homebrew/versions
#brew install gcc49 --enable-cxx
