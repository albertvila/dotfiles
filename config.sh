#!/usr/bin/env bash

declare -a FILES_TO_SYMLINK=(
  'git/gitignore'
  'misc/isort.cfg'
  'tmux/tmux.conf'
  'tmux/tmuxinator.zsh'
  'vim'
  'vim/vimrc'
  'zsh/zshrc'
)

declare -a BINARIES=()

declare -a BREW_APPS=(
  coreutils
  # ctags # Used by vim plugin https://github.com/majutsushi/tagbar
  gnupg2 # To generate GPG keys for github (https://help.github.com/articles/generating-a-new-gpg-key/)
  gradle
  htop
  tmux
  vim
  wget
)

declare -a BREW_CASK_APPS=(
  atom
  google-chrome
  iterm2
  mysqlworkbench
  sshfs
)

declare -a GEM_APPS=(
  tmuxinator # https://github.com/tmuxinator/tmuxinator
)

declare -a PIP_APPS=(
  beautysh # Beautifier for sh files (used by atom)
  flake8 # Python code checker
  isort # Needed by atom if we want to sort python imports
)

declare -a ATOM_PACKAGES=(
  atom-beautify
  atom-material-syntax
  atom-material-ui
  atom-sync@
  busy-signal
  file-icons
  git-diff
  git-plus
  highlight-selected
  language-mediawiki
  linter
  linter-perl
  linter-pycodestyle
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

# Check vim/plugins.vim for enabled plugins
