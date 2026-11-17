#!/usr/bin/env bash
# aws-env exists for one failure: a hook that reads AWS_ACCESS_KEY_ID, on a machine whose only
# credentials are an SSO session. So each check below pins one half of that bargain — the
# variable reaches the command, the profile is the one the repo declares, and a stale session
# stops before the command runs rather than inside it, where the error would be the hook's.
set -eo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_SH="$REPO/home/.agents/scripts/aws-env"

fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

BIN="$WORK/bin"
REPO_DIR="$WORK/repo"
mkdir -p "$BIN" "$REPO_DIR/sub"
printf 'export AWS_PROFILE="atlas-staging"\n' > "$REPO_DIR/.envrc"

# A fake aws that records the profile it was asked for, and answers as told.
cat > "$BIN/aws" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_AWS_ASKED"
if [ -f "$FAKE_AWS_STALE" ]; then
  echo "The SSO session associated with this profile has expired or is otherwise invalid." >&2
  exit 255
fi
printf 'export AWS_ACCESS_KEY_ID=ASIATESTKEY\nexport AWS_SECRET_ACCESS_KEY=secret\nexport AWS_SESSION_TOKEN=token\n'
FAKE
chmod +x "$BIN/aws"
export FAKE_AWS_ASKED="$WORK/asked" FAKE_AWS_STALE="$WORK/stale"

run() { (cd "$REPO_DIR/sub" && PATH="$BIN:$PATH" AWS_PROFILE= AWS_ACCESS_KEY_ID= bash "$ENV_SH" "$@"); }

# 1. The session's credentials reach the command, and the wrapped status comes back.
out=$(run env 2>&1) && code=0 || code=$?
check "the command sees the exported key" "printf '%s\n' \"\$out\" | grep -q '^AWS_ACCESS_KEY_ID=ASIATESTKEY$'"
check "the command sees the session token" "printf '%s\n' \"\$out\" | grep -q '^AWS_SESSION_TOKEN=token$'"
check "the profile comes from the repo's .envrc" "grep -q -- '--profile' '$WORK/asked' && grep -q 'atlas-staging' '$WORK/asked'"

out=$(run bash -c 'exit 7' 2>&1) && code=0 || code=$?
check "the wrapped command's exit status is the script's" "[ $code -eq 7 ]"

# 2. A stale session stops before the command runs, and names the fix.
touch "$FAKE_AWS_STALE"
out=$(run bash -c 'echo RAN' 2>&1) && code=0 || code=$?
check "a stale session exits 1" "[ $code -eq 1 ]"
check "nothing ran" "! printf '%s\n' \"\$out\" | grep -q RAN"
check "it names the profile and Strider" \
  "printf '%s\n' \"\$out\" | grep -q \"profile='atlas-staging'\" && printf '%s\n' \"\$out\" | grep -q Strider"
rm -f "$FAKE_AWS_STALE"

# 3. Credentials already in the environment are used as they are, not replaced.
rm -f "$WORK/asked"
out=$( (cd "$REPO_DIR/sub" && PATH="$BIN:$PATH" AWS_PROFILE= AWS_ACCESS_KEY_ID=ALREADYSET bash "$ENV_SH" bash -c 'echo "$AWS_ACCESS_KEY_ID"') 2>&1)
check "an exported key is left alone" "[ \"$out\" = ALREADYSET ]"
check "aws is not asked at all" "[ ! -f '$WORK/asked' ]"

# 4. No command is a usage error, not a silent success.
run >/dev/null 2>&1 && code=0 || code=$?
check "no command exits 2" "[ $code -eq 2 ]"

exit "$fail"
