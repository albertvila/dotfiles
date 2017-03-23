#!/usr/bin/env bash

declare -a FILES_TO_SYMLINK=(
  'vim'
  'vim/vimrc'
  'git/gitignore'
  'misc/isort.cfg'
  'zsh/zshrc'
  'tmux/tmux.conf'
  'tmux/tmuxinator.zsh'
)

declare -a BINARIES=()

declare -a BREW_APPS=(
  coreutils
  vim
  htop
  wget
  gnupg2 # To generate GPG keys for github (https://help.github.com/articles/generating-a-new-gpg-key/)
  tmux
  # ctags # Used by vim plugin https://github.com/majutsushi/tagbar
)

declare -a BREW_CASK_APPS=(
  iterm2
  sshfs
  google-chrome
  atom
  mysqlworkbench
)

declare -a GEM_APPS=(
  tmuxinator # https://github.com/tmuxinator/tmuxinator
)

declare -a PIP_APPS=(
  isort # Needed by atom if we want to sort python imports
  beautysh # Beautifier for sh files (used by atom)
  flake8 # Python code checker
)

declare -a ATOM_PACKAGES=(
  atom-beautify
  atom-material-syntax
  atom-material-ui
  atom-sync@
  busy-signal
  file-icons
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
