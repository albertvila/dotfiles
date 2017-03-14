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

function ok() {
  if [ -n "$1" ]; then
    printf "$COL_GREEN [✔] $1 $COL_RESET\n"
  else
    printf "$DONE_ICON  done\n"
  fi
}

function warn() {
  echo -e "$COL_YELLOW[warning]$COL_RESET "$1
}

function error() {
  printf "$COL_RED [✖] $1 $2 $COL_RESET\n"
}

function result() {
  [ $1 -eq 0 ] && ok "$2" || error "$2"
  [ "$3" == "true" ] && [ $1 -ne 0 ] && exit
}

function ask() {
  printf "$COL_YELLOW [?] $1 $COL_RESET"
}

function ask_for_confirmation() {
  ask "$1 (y/n) "
  read -n 1
  printf "\n"
}

function answer_is_yes() {
  [[ "$REPLY" =~ ^[Yy]$ ]] && return 0 || return 1
}
