#!/usr/bin/env bash
# aws-check decides two things: does the profile this repo declares still answer
# STS, and if not, who can fix it (a login, or the role in ~/.aws/config). A
# false "stale" teaches the user to ignore it, and a false "OK" wastes a
# thread's retry, so every direction is checked here with a fake aws CLI.
set -eo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$REPO/home/.agents/scripts/aws-check"

fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

BIN="$WORK/bin"
REPO_DIR="$WORK/repo"
AWSHOME="$WORK/aws"
mkdir -p "$BIN" "$REPO_DIR/sub" "$AWSHOME/.aws"
printf 'export AWS_PROFILE="atlas-staging"\n' > "$REPO_DIR/.envrc"
printf '[profile atlas-staging]\nregion = eu-west-1\n' > "$AWSHOME/.aws/config"

# A fake aws that records the profile it was asked for, and answers as told.
cat > "$BIN/aws" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" | grep -A1 -- '--profile' | tail -1 > "$WORK/asked"
if [ -f "$WORK/answering" ]; then cat "$WORK/answering"; exit 0; fi
if [ -f "$WORK/stderr" ]; then cat "$WORK/stderr"; exit 255; fi
echo "An error occurred (ExpiredToken)" >&2
exit 255
EOF
chmod +x "$BIN/aws"

# 1. stale: aws rejects, the check says so and names the profile from .envrc.
rm -f "$WORK/answering" "$WORK/stderr"
OUT=$(cd "$REPO_DIR/sub" && PATH="$BIN:$PATH" HOME="$AWSHOME" AWS_PROFILE= bash "$CHECK" 2>&1) && code=0 || code=$?
check "an expired session exits 1" "[ $code -eq 1 ]"
check "an expired session names the profile and the fix" \
  "printf '%s\n' \"\$OUT\" | grep -q \"STALE profile='atlas-staging'\" && printf '%s\n' \"\$OUT\" | grep -q Strider"
check "the profile comes from the repo's .envrc, not the default" \
  "[ \"\$(cat "$WORK/asked")\" = 'atlas-staging' ]"

# 1b. An SSO profile refreshes from its session, so the login is the fix.
printf '[sso-session lm-global]\nsso_start_url = https://example.awsapps.com/start/\nsso_region = eu-west-1\n\n[profile atlas-staging]\nsso_session = lm-global\nregion = eu-west-1\n' > "$AWSHOME/.aws/config"
OUT=$(cd "$REPO_DIR/sub" && PATH="$BIN:$PATH" HOME="$AWSHOME" AWS_PROFILE= bash "$CHECK" 2>&1) || true
check "an SSO profile names the login that fixes it" \
  "printf '%s\n' \"\$OUT\" | grep -q 'aws sso login --sso-session lm-global'"

# 1c. A role the user is not assigned is not a stale session: no login fixes it.
printf 'An error occurred (ForbiddenException) when calling the GetRoleCredentials operation: No access\n' > "$WORK/stderr"
OUT=$(cd "$REPO_DIR/sub" && PATH="$BIN:$PATH" HOME="$AWSHOME" AWS_PROFILE= bash "$CHECK" 2>&1) && code=0 || code=$?
check "a role that is not yours exits 1" "[ $code -eq 1 ]"
check "a role that is not yours says DENIED and points at the config" \
  "printf '%s\n' \"\$OUT\" | grep -q 'DENIED profile=.*sso_role_name' && ! printf '%s\n' \"\$OUT\" | grep -q STALE"
rm -f "$WORK/stderr"

# 2. fresh: STS answers, account is reported, exit 0.
printf '{"UserId":"AIDA","Account":"295330289955","Arn":"arn:aws:sts::295330289955:assumed-role/x/y"}\n' > "$WORK/answering"
OUT=$(cd "$REPO_DIR/sub" && PATH="$BIN:$PATH" HOME="$AWSHOME" AWS_PROFILE= bash "$CHECK" 2>&1) && code=0 || code=$?
check "a live session exits 0" "[ $code -eq 0 ]"
check "a live session reports the account" \
  "printf '%s\n' \"\$OUT\" | grep -q 'OK.*atlas-staging.*account=295330289955'"

# 3. AWS_PROFILE in the environment wins over the file.
OUT=$(cd "$REPO_DIR" && PATH="$BIN:$PATH" HOME="$AWSHOME" AWS_PROFILE=discover-prod bash "$CHECK" 2>&1) || true
check "the exported AWS_PROFILE wins over .envrc" \
  "[ \"\$(cat "$WORK/asked")\" = 'discover-prod' ]"
check "a declared profile is not marked as assumed" \
  "printf '%s\n' \"\$OUT\" | grep -q \"profile='discover-prod' account\""

# 4. Nothing declares a profile: atlas-staging wins while ~/.aws knows it,
#    then aws's own fallback.
BARE="$WORK/bare"
FAKEHOME="$WORK/home"
mkdir -p "$BARE" "$FAKEHOME/.aws"
printf 'echo hello\n' > "$BARE/.envrc"
printf '[profile atlas-staging]\nregion=eu-west-1\n\n[default]\nregion=eu-west-1\n' > "$FAKEHOME/.aws/config"
OUT=$(cd "$BARE" && PATH="$BIN:$PATH" HOME="$FAKEHOME" AWS_PROFILE= bash "$CHECK" 2>&1) || true
check "with nothing declared, atlas-staging is preferred" \
  "[ \"\$(cat "$WORK/asked")\" = 'atlas-staging' ]"
check "a guessed profile is marked as assumed" \
  "printf '%s\n' \"\$OUT\" | grep -q \"profile='atlas-staging' (assumed)\""

printf '[profile discover-prod]\nregion=eu-west-1\n' > "$FAKEHOME/.aws/config"
OUT=$(cd "$BARE" && PATH="$BIN:$PATH" HOME="$FAKEHOME" AWS_PROFILE= bash "$CHECK" 2>&1) || true
check "with no atlas-staging in ~/.aws, default is used" \
  "[ \"\$(cat "$WORK/asked")\" = 'default' ]"

# 5. No aws CLI: cannot tell, and says so instead of inventing an answer.
OUT=$(cd "$REPO_DIR" && PATH=/usr/bin:/bin AWS_PROFILE= bash "$CHECK" 2>&1) && code=0 || code=$?
check "a missing aws CLI exits 2" "[ $code -eq 2 ]"
check "a missing aws CLI is not reported as stale" \
  "printf '%s\n' \"\$OUT\" | grep -q 'cannot verify'"

exit "$fail"
