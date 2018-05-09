#!/usr/bin/env bash

declare -a FILES_TO_SYMLINK=(
  'git/gitignore'
  'misc/isort.cfg'
  'tmux/tmux.conf'
  'tmux/tmuxinator.zsh'
  'vim'
  'vim/vimrc'
  'zsh/zpreztorc'
  'zsh/scripts'
  'zsh/zshrc'
)

declare -a BINARIES=()

declare -a BREW_APPS=(
  ack
  awscli
  coreutils
  fasd
  git
  gnupg # To generate GPG keys for github (https://help.github.com/articles/generating-a-new-gpg-key/)
  gradle
  htop
  jenv
  mas # To install appstore apps that are not yet present on brew cask, see APP_STORE_APPS below (https://github.com/mas-cli/mas)
  mysql
  perl-build
  plenv
  sbt # scala build tool
  scala
  terraform
  tmux
  vim
  wget
  yarn
  zookeeper
)

declare -a BREW_CASK_APPS=(
  alfred
  atom
  calibre
  docker
  dropbox
  google-chrome
  intellij-idea-ce
  iterm2
  java
  movist
  plex-media-server
  skype
  slack
  spectacle
  spotify
  suunto-moveslink
  transmission
  # unison # either brew cask or brew, try it before (http://www.cs.haifa.ac.il/~shuly/unison/)
  # vagrant
  # virtualbox
)

declare -a GEM_APPS=(
  # tmuxinator # https://github.com/tmuxinator/tmuxinator
)

declare -a PIP_APPS=(
  beautysh # Beautifier for sh files (used by atom)
  flake8 # Python code checker
  isort # Needed by atom if we want to sort python imports
  pygments
  wakatime
)

declare -a YARN_APPS=(
  mocha
  serverless
)

declare -a ATOM_PACKAGES=(
  atom-beautify
  atom-material-syntax
  atom-material-ui
  busy-signal
  file-icons
  git-plus
  goto-definition
  highlight-selected
  language-gradle
  language-terraform
  linter
  linter-jshint
  linter-perl
  linter-pycodestyle
  linter-terraform-syntax
  linter-ui-default
  minimap
  minimap-git-diff
  minimap-highlight-selected
  pretty-json
  project-manager
  Sublime-Style-Column-Selection
  todo-show
  tree-view-git-status
)

declare -a APP_STORE_APPS=(
  # Please note that it won't allow you to install (or even purchase) an app for the first time: it must already be in the Purchased tab of the App Store
  485812721 # Tweetdeck
  918858936 # Airmail (it will only work if it has been paid with your mac account, also you need to set up your app store account first)
)

# Check vim/plugins.vim for enabled plugins
# Check setup_osx function from lib/osx.sh for osx defaults
