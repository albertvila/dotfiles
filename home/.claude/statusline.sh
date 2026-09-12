#!/bin/bash
# Custom status line for Claude Code CLI
# Place this file at ~/.claude/statusline.sh and make it executable: chmod +x ~/.claude/statusline.sh
# Configure it in settings.json with: "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" }
#
# Claude Code pipes a JSON blob to stdin with session info. Available fields:
#   .model.display_name              - Current model name (e.g. "Opus 4.6")
#   .workspace.current_dir           - Working directory path
#   .cost.total_cost_usd             - Accumulated session cost in USD
#   .cost.total_duration_ms          - Total wall-clock session duration in milliseconds
#   .cost.total_api_duration_ms      - Time spent waiting for API responses only
#   .context_window.used_percentage  - How full the context window is (0-100)
#   .session_id                      - Unique session identifier
#
# Requires: jq (brew install jq)

# Read the JSON blob from stdin
input=$(cat)

# Parse fields from the JSON input
MODEL=$(echo "$input" | jq -r '.model.display_name')
DIR=$(echo "$input" | jq -r '.workspace.current_dir')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')

# ANSI color codes
CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; RESET='\033[0m'

# Context window usage bar: green < 70%, yellow 70-89%, red >= 90%
if [ "$PCT" -ge 90 ]; then BAR_COLOR="$RED"
elif [ "$PCT" -ge 70 ]; then BAR_COLOR="$YELLOW"
else BAR_COLOR="$GREEN"; fi

# Build a 10-char progress bar (e.g. "████░░░░░░" for 40%)
FILLED=$((PCT / 10)); EMPTY=$((10 - FILLED))
printf -v FILL "%${FILLED}s"; printf -v PAD "%${EMPTY}s"
BAR="${FILL// /█}${PAD// /░}"

# Convert duration from ms to minutes and seconds
MINS=$((DURATION_MS / 60000)); SECS=$(((DURATION_MS % 60000) / 1000))

# Show git branch if inside a repo
BRANCH=""
git rev-parse --git-dir > /dev/null 2>&1 && BRANCH=" | 🌿 $(git branch --show-current 2>/dev/null)"

# Line 1: model, directory, and git branch
echo -e "${CYAN}[$MODEL]${RESET} 📁 ${DIR##*/}$BRANCH"

# Line 2: context bar, cost, and session duration
# NOTE: We use /usr/bin/printf (external) with LC_NUMERIC=C to force dot as decimal separator.
# This avoids locale issues (e.g. Spanish/Catalan locales use comma) when formatting the cost.
COST_FMT=$(LC_NUMERIC=C /usr/bin/printf '$%.2f' "$COST")
echo -e "${BAR_COLOR}${BAR}${RESET} ${PCT}% | ${YELLOW}${COST_FMT}${RESET} | ⏱️ ${MINS}m ${SECS}s"
