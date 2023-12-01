#!/usr/bin/env bash

declare -a FILES_TO_SYMLINK=(
  'git/gitignore'
  'git/gitconfig'
  'misc/isort.cfg'
  'vim'
  'vim/vimrc'
  'zsh/zpreztorc'
  'zsh/scripts'
  'zsh/zshrc'
  'zsh/p10k.zsh'
)

declare -a BINARIES=()

declare -a BREW_APPS=(
  ack
  awscli
  coreutils
  ctags # Needed by https://marketplace.visualstudio.com/items?itemName=henriiik.vscode-perl
  direnv
  gh
  git
  gnupg # To generate GPG keys for github (https://help.github.com/articles/generating-a-new-gpg-key/)
  gradle
  gradle-completion
  htop
  openjdk
  openjdk@11
  jenv
  jq
  node
  nvm
  openssl@3
  openvpn
  perl-build
  perltidy
  pinentry-mac
  plenv
  vim
  pygments
  yarn
)

declare -a BREW_CASK_APPS=(
  alfred
  dropbox
  firefox
  google-chrome
  intellij-idea-ce
  iterm2
  leapp
  openvpn-connect
  orbstack # Docker https://orbstack.dev/
  postman
  rectangle
  slack
  spotify
  visual-studio-code
  zoom
)

declare -a GEM_APPS=(
)

declare -a PIP_APPS=(
)

declare -a YARN_APPS=(
  mocha
)

declare -a NPM_PACKAGES=(
  eslint # Needed to check js code on vscode
  npm-check-updates # Needed to check if the other packages are up to date
  serverless@2.64.1
)

declare -a VSCODE_PACKAGES=(
  alefragnani.project-manager
  brpaz.file-templates
  byi8220.indented-block-highlighting
  dbaeumer.vscode-eslint
  eamodio.gitlens
  foxundermoon.shell-format
  GitHub.vscode-pull-request-github
  Gruntfuggly.todo-tree
  JerryHong.autofilename
  johnpapa.vscode-peacock
  Kaktus.perltidy-more
  hashicorp.terraform
  mohsen1.prettify-json
  ms-azuretools.vscode-docker
  ms-python.python
  nsfilho.tosnippet
  pflannery.vscode-versionlens
  PKief.material-icon-theme
  RoscoP.ActiveFileInStatusBar
  sfodje.perlcritic
  VisualStudioExptTeam.vscodeintellicode
  vncz.vscode-apielements
)

declare -a APP_STORE_APPS=(
  # Please note that it won't allow you to install (or even purchase) an app for the first time: it must already be in the Purchased tab of the App Store, so download it manually first
)

# Check vim/plugins.vim for enabled plugins
# Check setup_osx function from lib/osx.sh for osx defaults
