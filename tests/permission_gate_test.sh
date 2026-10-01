#!/usr/bin/env bash
# Checks the permission gate's real decision function against the commands the ops
# skills (lm-fireline, den-triage) are documented to run, and pins the Jev middle
# band: the read-only allowlist still wins, destructive denials and prompt-class
# commands never reach Jev, and only a blocked read-shaped aws/databricks command
# is eligible. The Jev response parser is checked offline.
set -eo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE_FILE="$REPO/home/.pi/agent/extensions/permission-gate.ts"
export GATE_FILE

# The Jev design is copied from Xavier's private package; keep it visible and keep
# the alias, threshold, and timeout in one place.
grep -q "Xavier" "$GATE_FILE"
grep -q "cannot be fetched" "$GATE_FILE"
[ "$(grep -c '~typesafe/jev-latest' "$GATE_FILE")" = "1" ]
grep -q "JEV_PASS_AT = 0.9" "$GATE_FILE"
grep -q "JEV_TIMEOUT_MS = 1_500" "$GATE_FILE"

node --input-type=module <<'EOF'
import { pathToFileURL } from "node:url";

// The test imports the extension's real decision functions. It must not
// re-implement the order or the middle-band rules.
const { evaluate, isJevEligible, parseJevDecision } = await import(pathToFileURL(process.env.GATE_FILE).href);

let failed = 0;
const check = (label, actual, expected) => {
  if (actual === expected) {
    console.log(`ok   - ${label}`);
  } else {
    console.log(`FAIL - expected ${expected}, got ${actual}: ${label}`);
    failed = 1;
  }
};

// --- Deterministic policy: allow, deny, prompt -----------------------------
const decisions = [
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
  ["ALLOW", 'databricks sql execute --warehouse-id w --query "select 1"'],
  ["ALLOW", 'databricks sql execute --query "SELECT * FROM t"'],

  // --- Databricks writes must stay blocked ---------------------------------
  ["BLOCK", "databricks jobs repair-run --run-id 1"],
  ["BLOCK", "databricks jobs delete-run --run-id 1"],
  ["BLOCK", "databricks jobs reset --job-id 1"],
  ["BLOCK", "databricks jobs run-now --job-id 1"],
  ["BLOCK", "databricks fs rm -r dbfs:/data"],
  ["BLOCK", "databricks secrets put --scope x --key y"],
  ["BLOCK", "databricks api post /api/2.1/jobs/run-now"],
  ["BLOCK", 'databricks sql execute --query "select * from x where a = \'$foo\'"'],
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
  ["BLOCK", "aws sts assume-role --role-arn arn:aws:iam::1:role/x"],

  // --- Destructive hard denials and prompt-class commands ------------------
  ["BLOCK", "rm -rf /tmp/x"],
  ["BLOCK", "git reset --hard"],
  ["BLOCK", "terraform destroy"],
  ["BLOCK", "sudo rm -rf /tmp/x"],
  ["PROMPT", "sudo aws s3 ls s3://bucket"],
  ["PROMPT", "chmod 777 /tmp/x"],
  ["PROMPT", "chown albert 777 /tmp/x"],

  // --- Case-shifted destructive and prompt payloads execute the same --------
  ["BLOCK", "RM -RF /tmp/x"],
  ["BLOCK", "TERRAFORM DESTROY -auto-approve"],
  ["BLOCK", "NPM PUBLISH"],
  ["BLOCK", "DISKUTIL eraseDisk"],
  ["BLOCK", "GIT RESET --HARD"],
  ["BLOCK", "MKFS.EXT4 /dev/sda"],
  ["PROMPT", "SUDO reboot"],
  ["PROMPT", "CHMOD 777 /etc/passwd"],
  ["PROMPT", "CHOWN root:root 777 /etc/passwd"],
];

for (const [expected, cmd] of decisions) check(`${expected}  ${cmd}`, evaluate(cmd).toUpperCase(), expected);

// --- Middle band: only a blocked read-shaped aws/databricks command -------
const eligible = [
  [true, "aws s3api head-object --bucket b --key k"],
  [true, "aws logs tail /aws/lambda/x"],
  [true, "databricks account networks list"],
  [false, "aws cloudwatch describe-alarm-history --alarm-name x"],
  [false, "databricks jobs list-runs --job-id 1"],
  [false, "aws s3api put-object --bucket b --key k"],
  [false, "aws s3 cp s3://bucket/key ."],
  [false, "databricks jobs repair-run --run-id 1"],
  [false, "aws sts assume-role --role-arn arn:aws:iam::1:role/x"],
  [false, 'databricks sql execute --query "select * from x where a = \'$foo\'"'],
  [false, 'databricks --profile x sql execute --query "select * from t where a = \'$foo\'"'],
  [false, "databricks jobs list-runs --job-id 1 && rm -rf /tmp/x"],
  [false, "rm -rf /tmp/x"],
  [false, "git reset --hard"],
  [false, "sudo aws s3 ls s3://bucket"],
  [false, "chmod 777 /tmp/x"],
  [false, "aws logs tail /aws/lambda/x\naws s3api restore-object --bucket b --key k"],

  // --- Export and copy verbs are the cp class ------------------------------
  [false, "databricks workspace export /Shared/notebook --format SOURCE --output-file list.txt"],
  [false, "aws s3api copy-object --bucket b --key k --copy-source src --output list"],
  [false, "aws ec2 copy-snapshot --source-region eu-west-1 --source-snapshot-id snap-1"],
  [false, "aws rds copy-db-snapshot --source-db-snapshot-identifier x --target-db-snapshot-identifier y"],

  // --- Mixed-case SQL is still SQL ----------------------------------------
  [false, 'databricks SQL execute --query "DELETE FROM t WHERE id IN (select id from x)"'],

  // --- A read token in an argument cannot rescue an unknown verb -----------
  [false, 'aws ssm send-command --parameters commands=["echo list"] --targets list'],
  [true, "aws --region eu-west-1 logs tail /aws/lambda/x"],
  [true, "databricks --profile x account networks list"],
];

for (const [expected, cmd] of eligible) check(`Jev eligible=${expected}  ${JSON.stringify(cmd)}`, isJevEligible(cmd), expected);

// --- Only the aws/databricks catch-all deny is middle band ----------------
// A destructive or prompt payload embedded as a parameter value must not make
// a generic command Jev-eligible, in either case form.
const hostilePayloads = [
  "terraform destroy -auto-approve",
  "rm -rf /tmp",
  "mkfs.ext4 /dev/sda",
  "diskutil eraseDisk",
  "npm publish",
  "git reset --hard",
  "sudo ls",
  "chmod 777 /tmp",
  "databricks workspace export /Shared/nb",
  "TERRAFORM DESTROY -auto-approve",
  "DISKUTIL eraseDisk",
  "NPM PUBLISH",
  "SUDO reboot",
  "CHMOD 777 /etc/passwd",
  "CHOWN root:root 777 /etc/passwd",
];
const hostileTemplates = [
  (p) => `aws ssm send-command --document-name AWS-RunShellScript --parameters commands=["${p}"] --targets list`,
  (p) => `databricks runs tail --filter "${p}"`,
  (p) => `aws logs tail /aws/lambda/x --filter-pattern "${p}"`,
];
for (const payload of hostilePayloads) {
  for (const template of hostileTemplates) {
    const cmd = template(payload);
    check(`Jev eligible=false  payload=${JSON.stringify(payload)}  ${JSON.stringify(cmd)}`, isJevEligible(cmd), false);
  }
}

// --- Jev payload parser, offline ------------------------------------------
const payloads = [
  [true, { answers: { read_only: { type: "noul", noul: 0.95 } } }],
  [true, { answers: { read_only: { type: "noul", noul: 0.9 } } }],
  [true, { answers: { read_only: { type: "noul", noul: 1 } } }],
  [false, { answers: { read_only: { type: "noul", noul: 0.89 } } }],
  [false, { answers: { read_only: { type: "noul", noul: 0 } } }],
  [undefined, { answers: { read_only: { type: "noul", noul: 1.01 } } }],
  [undefined, { answers: { read_only: { type: "noul", noul: -0.01 } } }],
  [undefined, { answers: { read_only: { type: "noul", noul: "0.95" } } }],
  [undefined, { answers: { read_only: { type: "choice", choice: "yes", probabilities: { yes: 0.95 }, confidence: 0.9 } } }],
  [undefined, { answers: { read_only: { type: "score", score: 1.99, confidence: 0.9 } } }],
  [undefined, { answers: {} }],
  [undefined, {}],
  [undefined, null],
  [undefined, "yes"],
  [undefined, []],
  [undefined, { answers: [] }],
  [undefined, { answers: { read_only: null } }],
];

for (const [expected, payload] of payloads) check(`Jev parse ${JSON.stringify(payload)}`, parseJevDecision(payload), expected);

process.exit(failed);
EOF
