#!/usr/bin/env bash
# scratch-sweep: sweep .scratch specs across all BB-registered projects and
# file one BB Task per pending spec, so a human approves before tokens are
# spent. Prints nothing when there is nothing to report (safe for script
# automations: empty stdout = silent skipped tick).
#
# Classification per .scratch/<feature>/ directory:
#   spec-only      has spec.md, no issues/        -> next step /to-tickets
#   tickets-ready  has issues/ (spec.md optional) -> next step /orchestrate-bb-threads
# "Pending" = at least one issue whose status is not done/wontfix/resolved;
# for spec-only, the spec's own Status line counts. Fully settled specs are
# skipped silently. Status lines are matched in both `**Status:** x` and
# plain `Status: x` forms.
#
# Dedup: each filed task carries a machine-readable marker line in its
# description:
#   scratch-sweep-key: <bb-project-name>:.scratch/<feature>
# A spec is skipped when a non-done/non-canceled task with the same marker
# already exists in its tracker project. Residual gap: tasks filed by hand
# or by /to-tickets before this sweeper existed carry no marker, so they are
# not deduped against.
#
# bb project -> tracker project mapping comes from
# `bb tasks project list --json` (linkedBbProjectId -> prefix). bb projects
# with no tracker project (e.g. dotfiles.private) are skipped and reported,
# not treated as an error.
#
# Usage: scratch-sweep.sh [--dry-run]
#   --dry-run  print exactly what would be created (bb project, tracker
#              prefix, task title, next step, marker) and create nothing.
set -euo pipefail

dry_run=0
case "${1:-}" in
  --dry-run) dry_run=1 ;;
  "") ;;
  *) echo "usage: scratch-sweep.sh [--dry-run]" >&2; exit 2 ;;
esac

# First Status line of a file, both `**Status:** x` and `Status: x` forms.
status_of() {
  grep -m1 -oiE '\*{0,2}Status:\*{0,2} *[A-Za-z*-]+' "$1" 2>/dev/null \
    | sed -E 's/.*Status:\** *//I; s/\*//g' | tr '[:upper:]' '[:lower:]' || true
}

is_settled() {
  case "$1" in done|wontfix|resolved) return 0 ;; *) return 1 ;; esac
}

projects_json=$(bb project list --include-personal --json)
tracker_json=$(bb tasks project list --json)

echo "$projects_json" | jq -r '.[] | .id as $id | .name as $name | .sources[]? | select(.isDefault) | [$id, $name, .path] | @tsv' \
| while IFS=$'\t' read -r bb_id bb_name root; do
    [ -d "$root/.scratch" ] || continue
    prefix=$(echo "$tracker_json" | jq -r --arg id "$bb_id" '.projects[]? | select(.linkedBbProjectId == $id) | .prefix' | head -1)

    project_report=""
    for dir in "$root/.scratch"/*/; do
      [ -d "$dir" ] || continue
      feature=$(basename "$dir")
      spec_rel=".scratch/$feature"

      n=0; rows=""
      if [ -d "$dir/issues" ]; then
        kind="tickets-ready"; next_step="/orchestrate-bb-threads"
        for f in "$dir/issues"/*.md; do
          [ -e "$f" ] || continue
          s=$(status_of "$f")
          if ! is_settled "$s"; then
            n=$((n + 1)); rows="${rows}    $(basename "$f")  [${s:-none}]\n"
          fi
        done
      elif [ -f "$dir/spec.md" ]; then
        kind="spec-only"; next_step="/to-tickets"
        s=$(status_of "$dir/spec.md")
        if ! is_settled "$s"; then
          n=1; rows="    spec.md  [${s:-none}]\n"
        fi
      else
        continue
      fi
      [ "$n" -gt 0 ] || continue  # fully settled: skip silently

      [ "$n" = "1" ] && s="issue" || s="issues"
      project_report="${project_report}  Feature $feature [$n pending $s, $kind -> $next_step]\n${rows}"

      if [ -z "$prefix" ]; then
        project_report="${project_report}    !! no tracker project for $bb_name -- skipped, file by hand\n"
        continue
      fi

      marker="scratch-sweep-key: $bb_name:$spec_rel"
      title="scratch-sweep: $feature -> $next_step"
      desc="Pending .scratch spec found by scratch-sweep.

- Spec: $root/$spec_rel
- BB project: $bb_name
- Pending issues: $n
- Next step: $next_step

$marker"

      # Fail closed: a broken lookup must skip filing, never create a duplicate.
      existing=""
      if list_json=$(bb tasks list --project "$prefix" --search "$marker" --json); then
        existing=$(echo "$list_json" | jq '[.tasks[]? | select(.status != "done" and .status != "canceled")] | length' 2>/dev/null) || existing=""
      fi
      if [ -z "$existing" ]; then
        project_report="${project_report}    !! task lookup failed for $prefix -- skipped, file by hand\n"
        continue
      fi
      if [ "$existing" -gt 0 ]; then
        project_report="${project_report}    = task exists ($prefix), skipped\n"
      elif [ "$dry_run" = "1" ]; then
        project_report="${project_report}    + would create [$prefix] \"$title\"\n      bb project: $bb_name | next step: $next_step\n      marker: $marker\n"
      else
        key=$(bb tasks create --project "$prefix" --title "$title" --description "$desc" --json | jq -r '.task.key // "?"')
        project_report="${project_report}    + created $key \"$title\"\n"
      fi
    done

    if [ -n "$project_report" ]; then
      echo "--------------------"
      echo "Project ${root/#$HOME/\~} (bb: $bb_name${prefix:+, tracker: $prefix})"
      printf '%b' "$project_report"
    fi
done
