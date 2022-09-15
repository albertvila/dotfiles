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
  docker
  fasd
  gh
  git
  gnupg # To generate GPG keys for github (https://help.github.com/articles/generating-a-new-gpg-key/)
  gradle
  gradle-completion
  htop
  java11
  jenv
  jq
  node
  nvm
  openssl
  openvpn
  perl-build
  perltidy
  pinentry-mac
  plenv
  vim
  yarn
)

declare -a APT_GET_APPS=(
  build-essential # Needed by linuxBrew
  curl # Needed by linuxBrew
  file # Needed by linuxBrew
  git # Needed by linuxBrew
  default-jdk
)

declare -a BREW_CASK_APPS=(
  alfred
  docker
  dropbox
  firefox
  intellij-idea-ce
  iterm2
  postman
  rectangle
  spotify
  visual-studio-code
)

declare -a GEM_APPS=(
)

declare -a PIP_APPS=(
  Pygments
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
  akamud.vscode-theme-onedark
  alefragnani.project-manager
  atlassian.atlascode
  brpaz.file-templates
  byi8220.indented-block-highlighting
  dbaeumer.vscode-eslint
  eamodio.gitlens
  foxundermoon.shell-format
  GabrielBB.vscode-lombok
  GitHub.vscode-pull-request-github
  Gruntfuggly.todo-tree
  JerryHong.autofilename
  johnpapa.vscode-peacock
  Kaktus.perltidy-more
  mathiasfrohlich.Kotlin
  hashicorp.terraform
  mohsen1.prettify-json
  ms-azuretools.vscode-docker
  ms-python.python
  ms-vscode.atom-keybindings
  ms-vsliveshare.vsliveshare-pack
  nsfilho.tosnippet
  pflannery.vscode-versionlens
  PKief.material-icon-theme
  redhat.java
  RoscoP.ActiveFileInStatusBar
  secanis.jenkinsfile-support
  sfodje.perlcritic
  VisualStudioExptTeam.vscodeintellicode
  vncz.vscode-apielements
  vscjava.vscode-java-debug
  vscjava.vscode-java-test
)

declare -a APP_STORE_APPS=(
  # Please note that it won't allow you to install (or even purchase) an app for the first time: it must already be in the Purchased tab of the App Store, so download it manually first
)

# Check vim/plugins.vim for enabled plugins
# Check setup_osx function from lib/osx.sh for osx defaults
