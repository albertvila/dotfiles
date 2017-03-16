#!/usr/bin/env bash

# Colors
ESC_SEQ="\x1b["
COL_RESET=$ESC_SEQ"39;49;00m"
COL_RED=$ESC_SEQ"31;01m"
COL_GREEN=$ESC_SEQ"32;01m"
COL_YELLOW=$ESC_SEQ"33;01m"
COL_BLUE=$ESC_SEQ"34;01m"
COL_MAGENTA=$ESC_SEQ"35;01m"
COL_CYAN=$ESC_SEQ"36;01m"
DONE_ICON=$'\xf0\x9f\x8d\xa9' # donut

function blue() {
  printf "$COL_BLUE$1$COL_RESET"
}

function bot() {
  printf "$COL_BLUE[._.]$COL_RESET $1\n"
}

function ok() {
  if [ -n "$1" ]; then
    printf "$COL_GREEN [✔]$COL_RESET $1\n"
  else
    printf "$DONE_ICON\n"
  fi
}

function warn() {
  printf "$COL_YELLOW [✔]$COL_RESET $1\n"
}

function error() {
  printf "$COL_RED [✖]$COL_RESET $1 $2\n"
}

function result() {
  [ $1 -eq 0 ] && ok "$2" || error "$2"
  [ "$3" == "true" ] && [ $1 -ne 0 ] && exit
}

function ask() {
  printf "$COL_YELLOW [?]$COL_RESET $1"
}

function ask_for_confirmation() {
  ask "$1 (y/n) "
  read -n 1
  printf "\n"
}

function answer_is_yes() {
  [[ "$REPLY" =~ ^[Yy]$ ]] && return 0 || return 1
}
