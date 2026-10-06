#!/usr/bin/env bash
# Checks that _install_brew_cask taps and trusts only what the active config
# declares: a default pass taps nothing a per-user config owns, while the user
# config taps and trusts maestro's repo before installing its package. opencode
# comes from homebrew/core, so the user pass installs it untapped.
set -eo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT

# Stubs: no prompts, and record every brew invocation.
bot() { :; }; ok() { :; }; warn() { :; }; error() { :; }
brew() { echo "brew $*" >> "$LOG"; }

# Source the given config files in order, then run the cask installer.
run_pass() {
  : > "$LOG"
  local f
  for f in "$@"; do
    # shellcheck source=/dev/null
    source "$REPO/$f"
  done
  # shellcheck source=/dev/null
  source "$REPO/lib/os.sh"
  _install_brew_cask
  _install_brew
}

fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }

run_pass config.sh
check "default pass taps no user-only repo" \
  "! grep -qxF 'brew tap mobile-dev-inc/tap' '$LOG'"
check "default pass trusts no user-only formula" \
  "! grep -qxF 'brew trust --formula mobile-dev-inc/tap/maestro' '$LOG'"

run_pass config.sh config_albert.sh
check "user pass taps mobile-dev-inc" "grep -qxF 'brew tap mobile-dev-inc/tap' '$LOG'"
check "user pass trusts maestro" "grep -qxF 'brew trust --formula mobile-dev-inc/tap/maestro' '$LOG'"
check "user pass installs opencode from core" "grep -qxF 'brew install opencode' '$LOG'"
check "maestro tap precedes its install" \
  "[ \"\$(grep -nxF 'brew tap mobile-dev-inc/tap' '$LOG' | cut -d: -f1)\" -lt \"\$(grep -nxF 'brew install mobile-dev-inc/tap/maestro' '$LOG' | cut -d: -f1)\" ]"

exit "$fail"
