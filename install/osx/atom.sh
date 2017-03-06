#!/usr/bin/env bash
echo "Checking atom packages ..."

if ! test $(which atom)
then
  print_error "atom not installed"
  exit 1
fi

# Install atom packages
packages=(
  Sublime-Style-Column-Selection
  atom-beautify
  atom-material-syntax
  atom-material-ui
  atom-sync@
  file-icons
  git-plus
  highlight-selected
  linter
  linter-perl
  linter-pycodestyle
  minimap
  minimap-git-diff
  minimap-highlight-selected
  pretty-json
  project-manager
  todo-show
  tree-view-git-status
)

for pkg in ${packages[@]}; do
  if [[ ! -d "$HOME/.atom/packages/$package" ]]
  then
    echo "[atom] Package '$pkg' is not installed"
    apm install $package
  else
    print_success "[atom] Package '$pkg' is already installed"
  fi
done

print_done
