#!/usr/bin/env bash

declare -a BREW_APPS=(
  docker-credential-helper-ecr
  hadolint # Dockerfile linter and validation tool (https://github.com/hadolint/hadolint)
  mas # To install appstore apps that are not yet present on brew cask, see APP_STORE_APPS below (https://github.com/mas-cli/mas)
  parquet-tools
  php # Needed by Alfred Github workflow
  pyenv
)

# Those packages will only be installed on Linux
declare -a APT_GET_APPS=(
)

# Those packages will only be installed on OSX
declare -a BREW_CASK_APPS=(
  adoptopenjdk8
  calibre
  leapp # New AWS authentication method
  google-chrome # Moved here because it's already installed on company laptops
  session-manager-plugin # https://enter-lmwiki.launchmetrics.com/en/guides/aws-system-manager
  slack # Moved here because it's already installed on company laptops
  1password # password storage
  mongodb-compass
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
  pyenv
)

declare -a YARN_APPS=(
)

declare -a NPM_PACKAGES=(
    serverless@2.72.2
    yarn
)

declare -a VSCODE_PACKAGES=(
  exiasr.hadolint
  apollographql.vscode-apollo
  cssho.vscode-svgviewer
  paiqo.databricks-vscode
  parquet-viewer
  Durzn.brackethighlighter
  esbenp.prettier-vscode
  iulian-radu-at.find-unused-exports
  jock.svg
  ms-vsliveshare.vsliveshare
  SonarSource.sonarlint-vscode
  redhat.vscode-yaml
  RandomFractalsInc.vscode-data-table
)
