#!/usr/bin/env bash
# Checks that _install_brew_cask taps and trusts only what the active config
# declares: a default pass taps nothing a per-user config owns, while the user
# config taps and trusts both repos before installing their packages.
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
  "! grep -qE 'brew tap (mobile-dev-inc|anomalyco)/tap' '$LOG'"
check "default pass trusts no user-only formula" \
  "! grep -qE 'brew trust --formula (mobile-dev-inc|anomalyco)/' '$LOG'"

run_pass config.sh config_albert.sh
check "user pass taps mobile-dev-inc" "grep -qxF 'brew tap mobile-dev-inc/tap' '$LOG'"
check "user pass taps anomalyco" "grep -qxF 'brew tap anomalyco/tap' '$LOG'"
check "user pass trusts maestro" "grep -qxF 'brew trust --formula mobile-dev-inc/tap/maestro' '$LOG'"
check "user pass trusts opencode" "grep -qxF 'brew trust --formula anomalyco/tap/opencode' '$LOG'"
check "maestro tap precedes its install" \
  "[ \"\$(grep -nxF 'brew tap mobile-dev-inc/tap' '$LOG' | cut -d: -f1)\" -lt \"\$(grep -nxF 'brew install mobile-dev-inc/tap/maestro' '$LOG' | cut -d: -f1)\" ]"
check "opencode tap precedes its install" \
  "[ \"\$(grep -nxF 'brew tap anomalyco/tap' '$LOG' | cut -d: -f1)\" -lt \"\$(grep -nxF 'brew install opencode' '$LOG' | cut -d: -f1)\" ]"

exit "$fail"
