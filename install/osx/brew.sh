#!/usr/bin/env bash
echo "Checking brew packages ..."

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
    print_success "[brew] Package '$pkg' is already installed"
  else
    echo "[brew] Package '$pkg' is not installed"
    if [ $pck == "vim" ]; then
        brew install "$pkg" --with-lua
    fi
    brew install "$pkg"
  fi
done

if vim --version | egrep -q '\-lua'; then
    print_error "[brew] Vim package installed without lua support. Lua support is needed for some plugins. Run:"
    print_error "brew unlink vim"
    print_error "brew install vim --with-lua"
fi

print_done
#brew install pkg-config
#brew install pandoc
#brew install chrome-cli
