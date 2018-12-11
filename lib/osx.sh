#!/usr/bin/env bash

function install_osx_packages() {
  _install_brew
  _install_brew_cask
  _install_gem
  _install_pip
  _install_yarn
  _install_atom
  _install_app_store_apps
  _install_npm
  _install_vsc
  _setup_osx
}

function _setup_osx() {
  bot "Setting up osx ..."

  # show full paths in Finder
  defaults write com.apple.finder _FXShowPosixPathInTitle -bool YES

  # Disable and kill Dashboard
  defaults write com.apple.dashboard mcx-disabled -boolean YES

  # Show all file extensions on Finder
  defaults write NSGlobalDomain AppleShowAllExtensions -bool true

  # Disable natural trackpad scrolling (TODO however it seems it does not work)
  defaults write NSGlobalDomain com.apple.swipescrolldirection -bool false

  # Don't automatically rearrange Spaces
  defaults write com.apple.dock mru-spaces -bool false

  # Set list view as preferred Finder view
  defaults write com.apple.finder FXPreferredViewStyle -string 'Nlsv'

  # Search the current folder by default
  defaults write com.apple.finder FXDefaultSearchScope -string 'SCcf'

  # Remove all applications from Dock
  defaults write com.apple.dock persistent-apps -array

  # Set bottom right hot corner to show/hide desktop
  defaults write com.apple.dock wvous-br-corner -int 4
  defaults write com.apple.dock wvous-br-modifier -int 0

  # Update clock to show current date and current day of the week and 24h format
  defaults write com.apple.menuextra.clock DateFormat 'EEE MMM d  H:mm a'

  # Show the ~/Library directory in Finder
  chflags nohidden "${HOME}/Library"

  # Show finder status bar
  defaults write com.apple.finder ShowStatusBar -bool true

  # Show home folder on new Finder window instead of All my files
  defaults write com.apple.finder NewWindowTarget PfHm

  # Put dock on the left
  defaults write com.apple.dock orientation -string left

  # Avoid creating .DS_Store files on network volumes
  defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true

  # Disable the warning when changing a file extension
  defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

  # Setting iterm custom folder config
  sed -i.bak "s;/Users/albert/workspace/dotfiles;${DOTFILES_DIR};g" "${DOTFILES_DIR}"/iterm/com.googlecode.iterm2.plist
  defaults write com.googlecode.iterm2 "PrefsCustomFolder" -string "${DOTFILES_DIR}/iterm"
  defaults write com.googlecode.iterm2 "LoadPrefsFromCustomFolder" -bool true
  ok "iTerm's custom config folder set"

  killall Dock Finder SystemUIServer

  installation_mode=$(get_installation_mode)
  if [ $installation_mode == "install" ]; then

    # Install the Solarized Dark theme for iTerm
    open "${DOTFILES_DIR}/iterm/themes/Solarized Dark.itermcolors"
  fi

  ok
}

# [Some brew commands]
# brew outdated -> list outdated packages
# brew upgrade -> upgrade all
# brew pin mysql -> keep mysql packages to the current version to avoid upgrading it
# brew upgrade mysql
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

      # Checking if the package needs update
      if brew outdated --quiet | grep -q "^${pkg}\$"; then
        warn "[brew] Package '$pkg' is not up to date, updating it ..."
        brew upgrade "$pkg"
      fi
    else
      warn "[brew] Package '$pkg' is not installed"
      if [ $pkg == "vim" ]; then
        brew install "$pkg" --with-lua
      fi
      brew install "$pkg"
    fi
  done
  unset BREW_APPS

  if vim --version | egrep -q '\-lua'; then
    error "[brew] Vim package installed without lua support. Lua support is needed for some plugins. Run:"
    error "brew unlink vim"
    error "brew install vim --with-lua"
  fi

  ok
}

function _install_brew_cask() {
  bot "Checking brew cask packages ..."

  # Install Caskroom
  brew tap caskroom/cask
  brew tap caskroom/versions
  brew tap caskroom/drivers

  # Install brew cask packages
  for pkg in ${BREW_CASK_APPS[@]}; do
    if brew cask list -1 | grep -q "^${pkg}"; then
      ok "[brew cask] Package '$pkg' is already installed"

      # Checking if the package needs update
      if brew cask outdated --quiet | grep -q "^${pkg}"; then
        warn "[brew cask] Package '$pkg' is not up to date, updating it ..."
        brew cask reinstall "$pkg"
      fi
    else
      warn "[brew cask] Package '$pkg' is not installed"
      brew cask install "$pkg"
    fi
  done
  unset BREW_CASK_APPS

  ok "[brew cask] going to upgrade brew cask"
  brew cask upgrade

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
  unset GEM_APPS

  ok
}

function _install_pip() {
  bot "Checking pip packages ..."

  which -s pip
  if [[ $? != 0 ]] ; then
    bot "Going to install pip, if it does not work, maybe it's because the command needs sudo"
    easy_install pip
  else
    pip install --upgrade --user pip
  fi

  # Install pip apps
  for pkg in ${PIP_APPS[@]}; do
    if pip list | grep "^${pkg}"; then
      ok "[pip] Package '$pkg' is already installed"

      # Checking if the package needs update
      if pip list --outdated | grep "^${pkg}"; then
        warn "[pip] Package '$pkg' is not up to date, updating it ..."
        pip install "$pkg" --upgrade --user
      fi

    else
      warn "[pip] Package '$pkg' is not installed"
      pip install "$pkg" --user
    fi
  done
  unset PIP_APPS

  ok
}

function _install_yarn() {
  bot "Checking yarn packages ..."

  # Install yarn apps
  for pkg in ${YARN_APPS[@]}; do
    if yarn global list | grep "^info \"${pkg}" | awk -F\" '{ print $2 }'; then
      ok "[yarn] Package '$pkg' is already installed"

      # TODO Coudn't find a way to know if the package was outdated
      warn "[yarn] Going to check if '$pkg' needs an update"
      yarn global upgrade $pkg
    else
      warn "[yarn] Package '$pkg' is not installed"
      yarn global add "$pkg"
    fi
  done
  unset YARN_APPS

  ok
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

function _install_atom_packages() {
  for pkg in ${ATOM_PACKAGES[@]}; do
    if [[ ! -d "$HOME/.atom/packages/$pkg" ]]
    then
      warn "[atom] Package '$pkg' is not installed"
      apm install $pkg
    else
      ok "[atom] Package '$pkg' is already installed"
      if apm upgrade -list | grep "${pkg}"; then
        warn "[atom] Package '${pkg}' is not up to date, updating it ..."
        apm upgrade $pkg --no-confirm
      fi
    fi
  done
  unset ATOM_PACKAGES
}

function _install_app_store_apps() {
  bot "Checking app store apps ..."

  for app in ${APP_STORE_APPS[@]}; do
    if mas list | grep "^${app}"; then
      ok "[app store] App $app already installed"

      # Checking if the app needs update
      if mas outdated | grep "^${pkg}"; then
        warn "[app store] App '$pkg' is not up to date, updating it ..."
        mas install $app
      fi
    else
      warn "[app store] App '$app' is not installed"
      mas install $pkg
    fi
  done
  unset ATOM_PACKAGES

  ok
}

function _install_npm() {
  bot "Checking npm packages ..."

  for pkg in ${NPM_PACKAGES[@]}; do
    if npm ls -g ${pkg} | grep "${pkg}"; then
      ok "[npm] Package '$pkg' is already installed"

      if which ncu &>/dev/null && ncu -g -f ${pkg} | grep "${pkg}"; then
        warn "[npm] Package '$pkg' is not up to date, updating it ..."
        npm install -g "$pkg"
      fi
    else
      warn "[npm] Package '$pkg' is not installed"
      npm install -g "$pkg"
    fi
  done
  unset NPM_PACKAGES

  ok
}

function _install_vsc() {
  bot "Checking visual studio code packages ..."

  ln -fs $DOTFILES_DIR/vscode/settings.json ~/Library/Application\ Support/Code/User/settings.json

  if ! test $(which code)
  then
    error "visual studio code not installed"
  else
    _install_vsc_packages
  fi

  ok
}

function _install_vsc_packages() {
  for pkg in ${VSCODE_PACKAGES[@]}; do
    if code --list-extensions | grep "${pkg}"; then
      ok "[vsc] Package '$pkg' is already installed"
      code --install-extension --force $pkg
    else
      warn "[vsc] Package '$pkg' is not installed"
      code --install-extension $pkg
    fi
  done
  unset VSCODE_PACKAGES
}