#!/usr/bin/env bash

declare -a BREW_APPS=(
  docker-credential-helper-ecr
  hadolint # Dockerfile linter and validation tool (https://github.com/hadolint/hadolint)
  mobile-dev-inc/tap/maestro # Mobile UI testing framework (https://github.com/mobile-dev-inc/maestro)
  mas # To install appstore apps that are not yet present on brew cask, see APP_STORE_APPS below (https://github.com/mas-cli/mas)
  opencode # AI coding agent (https://opencode.ai/)
  pi-coding-agent # AI agent toolkit (https://pi.dev/)
  # parquet-tools # TODO : This is deprecated
  php # Needed by Alfred Github workflow
  pyenv
  skills
  slack-mcp-server
  supabase # Supabase CLI (https://supabase.com/docs/reference/cli/about)
  tailscale # https://tailscale.com/ used to control opencode from my iphone
)

# Those packages will only be installed on OSX
declare -a BREW_CASK_APPS=(
  android-studio
  bb # IDE for orchestrating coding agents (https://getbb.app/)
  calibre
  claude-code
  ghostty
  ledger-live
  logitune # https://www.logitech.com/en-us/video-collaboration/software/logi-tune-software.html
  session-manager-plugin # https://enter-lmwiki.launchmetrics.com/en/guides/aws-system-manager
  steipete/tap/codexbar # https://codexbar.app/
  synology-drive
  tailscale-app # To control this mac through my iphone
  thebrowsercompany-dia # Dia AI browser (https://www.diabrowser.com/)
  twingate # VPN client
)

# Taps for this config's brew packages outside homebrew/core, plus the formulas
# that need `brew trust` before install.
declare -a BREW_TAPS=(
  anomalyco/tap # opencode
  aws/tap # docker-credential-helper-ecr, session-manager-plugin
  mobile-dev-inc/tap # maestro
)

declare -a BREW_TRUSTED_FORMULAS=(
  anomalyco/tap/opencode
  mobile-dev-inc/tap/maestro
)

declare -a PIP_APPS=(
  autopep8 # Needed by python
  databricks-cli
  diagrams # Diagrams as code (https://diagrams.mingrammer.com/)
  flake8 # Python code checker
  "isort<8.0.0" # lm-pyconv requires isort<8
  pylint # Needed by python
)

declare -a NPM_PACKAGES=(
  alfred-goodreads-workflow
  @withgraphite/graphite-cli
  mcp-remote
)

declare -a APP_STORE_APPS=(
  # Please note that it won't allow you to install (or even purchase) an app for the first time: it must already be in the Purchased tab of the App Store, so download it manually first
  904280696 # Things3
  1176895641 # Spark email
)
