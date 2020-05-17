#!/usr/bin/env bash

declare -a BREW_APPS=(
  docker-credential-helper-ecr
  hadolint # Dockerfile linter and validation tool (https://github.com/hadolint/hadolint)
  mas # To install appstore apps that are not yet present on brew cask, see APP_STORE_APPS below (https://github.com/mas-cli/mas)
  pyenv
  terraform
)

# Those packages will only be installed on Linux
declare -a APT_GET_APPS=(
)

# Those packages will only be installed on OSX
declare -a BREW_CASK_APPS=(
  calibre
  google-chrome # Moved here because it's already installed on company laptops
  movist
  plex-media-server
  skype
  slack # Moved here because it's already installed on company laptops
  suunto-moveslink
  transmission
)

declare -a GEM_APPS=(
)

declare -a PIP_APPS=(
  autopep8 # Needed by python
  beautysh # Beautifier for sh files (used by atom)
  diagrams # Diagrams as code (https://diagrams.mingrammer.com/)
  flake8 # Python code checker
  isort # Needed by atom if we want to sort python imports
  pylint # Needed by python
)

declare -a YARN_APPS=(
)

declare -a NPM_PACKAGES=(
  alfred-goodreads-workflow
)

declare -a VSCODE_PACKAGES=(
  exiasr.hadolint
  softwaredotcom.swdc-vscode # Code Time (https://www.software.com/)
)

declare -a APP_STORE_APPS=(
  # Please note that it won't allow you to install (or even purchase) an app for the first time: it must already be in the Purchased tab of the App Store, so download it manually first
  918858936 # Airmail (it will only work if it has been paid with your mac account, also you need to set up your app store account first)
  904280696 # Things3
  1475897096 # Jira Cloud
)
