#!/usr/bin/env bash
bot "Checking brew packages ..."

# install homebrew
which -s brew
if [[ $? != 0 ]] ; then
  /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
else
  brew update
fi

# Install brew packages
brew_apps=(
  coreutils
  vim
  htop
  wget
  gnupg2 # To generate GPG keys for github (https://help.github.com/articles/generating-a-new-gpg-key/)
  tmux
  # ctags # Used by vim plugin https://github.com/majutsushi/tagbar
)

for pkg in ${brew_apps[@]}; do
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
#brew install pkg-config
#brew install pandoc
#brew install chrome-cli
