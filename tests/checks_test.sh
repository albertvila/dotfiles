#!/usr/bin/env bash
# setup.sh -c claims a green run means the machine matches the repo, so the
# package and manual-step checks have to report what setup would have installed,
# and nothing else: a check that cries wolf gets switched off.
set -eo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

export HOME="$ROOT/home"
export DOTFILES_USER=test
mkdir -p "$HOME" "$ROOT/bin"

# shellcheck source=/dev/null
source "$REPO/lib/echos.sh"
# shellcheck source=/dev/null
source "$REPO/lib/os.sh"

# Stubs report a machine with nothing installed, then one with everything.
BIN="$ROOT/bin"
answers="$ROOT/answers"
mkdir -p "$answers"
printf '#!/bin/bash\ncat "%s/brew-formula" 2>/dev/null\n' "$answers" > "$BIN/brew"
printf '#!/bin/bash\ncat "%s/npm" 2>/dev/null\n' "$answers" > "$BIN/npm"
printf '#!/bin/bash\ncat "%s/pip" 2>/dev/null\n' "$answers" > "$BIN/pip"
chmod +x "$BIN/brew" "$BIN/npm" "$BIN/pip"
export PATH="$BIN:$PATH"

fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }
count() { printf '%s\n' "$1" | grep -c "$2" || true; }

# What the config declares, mirroring config.sh + config_albert.sh shapes.
declare -a BREW_APPS=(bat mobile-dev-inc/tap/maestro openssl@3)
declare -a BREW_CASK_APPS=(alfred bb)
declare -a NPM_PACKAGES=(eslint "@withgraphite/graphite-cli")
declare -a PIP_APPS=(pylint "isort<8.0.0")

# brew list answers per subcommand, like the real thing.
cat > "$answers/brew-formula" <<'EOF'
EOF
: > "$answers/brew-formula"
: > "$answers/npm"
: > "$answers/pip"

OUT=$(check_packages 2>&1) || true
check "empty machine reports every brew formula" "[ $(count "$OUT" 'brew formula not installed') -eq 3 ]"
check "empty machine reports every brew cask" "[ $(count "$OUT" 'brew cask not installed') -eq 2 ]"
check "empty machine reports every npm package" "[ $(count "$OUT" 'npm package not installed') -eq 2 ]"
check "empty machine reports every pip package" "[ $(count "$OUT" 'pip package not installed') -eq 2 ]"

# The tap prefix and the version range must not defeat the match.
printf 'bat\nmaestro\nopenssl@3\n' > "$answers/brew-formula"
printf 'alfred\nbb\n' > "$answers/brew-formula-cask"
cat > "$BIN/brew" <<EOF
#!/bin/bash
case "\$1 \$2" in
  "list --formula") cat "$answers/brew-formula" ;;
  "list --cask") cat "$answers/brew-formula-cask" ;;
esac
EOF
chmod +x "$BIN/brew"
printf '/opt/homebrew/lib\n├── eslint@9.1.0\n└── @withgraphite/graphite-cli@1.2.3\n' > "$answers/npm"
printf 'Package    Version\n---------- -------\npylint     3.1.0\nisort      5.13.2\n' > "$answers/pip"
DOTFILES_DRIFT=0
OUT=$(check_packages 2>&1) || true
check "installed tap formula with a slash is recognised" \
  "! printf '%s\n' \"\$OUT\" | grep -q 'brew formula not installed: mobile-dev-inc/tap/maestro'"
check "a versioned formula keeps its @version suffix" \
  "! printf '%s\n' \"\$OUT\" | grep -q 'brew formula not installed: openssl@3'"
check "installed scoped npm package is recognised" \
  "! printf '%s\n' \"\$OUT\" | grep -q 'withgraphite'"
check "pip package declared with a range is recognised" \
  "! printf '%s\n' \"\$OUT\" | grep -q 'pip package not installed: isort'"
check "full machine has no package drift" "[ $DOTFILES_DRIFT -eq 0 ]"

# A bare machine is one drift line per missing package manager, not per package.
DOTFILES_DRIFT=0
OUT=$(PATH=/usr/bin:/bin check_packages 2>&1) || true
check "bare machine is one drift line per package manager ($(count "$OUT" 'drift:'))" \
  "[ $(count "$OUT" 'drift:') -eq 3 ]"

# Manual steps: each one either has its trace or is reported.
printf '#!/bin/bash\ncat "%s/gpg" 2>/dev/null\n' "$answers" > "$BIN/gpg"
chmod +x "$BIN/gpg"
: > "$answers/gpg"
OUT=$(check_manual_steps 2>&1) || true
check "no gitconfig-user is drift" "printf '%s\n' \"\$OUT\" | grep -q 'missing ~/.gitconfig-user'"
check "no gpg secret key is drift" "printf '%s\n' \"\$OUT\" | grep -q 'no gpg secret key'"
check "no aws credentials is drift" "printf '%s\n' \"\$OUT\" | grep -q 'missing ~/.aws/credentials'"
check "all three reported on a bare HOME ($(count "$OUT" 'drift:'))" "[ $(count "$OUT" 'drift:') -eq 3 ]"

printf 'sec:u:4096:1:ABCD:1:::S:::+:::\n' > "$answers/gpg"
touch "$HOME/.gitconfig-user"
mkdir -p "$HOME/.aws"
touch "$HOME/.aws/credentials"
DOTFILES_DRIFT=0
check_manual_steps > /dev/null 2>&1 || true
check "complete manual steps are not drift" "[ $DOTFILES_DRIFT -eq 0 ]"

rm "$HOME/.aws/credentials"
DOTFILES_DRIFT=0
OUT=$(check_manual_steps 2>&1) || true
check "a step that regresses is the only drift line ($(count "$OUT" 'drift:'))" \
  "[ $(count "$OUT" 'drift:') -eq 1 ]"

exit "$fail"
