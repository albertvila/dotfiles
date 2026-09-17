#!/usr/bin/env bash

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

  # Store screenshots on Downloads folder
  defaults write com.apple.screencapture location ~/Downloads

  # dark mode
  defaults write "Apple Global Domain" "AppleInterfaceStyle" "Dark"

  # stop itunes to autorun when a device is connected
  defaults write com.apple.iTunesHelper ignore-devices 1

  # Disable show recent application on Dock
  defaults write com.apple.dock show-recents -bool FALSE

  # Setting default language English
  defaults write NSGlobalDomain AppleLocale en_ES

  killall Dock Finder SystemUIServer

  ok
}

# [Some brew commands]
# brew outdated -> list outdated packages
# brew upgrade -> upgrade all
# brew pin mysql -> keep mysql packages to the current version to avoid upgrading it
# brew upgrade mysql
function _install_brew() {
  bot "Checking brew packages ..."

  brew update

  # Install brew packages
  for pkg in ${BREW_APPS[@]}; do
    pkg_name="${pkg##*/}"
    if brew list --formula -1 | grep -q "^${pkg_name}\$"; then
      ok "[brew] Package '$pkg' is already installed"

      # Checking if the package needs update
      if brew outdated --quiet | grep -q "^${pkg_name}"; then
        warn "[brew] Package '$pkg' is not up to date, updating it ..."
        brew upgrade "$pkg"
      fi
    else
      warn "[brew] Package '$pkg' is not installed"
      brew install "$pkg"
    fi
  done
  unset BREW_APPS

  ok
}

function _install_brew_cask() {
  bot "Checking brew cask packages ..."

  # install homebrew
  if [[ $(command -v brew) == "" ]]; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi

  # Install HomeBrew casks
  brew tap aws/tap
  brew tap databricks/tap
  brew tap mobile-dev-inc/tap
  brew trust --formula mobile-dev-inc/tap/maestro
  brew tap anomalyco/tap
  brew trust --formula anomalyco/tap/opencode

  # Install brew cask packages
  for pkg in ${BREW_CASK_APPS[@]}; do
    pkg_name="${pkg##*/}"
    if brew list --cask -1 | grep -q "^${pkg_name}$"; then
      ok "[brew cask] Package '$pkg' is already installed"

      # Checking if the package needs update
      if brew outdated --cask --quiet | grep -q "^${pkg_name}"; then
        warn "[brew cask] Package '$pkg' is not up to date, updating it ..."
        brew reinstall --cask "$pkg"
      fi
    else
      warn "[brew cask] Package '$pkg' is not installed"
      brew install --cask "$pkg"
    fi
  done
  unset BREW_CASK_APPS

  ok
}

function _install_pip() {
  bot "Checking pip packages ..."

  if [[ $(command -v pip) == "" ]]; then
    bot "Going to install pip, this command requires sudo"
    curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py && python3 get-pip.py
  else
    pip install --upgrade --user pip
  fi

  # One batch, always upgraded: pins travel with the package name (e.g.
  # isort<8 for lm-pyconv), so the resolver upgrades within constraints.
  if [[ ${#PIP_APPS[@]} -gt 0 ]]; then
    pip install --user --upgrade "${PIP_APPS[@]}"
  fi
  unset PIP_APPS

  ok
}

function _install_app_store_apps() {
  bot "Checking app store apps ..."

  for app in ${APP_STORE_APPS[@]}; do
    # mas list can miss apps installed under a different Apple ID, so we
    # use mas install as source of truth: it prints "Already installed"
    # when the app is present regardless of which account installed it.
    local install_output
    install_output=$(mas install "$app" 2>&1)

    if echo "$install_output" | grep -qi "already installed"; then
      ok "[app store] App '$app' already installed"

      if mas outdated | grep -q "^${app}"; then
        warn "[app store] App '$app' is not up to date, updating it ..."
        mas upgrade "$app"
      fi
    elif echo "$install_output" | grep -qi "Installed\|Downloading"; then
      ok "[app store] App '$app' installed successfully"
    else
      error "[app store] Failed to install app '$app': $install_output"
    fi
  done
  unset APP_STORE_APPS

  ok
}

function _install_npm() {
  bot "Checking npm packages ..."

  for pkg in ${NPM_PACKAGES[@]}; do
    if npm ls -g "${pkg}" | grep "${pkg}"; then
      ok "[npm] Package '$pkg' is already installed"

      if which ncu &>/dev/null && ncu -g -f "${pkg}" | grep "${pkg}"; then
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

