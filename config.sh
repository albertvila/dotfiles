#!/usr/bin/env bash

declare -a FILES_TO_SYMLINK=(
  'git/gitignore'
  'misc/isort.cfg'
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
  ctags # Needed by https://marketplace.visualstudio.com/items?itemName=henriiik.vscode-perl
  fasd
  git
  gnupg # To generate GPG keys for github (https://help.github.com/articles/generating-a-new-gpg-key/)
  gradle
  gradle-completion
  htop
  jenv
  mas # To install appstore apps that are not yet present on brew cask, see APP_STORE_APPS below (https://github.com/mas-cli/mas)
  node
  openvpn
  perl-build
  plenv
  #terraform # Just commented to avoid updating it and causing issues on SRE production pipeline
  terraform_landscape
  vim
  wget
  yarn
  zookeeper
)

declare -a BREW_CASK_APPS=(
  alfred
  calibre
  docker
  dropbox
  firefox
  google-chrome
  intellij-idea-ce
  iterm2
  java
  movist
  plex-media-server
  postman
  skype
  slack
  spectacle
  spotify
  suunto-moveslink
  transmission
  visual-studio-code
)

declare -a GEM_APPS=(
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

declare -a NPM_PACKAGES=(
  alfred-goodreads-workflow
  aws-sam-local
  npm-check-updates # Needed to check if the other packages are up to date
)

declare -a VSCODE_PACKAGES=(
  akamud.vscode-theme-onedark
  alefragnani.project-manager
  brpaz.file-templates
  dbaeumer.vscode-eslint
  eamodio.gitlens
  GabrielBB.vscode-lombok
  GitHub.vscode-pull-request-github
  Gruntfuggly.todo-tree
  henriiik.vscode-perl
  JerryHong.autofilename
  Kaktus.perltidy-more
  mauve.terraform
  mohsen1.prettify-json
  ms-vscode.atom-keybindings
  PKief.material-icon-theme
  redhat.java
  RoscoP.ActiveFileInStatusBar
  sfodje.perlcritic
  softwaredotcom.swdc-vscode
  VisualStudioExptTeam.vscodeintellicode
  vncz.vscode-apielements
  vscjava.vscode-java-debug
  vscjava.vscode-java-test
  WakaTime.vscode-wakatime
)

declare -a APP_STORE_APPS=(
  # Please note that it won't allow you to install (or even purchase) an app for the first time: it must already be in the Purchased tab of the App Store
  918858936 # Airmail (it will only work if it has been paid with your mac account, also you need to set up your app store account first)
  904280696 # Things3
)

# Check vim/plugins.vim for enabled plugins
# Check setup_osx function from lib/osx.sh for osx defaults
