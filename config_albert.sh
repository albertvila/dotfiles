#!/usr/bin/env bash

declare -a BREW_APPS=(
  docker-credential-helper-ecr
  hadolint # Dockerfile linter and validation tool (https://github.com/hadolint/hadolint)
  mas # To install appstore apps that are not yet present on brew cask, see APP_STORE_APPS below (https://github.com/mas-cli/mas)
  # parquet-tools # TODO : This is deprecated
  php # Needed by Alfred Github workflow
  pyenv
)

# Those packages will only be installed on OSX
declare -a BREW_CASK_APPS=(
  arc
  calibre
  ledger-live
  logitune # https://www.logitech.com/en-us/video-collaboration/software/logi-tune-software.html
  session-manager-plugin # https://enter-lmwiki.launchmetrics.com/en/guides/aws-system-manager
  synology-drive
  warp
)

declare -a GEM_APPS=(
)

declare -a PIP_APPS=(
  autopep8 # Needed by python
  beautysh # Beautifier for sh files (used by atom)
  databricks
  databricks-cli
  dbx # Databricks dbx tool (https://docs.databricks.com/dev-tools/dbx.html)
  diagrams # Diagrams as code (https://diagrams.mingrammer.com/)
  flake8 # Python code checker
  isort # Needed by atom if we want to sort python imports
  pylint # Needed by python
)

declare -a YARN_APPS=(
)

declare -a NPM_PACKAGES=(
  alfred-goodreads-workflow
  @withgraphite/graphite-cli
)

declare -a VSCODE_PACKAGES=(
  amazonwebservices.aws-toolkit-vscode
  exiasr.hadolint
  gitHub.copilot
  gitHub.copilot-chat
  paiqo.databricks-vscode
)

declare -a APP_STORE_APPS=(
  # Please note that it won't allow you to install (or even purchase) an app for the first time: it must already be in the Purchased tab of the App Store, so download it manually first
  904280696 # Things3
  1176895641 # Spark email
)
