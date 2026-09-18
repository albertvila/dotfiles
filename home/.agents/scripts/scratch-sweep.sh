#!/usr/bin/env bash
# scratch-sweep: list .scratch tickets across all BB-registered projects that
# are not done/wontfix/resolved, grouped by project and feature.
# Prints nothing when everything is settled (safe for script automations:
# empty stdout = silent skipped tick).
set -euo pipefail

bb project list --include-personal --json | jq -r '.[].sources[]? | select(.isDefault) | .path' | while read -r root; do
  [ -d "$root/.scratch" ] || continue
  rows=$(find "$root/.scratch" -path '*/issues/*.md' | sort | while read -r f; do
    status=$(grep -m1 -oiE '\*\*Status:\*\* *[*A-Za-z-]+' "$f" | sed -E 's/.*\*\*Status:\*\* *//I; s/\*//g' || true)
    case "$status" in
      done|wontfix|resolved) ;;
      *)
        feature=$(basename "$(dirname "$(dirname "$f")")")
        printf '%s\t%s\t%s\n' "$feature" "$(basename "$f")" "${status:-none}"
        ;;
    esac
  done)
  [ -n "$rows" ] || continue
  echo "--------------------"
  echo "Project ${root/#$HOME/\~}"
  echo "$rows" | cut -f1 | uniq -c | while read -r n feature; do
    [ "$n" = "1" ] && s="issue" || s="issues"
    echo "  Feature $feature [$n $s]"
    echo "$rows" | awk -F'\t' -v feat="$feature" '$1==feat {printf "    %s  [%s]\n", $2, $3}'
  done
done
