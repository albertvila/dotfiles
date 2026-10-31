#!/usr/bin/env bash
# aws-check decides one thing: does the profile this repo declares still answer
# STS? A false "stale" teaches the user to ignore it, and a false "OK" wastes a
# thread's retry, so both directions are checked here with a fake aws CLI.
set -eo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$REPO/home/.agents/scripts/aws-check"

fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

BIN="$WORK/bin"
REPO_DIR="$WORK/repo"
mkdir -p "$BIN" "$REPO_DIR/sub"
printf 'export AWS_PROFILE="atlas-staging"\n' > "$REPO_DIR/.envrc"

# A fake aws that records the profile it was asked for, and answers as told.
cat > "$BIN/aws" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" | grep -A1 -- '--profile' | tail -1 > "$WORK/asked"
if [ -f "$WORK/answering" ]; then cat "$WORK/answering"; exit 0; fi
echo "An error occurred (ExpiredToken)" >&2
exit 255
EOF
chmod +x "$BIN/aws"

# 1. stale: aws rejects, the check says so and names the profile from .envrc.
rm -f "$WORK/answering"
OUT=$(cd "$REPO_DIR/sub" && PATH="$BIN:$PATH" AWS_PROFILE= bash "$CHECK" 2>&1) && code=0 || code=$?
check "an expired session exits 1" "[ $code -eq 1 ]"
check "an expired session names the profile and the fix" \
  "printf '%s\n' \"\$OUT\" | grep -q \"STALE profile='atlas-staging'\" && printf '%s\n' \"\$OUT\" | grep -q Strider"
check "the profile comes from the repo's .envrc, not the default" \
  "[ \"\$(cat "$WORK/asked")\" = 'atlas-staging' ]"

# 2. fresh: STS answers, account is reported, exit 0.
printf '{"UserId":"AIDA","Account":"295330289955","Arn":"arn:aws:sts::295330289955:assumed-role/x/y"}\n' > "$WORK/answering"
OUT=$(cd "$REPO_DIR/sub" && PATH="$BIN:$PATH" AWS_PROFILE= bash "$CHECK" 2>&1) && code=0 || code=$?
check "a live session exits 0" "[ $code -eq 0 ]"
check "a live session reports the account" \
  "printf '%s\n' \"\$OUT\" | grep -q 'OK.*atlas-staging.*account=295330289955'"

# 3. AWS_PROFILE in the environment wins over the file.
OUT=$(cd "$REPO_DIR" && PATH="$BIN:$PATH" AWS_PROFILE=discover-prod bash "$CHECK" 2>&1) || true
check "the exported AWS_PROFILE wins over .envrc" \
  "[ \"\$(cat "$WORK/asked")\" = 'discover-prod' ]"

# 4. No aws CLI: cannot tell, and says so instead of inventing an answer.
OUT=$(cd "$REPO_DIR" && PATH=/usr/bin:/bin AWS_PROFILE= bash "$CHECK" 2>&1) && code=0 || code=$?
check "a missing aws CLI exits 2" "[ $code -eq 2 ]"
check "a missing aws CLI is not reported as stale" \
  "printf '%s\n' \"\$OUT\" | grep -q 'cannot verify'"

exit "$fail"
