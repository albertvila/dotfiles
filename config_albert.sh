#!/usr/bin/env bash

declare -a BREW_APPS=(
  docker-credential-helper-ecr
  gemini-cli
  hadolint # Dockerfile linter and validation tool (https://github.com/hadolint/hadolint)
  mobile-dev-inc/tap/maestro # Mobile UI testing framework (https://github.com/mobile-dev-inc/maestro)
  mas # To install appstore apps that are not yet present on brew cask, see APP_STORE_APPS below (https://github.com/mas-cli/mas)
  ollama # https://ollama.com/
  opencode # AI coding agent (https://opencode.ai/)
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
  arc
  calibre
  chatgpt
  claude-code
  copilot-cli
  ghostty
  ledger-live
  logitune # https://www.logitech.com/en-us/video-collaboration/software/logi-tune-software.html
  session-manager-plugin # https://enter-lmwiki.launchmetrics.com/en/guides/aws-system-manager
  steipete/tap/codexbar # https://codexbar.app/
  synology-drive
  tailscale-app # To control this mac through my iphone
  twingate # VPN client
  warp
  zen
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
  mcp-remote
)

declare -a VSCODE_PACKAGES=(
  amazonwebservices.aws-toolkit-vscode
  anthropic.claude-code
  exiasr.hadolint
  github.copilot-chat
  ms-python.autopep8
  ms-python.flake8
  ms-python.black-formatter
  ms-python.vscode-pylance
  paiqo.databricks-vscode
  prisma.prisma
)

declare -a APP_STORE_APPS=(
  # Please note that it won't allow you to install (or even purchase) an app for the first time: it must already be in the Purchased tab of the App Store, so download it manually first
  904280696 # Things3
  1176895641 # Spark email
)
