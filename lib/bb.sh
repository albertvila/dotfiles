#!/usr/bin/env bash

# bb plugin installs from bb-plugins.txt. Lives in lib/ so the decision below is
# covered by tests/bb_plugins_test.sh with a stubbed `bb`.

# The identity bb keys "already installed" on, with the ref/version removed: the
# repository (plus a monorepo tag prefix) for git, the package for npm. bb refuses
# `plugin install` for any git:/npm: source whose plugin id it already has — it
# answers `bb plugin update <id>` — so a manifest line that differs only in its
# range is still installed, and reinstalling it can never succeed.
function bb_source_identity() {
  local source=$1 bare tail
  case $source in
    *@semver:*) printf '%s' "${source%:*}" ;;
    npm:*)
      bare="${source#npm:}"
      [[ $bare == @* ]] && bare="${bare:1}" # a scope's @ is not a version separator
      [[ $bare == *@* ]] && printf '%s' "${source%@*}" || printf '%s' "$source"
      ;;
    git:*)
      # A ref is the last @-part, unless that @ is the URL's own user@host, which
      # drags the path along with it: `git:git@github.com:o/r.git` has no ref.
      tail="${source##*@}"
      if [[ $tail != */* || $source == *.git@* ]]; then
        printf '%s' "${source%@*}"
      else
        printf '%s' "$source"
      fi
      ;;
    *) printf '%s' "$source" ;;
  esac
}

# Installs what bb-plugins.txt lists: one source per line (git:/npm:/path:), path:
# entries relative to this repo. Idempotent, and never reinstalls a plugin bb
# already has — see bb_source_identity for why that can only fail.
function install_bb_plugins() {
  if ! command -v bb &>/dev/null; then
    warn "bb CLI not on PATH (install the bb cask, or link a get-bb/bb checkout's apps/cli/bin/bb), skipping bb plugins install"
    return
  fi
  local manifest="$DOTFILES_DIR/bb-plugins.txt"
  if [[ ! -f $manifest ]]; then
    warn "bb-plugins.txt not found, skipping bb plugins install"
    return
  fi
  bot "Installing bb plugins ..."
  local line source installed pairs recorded
  installed=$(bb plugin list --json 2>/dev/null | jq -r '.plugins[].source')
  pairs=$(while IFS= read -r source; do printf '%s\t%s\n' "$(bb_source_identity "$source")" "$source"; done <<< "$installed")
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z $line || $line == \#* ]] && continue
    source=$line
    # bb records resolved absolute paths, so a relative manifest entry with a
    # `..` segment would never match without canonicalizing it. A path: install
    # may also move, so only an exact match counts as installed.
    [[ $line == path:* ]] && source="path:$(realpath "$DOTFILES_DIR/${line#path:}" 2>/dev/null || echo "$DOTFILES_DIR/${line#path:}")"
    if grep -qxF "$source" <<< "$installed"; then
      ok "bb plugin already installed: $line"
      continue
    fi
    # bb records the ref it resolved, which moves ahead of the range here the
    # first time the plugin is updated past it. Update that line, don't reinstall:
    # bb would refuse, and removing the plugin first deletes its settings,
    # secrets, and schedules.
    recorded=$(awk -F'\t' -v identity="$(bb_source_identity "$source")" '$1 == identity { print $2; exit }' <<< "$pairs")
    if [[ -n $recorded ]]; then
      warn "bb plugin already installed under another ref: $line (bb records $recorded) — update that bb-plugins.txt line"
    else
      execute "bb plugin install --yes ${source#path:}" "bb plugin: $line"
    fi
  done < "$manifest"
  ok
}
