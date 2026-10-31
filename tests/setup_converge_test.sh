#!/usr/bin/env bash
# The README used to say the first setup run may error and you should run it
# twice. This runs the real setup.sh twice against a fake $HOME with the machine
# touched only through stubs: the first run must provision, the second must
# change nothing, and neither may prompt or error.
#
# `defaults`, `chflags`, `killall` and `chsh` are stubbed because the real ones
# would rewrite this Mac's settings and switch the developer's login shell.
set -eo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

export HOME="$ROOT/home"
export DOTFILES_USER=test
export DOTFILES_DIR="$REPO"
BIN="$ROOT/bin"
LOG="$ROOT/calls.log"
STATE="$ROOT/bb-plugins.state"
mkdir -p "$HOME" "$BIN"
: > "$LOG"
: > "$STATE"

# A stub that records what it was asked to do and changes nothing.
stub() {
  printf '#!/bin/bash\necho "%s $*" >> "%s"\n' "$1" "$LOG" > "$BIN/$1"
  chmod +x "$BIN/$1"
}
for cmd in brew pip pip3 npm vim git chsh defaults chflags killall mas gdate \
           fish pi herdr claude opencode; do
  stub "$cmd"
done

# bb remembers what it installed, so the second run is a converged machine.
cat > "$BIN/bb" <<EOF
#!/bin/bash
echo "bb \$*" >> "$LOG"
case "\$1 \$2" in
  "plugin list")
    printf '{"plugins":['
    sep=""
    while IFS= read -r source; do
      [ -z "\$source" ] && continue
      printf '%s{"id":"x","source":"%s"}' "\$sep" "\$source"
      sep=","
    done < "$STATE"
    printf ']}\n'
    ;;
  "plugin install")
    # bb records a bare path install as path:<abs>, a git:/npm: source verbatim.
    case "\${4:-}" in
      git:*|npm:*|path:*) echo "\${4:-}" >> "$STATE" ;;
      *) echo "path:\${4:-}" >> "$STATE" ;;
    esac
    ;;
esac
EOF
chmod +x "$BIN/bb"

# setup pipes the twg installer into bash; the stub installer leaves a stub twg.
cat > "$BIN/curl" <<EOF
#!/bin/bash
echo "curl \$*" >> "$LOG"
cat <<SCRIPT
mkdir -p "\\\$HOME/.local/bin"
printf '#!/bin/bash\necho "twg \\\$*" >> "$LOG"\n' > "\\\$HOME/.local/bin/twg"
chmod +x "\\\$HOME/.local/bin/twg"
SCRIPT
EOF
chmod +x "$BIN/curl"

# Stubs first, so no real package manager, editor or shell helper is reachable.
export PATH="$BIN:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
# A converged machine has fish as its login shell already, so chsh is never needed.
export SHELL="$BIN/fish"

# Everything setup created, with type, link target and file mtime. The two
# journals grow on every run by design, so they are the only things excluded.
snapshot() {
  ( cd "$HOME" && find . -mindepth 1 | LC_ALL=C sort | while IFS= read -r path; do
      case $path in
        ./.dotfiles|./.dotfiles_cleanup) continue ;;
      esac
      if [ -L "$path" ]; then
        printf 'link %s -> %s\n' "$path" "$(readlink "$path")"
      elif [ -d "$path" ]; then
        printf 'dir  %s\n' "$path"
      else
        printf 'file %s %s\n' "$path" "$(stat -f %m "$path")"
      fi
    done )
}

fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }

# Run from a directory that is not the repo: setup.sh claims it can be run from
# anywhere, and this test must not silently exercise the caller's checkout.
cd "$ROOT"

# --- run 1: a bare machine -------------------------------------------------
RUN1=$(bash "$REPO/setup.sh" -f 2>&1) && RUN1_STATUS=0 || RUN1_STATUS=$?
AFTER1=$(snapshot)
check "first run exits 0" "[ $RUN1_STATUS -eq 0 ]"
check "first run reports no errors ($(printf '%s\n' "$RUN1" | grep -c '✖' || true))" \
  "! printf '%s\n' \"\$RUN1\" | grep -q '✖'"
check "first run links the home mirror" "printf '%s\n' \"\$RUN1\" | grep -q 'Link already exists\|→ '"
check "first run installed fish via brew" "grep -q 'brew upgrade fish' '$LOG'"
check "first run never called chsh" "! grep -q 'chsh ' '$LOG'"
check "first run installed the declared brew formulae" "grep -q 'brew install bat' '$LOG'"
check "first run installed the twg CLI through the installer pipe" "grep -q 'curl ' '$LOG' && [ -x '$HOME/.local/bin/twg' ]"
check "first run installed bb plugins" "grep -q 'bb plugin install --yes' '$LOG'"

: > "$LOG"
sleep 1

# --- run 2: the same machine, twice ----------------------------------------
RUN2=$(bash "$REPO/setup.sh" -f 2>&1) && RUN2_STATUS=0 || RUN2_STATUS=$?
AFTER2=$(snapshot)
check "second run exits 0" "[ $RUN2_STATUS -eq 0 ]"
check "second run reports no errors ($(printf '%s\n' "$RUN2" | grep -c '✖' || true))" \
  "! printf '%s\n' \"\$RUN2\" | grep -q '✖'"
check "second run prompts for nothing" "! printf '%s\n' \"\$RUN2\" | grep -q '(y/n)'"
check "second run re-links nothing ($(printf '%s\n' "$RUN2" | grep -c '→ ' || true) install lines)" \
  "! printf '%s\n' \"\$RUN2\" | grep -q '→ '"
check "second run found the links already in place" "printf '%s\n' \"\$RUN2\" | grep -q 'Link already exists'"
check "second run reinstalls no bb plugin" "! grep -q 'bb plugin install' '$LOG'"
check "second run still calls chsh never" "! grep -q 'chsh ' '$LOG'"
check "second run backs nothing up" "[ -z \"\$(ls -A '$HOME/.dotfiles_old' 2>/dev/null)\" ]"

# The claim the README makes, and the one this test exists for.
if [ "$AFTER1" = "$AFTER2" ]; then
  echo "ok   - a second run leaves \$HOME byte-identical ($(printf '%s\n' "$AFTER2" | wc -l | tr -d ' ') entries)"
else
  echo "FAIL - a second run changed \$HOME:"
  diff <(printf '%s\n' "$AFTER1") <(printf '%s\n' "$AFTER2") | sed 's/^/       /'
  fail=1
fi

exit "$fail"
