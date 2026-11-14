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

# Prefix collision + tap prefix in outdated check: an outdated herdr-app cask or
# openjdk@17 formula must not trigger `brew upgrade herdr` / `brew upgrade openjdk`,
# while an outdated tapped formula (datadog-labs/pack/pup) must upgrade.
brew() {
  echo "brew $*" >> "$LOG"
  case "$*" in
    "list --formula -1") printf 'herdr\nopenjdk\npup\n' ;;
    "outdated --formula --quiet"|"outdated --quiet")
      printf 'herdr-gpui\nopenjdk@17\ndatadog-labs/pack/pup\n' ;;
  esac
}
: > "$LOG"
BREW_APPS=(herdr openjdk datadog-labs/pack/pup)
_install_brew
check "outdated check queries formulae only" "grep -qxF 'brew outdated --formula --quiet' '$LOG'"
check "prefix-colliding herdr-gpui does not upgrade herdr" "! grep -qxF 'brew upgrade herdr' '$LOG'"
check "prefix-colliding openjdk@17 does not upgrade openjdk" "! grep -qxF 'brew upgrade openjdk' '$LOG'"
check "outdated tapped formula upgrades" "grep -qxF 'brew upgrade datadog-labs/pack/pup' '$LOG'"

# A tap entry may carry its clone URL as a second word, for upstream repos that
# do not follow the homebrew-<name> convention (e.g. after doitintl renamed
# homebrew-dci-cli to dci-cli, `brew tap doitintl/dci-cli` alone re-adds the
# redirecting remote and `brew update` then refuses the redirect).
brew() { printf '%s|' "$@" >> "$LOG"; echo >> "$LOG"; }
: > "$LOG"
BREW_CASK_APPS=()
BREW_TRUSTED_FORMULAS=()
BREW_TAPS=("doitintl/dci-cli https://github.com/doitintl/dci-cli")
_install_brew_cask
check "tap URL entry passes name and URL as separate args" \
  "grep -qxF 'tap|doitintl/dci-cli|https://github.com/doitintl/dci-cli|' '$LOG'"

exit "$fail"
