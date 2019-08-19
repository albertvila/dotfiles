#!/usr/bin/env bash

function install_dotfiles() {
  _backup_existing_dotfiles

  _install_dotfiles
}

# It does a cleanup every 30 days
function cleanup() {
  if [ ! -e "$HOME/.dotfiles_cleanup" ]; then
    # First execution, doing nothin
    echo $(date) >> "$HOME/.dotfiles_cleanup"
    return
  else
    lastCleanup=$(sed = $HOME/.dotfiles_cleanup | sed -n '$p')
    cyan=$(cyan "$lastCleanup")
  fi

  todayMinus30Days=$(date --date "30 days ago" +"%Y%m%d")
  lastCleanupFormatted=$(date --date "${lastCleanup}" +%Y%m%d)
  if [[ "$todayMinus30Days" > "$lastCleanupFormatted" ]]; then
    bot "Last cleanup done at $cyan, doing another clean up now ..."

    if [ -e "$HOME/.gradle" ]; then
      # Cleaning up gradle cache (https://github.com/gradle/gradle/issues/2304)
      bot "Starting gradle cache cleaning, please be patient..."
      find ~/.gradle -type f -atime +30 -delete
      find ~/.gradle -type d -mindepth 1 -empty -delete
      ok "Gradle cache cleaned"
    fi

    if [ -x "$(command -v docker)" ]; then
      bot "Starting docker system prune, please be patient..."
      docker system prune -a -f --volumes
      ok "Docker imge prune"
    fi

    echo $(date) >> "$HOME/.dotfiles_cleanup"
  fi
}

function _symbolic_link() {
  sourceFile=$1
  targetFile=$2

  if [ ! -e "$targetFile" ]; then
    execute "ln -fs $sourceFile $targetFile" "$targetFile → $sourceFile"
  elif [ "$(readlink "$targetFile")" == "$sourceFile" ]; then
    ok "Link already exists for $targetFile"
  else
    ask_for_confirmation "'$targetFile' already exists, do you want to overwrite it?"
    if answer_is_yes; then
      rm -rf "$targetFile"
      execute "ln -fs $sourceFile $targetFile" "$targetFile → $sourceFile"
    else
      error "$targetFile → $sourceFile"
    fi
  fi
}

function _backup_existing_dotfiles() {
  bot "Backup any existing dotfiles in homedir to ~/.dotfiles_old directory if needed"

  # Create dotfiles_old for backup in homedir
  DOTFILES_BACKUP_DIR=~/.dotfiles_old
  mkdir -p $DOTFILES_BACKUP_DIR

  # Move any existing dotfiles in homedir to dotfiles_old directory
  for i in ${FILES_TO_SYMLINK[@]}; do
    file="$HOME/.${i##*/}"

    # Only move the file if it's not a symbolic link
    if [ -f $file ] && [ ! -L $file ]; then
      mv $file $DOTFILES_BACKUP_DIR
      if [ ! $? ]; then
        ok "$file moved to $DOTFILES_BACKUP_DIR"
      else
        error "Error moving $file to $DOTFILES_BACKUP_DIR"
      fi
    fi
  done

  ok
}

function _install_dotfiles() {
  local i=''
  local sourceFile=''
  local targetFile=''

  bot "Creating symbolic links for config files if needed"
  for i in ${FILES_TO_SYMLINK[@]}; do
    sourceFile="$DOTFILES_DIR/$i"
    targetFile="$HOME/.$(printf "%s" "$i" | sed "s/.*\/\(.*\)/\1/g")"

    _symbolic_link $sourceFile $targetFile
  done
  ok

  unset FILES_TO_SYMLINK

  # Copy binaries
  mkdir -p $HOME/bin

  bot "Creating symbolic links for binaries in ~/bin if needed"
  for i in ${BINARIES[@]}; do
    sourceFile="$DOTFILES_DIR/bin/$i"
    targetFile="$HOME/bin/$(printf "%s" "$i" | sed "s/.*\/\(.*\)/\1/g")"

    _symbolic_link $sourceFile $targetFile

    bot "Changing access permissions for binary script :: ~/bin/${i##*/}"
    chmod +rwx $HOME/bin/${i##*/}
  done

  ok

  unset BINARIES
}
