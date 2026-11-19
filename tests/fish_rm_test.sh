#!/usr/bin/env bash
# The rm function in fish/conf.d/30-shell.fish must remove a symlink instead of
# what its trailing slash resolves to: on macOS `rm -rf link/` empties the
# target and leaves the link.
set -eo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FISH_CONF="$REPO/home/.config/fish/conf.d/30-shell.fish"
WORK=$(mktemp -d)
trap 'rm -r -f "$WORK"' EXIT

fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }

# A shell with only these fish functions loaded, cwd in the fixture.
fishy() { (cd "$WORK" && fish --no-config -c "source $FISH_CONF; $1"); }
# Status of a command that is expected to fail, without tripping set -e.
status_of() { local s=0; "$@" >/dev/null 2>&1 || s=$?; echo "$s"; }

mkdir -p "$WORK/target/sub"
echo keep > "$WORK/target/keep"
echo hi > "$WORK/target/sub/file"
ln -s target "$WORK/link"

fishy 'rm -rf link/'
check "trailing slash removes the link only" \
  '[ ! -L "$WORK/link" ] && [ -f "$WORK/target/keep" ] && [ -f "$WORK/target/sub/file" ]'

ln -s target "$WORK/link"
fishy 'rm -rf -- link/'
check "guard still applies after --" \
  '[ ! -L "$WORK/link" ] && [ -f "$WORK/target/keep" ]'

ln -s target "$WORK/link"
fishy 'rm -rf link'
check "no slash removes the link only" \
  '[ ! -L "$WORK/link" ] && [ -f "$WORK/target/keep" ]'

mkdir -p "$WORK/real/sub" && echo x > "$WORK/real/sub/x"
fishy 'rm -rf real/'
check "a real directory with a trailing slash is still removed" '[ ! -e "$WORK/real" ]'

echo plain > "$WORK/plainfile"
file_status=$(status_of fishy 'rm plainfile/')
check "a file with a trailing slash still fails and survives" \
  '[ "$file_status" -ne 0 ] && [ -f "$WORK/plainfile" ]'

missing_status=$(status_of fishy 'rm -rf missing-dir/')
check "-f on a missing path exits 0" '[ "$missing_status" -eq 0 ]'

nofile_status=$(status_of fishy 'rm missing-file-xyz')
check "a missing file without -f exits nonzero" '[ "$nofile_status" -ne 0 ]'

# Operands the guard must never rewrite, checked against a stub rm: a strips-to-
# empty operand like // must reach rm as typed, not become an empty argument.
stub="$WORK/stub"
mkdir -p "$stub"
printf '#!/bin/sh\nfor a in "$@"; do printf "%%s\\n" "$a"; done > %s/rm-args\n' "$WORK" > "$stub/rm"
chmod +x "$stub/rm"
fishy "set -x PATH $stub \$PATH; rm -rf // / ."
check "root-ish operands reach rm unchanged" \
  '[ "$(tr "\n" " " < "$WORK/rm-args")" = "-rf // / . " ]'

exit "$fail"
