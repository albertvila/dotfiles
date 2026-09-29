#!/usr/bin/env bash
# Checks the permission gate's read-only allowlists really match the commands the
# ops skills (lm-fireline, den-triage) are documented to run — in particular the
# hyphenated Databricks verbs (jobs get-run, jobs list-runs) — and that write
# verbs still fall through to the auto-deny block instead of the allowlist.
set -eo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE_FILE="$REPO/home/.pi/agent/extensions/permission-gate.ts"
export GATE_FILE

node --input-type=module <<'EOF'
import { readFileSync } from "node:fs";

// Patterns are read out of the extension itself so the test cannot drift from it.
// Only double-quoted literals are parsed: the SQL allowlist rule is single-quoted
// (and out of scope here) and is simply ignored.
const ts = readFileSync(process.env.GATE_FILE, "utf8");
const patterns = {};
const entry = /pattern:\s*("(?:\\.|[^"\\])*")[\s\S]*?description:\s*"([^"]*)"/g;
for (const m of ts.matchAll(entry)) patterns[m[2]] = JSON.parse(m[1]);

const need = (d) => {
  if (!patterns[d]) throw new Error(`no pattern in permission-gate.ts with description "${d}"`);
  return new RegExp(patterns[d]);
};

const allowlist = [
  need("Read-only AWS ops (list/get/describe/ls/filter)"),
  need("Read-only Databricks ops (list/get/ls/cat/status/validate)"),
];
const denylist = [
  need("AWS outside read-only allowlist"),
  need("Databricks outside read-only allowlist"),
  need("Recursive force delete"),
];

// Mirrors the extension's order: allowlist bypasses, then auto-deny.
const decide = (cmd) => {
  if (allowlist.some((r) => r.test(cmd))) return "ALLOW";
  if (denylist.some((r) => r.test(cmd))) return "BLOCK";
  return "PROMPT";
};

const cases = [
  // --- Databricks read-only: the verbs the 2.x CLI actually uses -----------
  ["ALLOW", "databricks jobs get-run --run-id 374325194859810"],
  ["ALLOW", "databricks jobs get-run-output --run-id 374325194859810"],
  ["ALLOW", "databricks jobs get --job-id 168800064741092"],
  ["ALLOW", "databricks jobs list-runs --job-id 168800064741092 --limit 10"],
  ["ALLOW", "databricks clusters get --cluster-id 0924-180011-yxz70c25"],
  ["ALLOW", "databricks runs get --run-id 1"],
  ["ALLOW", "databricks runs list --job-id 1 --limit 10"],
  ["ALLOW", "databricks api get /api/2.1/jobs/runs/get?run_id=1"],
  ["ALLOW", "databricks fs ls dbfs:/cluster-logs/"],
  ["ALLOW", "DATABRICKS_HOST=https://lm-atlas.cloud.databricks.com databricks jobs get-run --run-id 1"],

  // --- Databricks writes must stay blocked ---------------------------------
  ["BLOCK", "databricks jobs repair-run --run-id 1"],
  ["BLOCK", "databricks jobs delete-run --run-id 1"],
  ["BLOCK", "databricks jobs reset --job-id 1"],
  ["BLOCK", "databricks jobs run-now --job-id 1"],
  ["BLOCK", "databricks fs rm -r dbfs:/data"],
  ["BLOCK", "databricks secrets put --scope x --key y"],
  ["BLOCK", "databricks api post /api/2.1/jobs/run-now"],
  ["BLOCK", "databricks jobs list-runs --job-id 1 && rm -rf /tmp/x"],
  ["BLOCK", "databricks jobs list-runs --job-id 1; rm -rf /tmp/x"],

  // --- AWS read-only allowlist ---------------------------------------------
  ["ALLOW", "aws cloudwatch describe-alarm-history --alarm-name x --region eu-west-1"],
  ["ALLOW", "aws lambda get-function-configuration --function-name x --region eu-west-1"],
  ["ALLOW", "aws logs get-log-events --log-group-name /aws/lambda/x --region eu-west-1"],
  ["ALLOW", 'aws logs filter-log-events --log-group-name /aws/lambda/x --filter-pattern "ERROR" --start-time 1 --end-time 2 --limit 50 --region eu-west-1'],

  // --- AWS writes must stay blocked (incl. via the `filter` verb) ----------
  ["BLOCK", "aws s3 rm s3://bucket/key --recursive"],
  ["BLOCK", "aws lambda delete-function --function-name x"],
  ["BLOCK", "aws logs delete-log-group --log-group-name /aws/lambda/x"],
  ["BLOCK", "aws ec2 terminate-instances --instance-ids i-123"],
  ["BLOCK", "aws logs filter-log-events --log-group-name x && rm -rf /tmp/x"],
];

let failed = 0;
for (const [expected, cmd] of cases) {
  const actual = decide(cmd);
  if (actual === expected) {
    console.log(`ok   - ${expected}  ${cmd}`);
  } else {
    console.log(`FAIL - expected ${expected}, got ${actual}: ${cmd}`);
    failed = 1;
  }
}
process.exit(failed);
EOF
