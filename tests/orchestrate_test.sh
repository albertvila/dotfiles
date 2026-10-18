#!/usr/bin/env bash
# Runs every orchestrate script's own `--self-test`, then drives the Herdr
# adapter over a fixture ledger and transcript. The self-tests hold the
# invariants a diff never shows — the ledger shape, the cause vocabulary, the
# item lifecycle, the shared record's figures — and nothing else ran them: the
# only previous coverage of this family was the body budget in
# skills_budget_test.sh, which measures file size, not behaviour.
set -eo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS="$REPO/home/.agents/skills"
PYTHON="${PYTHON:-python3}"

fail=0
shopt -s nullglob
scripts=("$SKILLS"/orchestrate-*/scripts/*.py)
[ "${#scripts[@]}" -gt 0 ] || { echo "FAIL - no orchestrate scripts found under $SKILLS"; exit 1; }

for script in "${scripts[@]}"; do
  name="$(basename "$(dirname "$(dirname "$script")")")/$(basename "$script")"
  if out="$("$PYTHON" "$script" --self-test 2>&1)"; then
    echo "ok   - $name --self-test"
  else
    echo "FAIL - $name --self-test"
    printf '%s\n' "$out" | sed 's/^/       /'
    fail=1
  fi
done

# The disk path, not just the pure functions: a ledger plus a pi transcript
# through the Herdr adapter must yield the shared record (schemaVersion 2).
ROUND=$(mktemp -d)
trap 'rm -rf "$ROUND"' EXIT
"$PYTHON" - "$ROUND" <<'PY'
import json, os, sys
rundir = sys.argv[1]
session = os.path.join(rundir, "item-01.jsonl")
with open(session, "w", encoding="utf-8") as handle:
    handle.write(json.dumps({
        "type": "message", "timestamp": "2026-01-01T12:01:00Z",
        "message": {"role": "assistant", "provider": "vendor", "model": "worker",
                    "usage": {"totalTokens": 10, "cost": {"total": 0.01}}}}) + "\n")
ledger = {
    "runtime": "herdr", "feature": "self-test", "tracker": "scratch self-test",
    "flow": "A", "mode": "gated", "rundir": rundir + "/.herdr-runs/self-test",
    "startedAt": "2026-01-01T12:00:00Z", "finishedAt": "2026-01-01T12:10:00Z",
    "executors": [{"id": "coordinator", "session": None}],
    "items": {"01": {"status": "done", "worker": {"id": "item-01", "session": session}}},
}
with open(os.path.join(rundir, "orchestration.json"), "w", encoding="utf-8") as handle:
    json.dump(ledger, handle)
PY

HERDR="$SKILLS/orchestrate-herdr-retro/scripts/run-metrics.py"
if out="$("$PYTHON" "$HERDR" "$ROUND" --json 2>&1)"; then
  if printf '%s' "$out" | "$PYTHON" -c 'import json, sys; r = json.load(sys.stdin); assert r["schemaVersion"] == 2 and r["runtime"] == "herdr"; assert any(l["role"] == "worker" for l in r["lanes"]); assert r["run"]["spanSec"] == 600' 2>/tmp/orchestrate_round.err; then
    echo "ok   - herdr fixture round trip -> shared record (schemaVersion 2)"
  else
    echo "FAIL - herdr fixture round trip: the record is not the shared shape"
    sed 's/^/       /' /tmp/orchestrate_round.err
    fail=1
  fi
else
  echo "FAIL - herdr fixture round trip: the adapter exited non-zero"
  printf '%s\n' "$out" | sed 's/^/       /'
  fail=1
fi

exit "$fail"
