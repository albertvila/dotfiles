#!/usr/bin/env bash
# bb refuses `plugin install` for a git:/npm: source whose plugin id it already
# has installed (it answers `bb plugin update`). So a manifest line whose range
# drifted from what bb recorded must be reported, never reinstalled, and two
# plugins from one monorepo must not collapse into each other.
set -eo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

export DOTFILES_DIR="$ROOT/repo"
export DOTFILES_USER=test
mkdir -p "$DOTFILES_DIR" "$ROOT/bb-plugins/plugins/activity-overview"

# What bb records for the path: entry below, canonicalized the way setup does.
LOCAL_PLUGIN=$(realpath "$ROOT/bb-plugins/plugins/activity-overview")

BB_LIST="$ROOT/bb-list.json"
BB_INSTALLS="$ROOT/installs.log"
: > "$BB_INSTALLS"
cat > "$BB_LIST" <<EOF
{"plugins": [
  {"id": "bb-sidebar", "source": "git:https://github.com/yusuf8834/bb-sidebar.git@semver:>=0.3.0"},
  {"id": "thread-badges", "source": "git:https://github.com/matthewdias/bb-plugins.git@semver:thread-badges/:^0.1.0"},
  {"id": "scoped-pkg", "source": "npm:@scope/pkg@2.0.0"},
  {"id": "activity-overview", "source": "path:$LOCAL_PLUGIN"}
]}
EOF

# `plugin list` answers the fixture; `plugin install` records what it was asked to
# install (the test asserts which sources never reach it).
bb() {
  case "$1 $2" in
    "plugin list") cat "$BB_LIST" ;;
    "plugin install") printf '%s\n' "${*:3}" >> "$BB_INSTALLS" ;;
  esac
}

cat > "$DOTFILES_DIR/bb-plugins.txt" <<'EOF'
# comments and blank lines are ignored

git:https://github.com/yusuf8834/bb-sidebar.git@semver:^0.2.0
git:https://github.com/matthewdias/bb-plugins.git@semver:thread-badges/:^0.1.0
git:https://github.com/matthewdias/bb-plugins.git@semver:follow-up/:^0.3.0
git:https://github.com/some/new-plugin.git@v1.0.0
npm:@scope/pkg@1.0.0
npm:@scope/other@1.0.0
path:../bb-plugins/plugins/activity-overview
EOF

# shellcheck source=/dev/null
source "$REPO/lib/echos.sh"
# shellcheck source=/dev/null
source "$REPO/lib/utils.sh"
# shellcheck source=/dev/null
source "$REPO/lib/bb.sh"

fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }

same() { [[ "$(bb_source_identity "$1")" == "$(bb_source_identity "$2")" ]]; }

check "a drifted semver range is the same plugin" 'same git:https://x/y.git@semver:^0.2.0 git:https://x/y.git@semver:>=0.3.0'
check "one monorepo's tag prefixes stay distinct" '! same git:https://x/y.git@semver:follow-up/:^0.3.0 git:https://x/y.git@semver:thread-badges/:^0.1.0'
check "a drifted npm version is the same package" 'same npm:@scope/pkg@1.0.0 npm:@scope/pkg@2.0.0'
check "an unversioned npm source keeps its scope" '[ "$(bb_source_identity npm:@scope/pkg)" = "npm:@scope/pkg" ]'
check "a ref-less git url is untouched" '[ "$(bb_source_identity git:https://x/y.git)" = "git:https://x/y.git" ]'
check "an ssh git url without a ref is untouched" '[ "$(bb_source_identity git:git@github.com:o/r.git)" = "git:git@github.com:o/r.git" ]'
check "an ssh git url with a ref keeps its host" '[ "$(bb_source_identity git:git@github.com:o/r.git@v1.0.0)" = "git:git@github.com:o/r.git" ]'

out=$(install_bb_plugins 2>&1)
printf '%s\n' "$out" > "$ROOT/out.log"

check "drifted git range is not reinstalled" '! grep -qF "bb-sidebar.git@semver:^0.2.0" "$BB_INSTALLS"'
check "drift warning names what bb records" 'grep -qF "bb records git:https://github.com/yusuf8834/bb-sidebar.git@semver:>=0.3.0" "$ROOT/out.log"'
check "drifted npm version is not reinstalled" '! grep -qF "npm:@scope/pkg@1.0.0" "$BB_INSTALLS"'
check "exact-match git source is not reinstalled" '! grep -qF "thread-badges/:^0.1.0" "$BB_INSTALLS"'
check "exact-match path source is not reinstalled" '! grep -qF "activity-overview" "$BB_INSTALLS"'
check "exact-match path source reports installed" 'grep -qF "already installed: path:../bb-plugins/plugins/activity-overview" "$ROOT/out.log"'
check "the monorepo's second plugin is still installed" 'grep -qF "follow-up/:^0.3.0" "$BB_INSTALLS"'
check "a plugin bb does not have is installed" 'grep -qF "new-plugin.git@v1.0.0" "$BB_INSTALLS"'
check "an uninstalled npm package is installed" 'grep -qF "npm:@scope/other@1.0.0" "$BB_INSTALLS"'
check "nothing was reported as an error" '! grep -qF "✖" "$ROOT/out.log"'

exit "$fail"
