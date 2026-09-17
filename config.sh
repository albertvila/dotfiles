#!/usr/bin/env bash

declare -a BREW_APPS=(
  awscli
  bat
  coreutils
  direnv
  fish
  gh
  git
  gnupg # To generate GPG keys for github (https://help.github.com/articles/generating-a-new-gpg-key/)
  gradle
  gradle-completion
  openjdk
  openjdk@11
  jenv
  jq
  nodenv # Node version manager — use `nodenv install <version>` to install Node
  openssl@3
  perltidy
  pinentry-mac
  pre-commit
  ripgrep
  starship
  vim
  yarn
)

declare -a BREW_CASK_APPS=(
  alfred
  dropbox
  firefox
  google-chrome
  leapp
  orbstack # Docker https://orbstack.dev/
  postman
  rectangle
  slack
  spotify
  zoom
)

declare -a PIP_APPS=(
)

declare -a NPM_PACKAGES=(
  eslint # Needed to check js code
  npm-check-updates # Needed to check if the other packages are up to date
  serverless@2.64.1
)

declare -a APP_STORE_APPS=(
  # Please note that it won't allow you to install (or even purchase) an app for the first time: it must already be in the Purchased tab of the App Store, so download it manually first
)

# Check home/.vim/plugins.vim for enabled plugins
# Check setup_osx function from lib/osx.sh for osx defaults
