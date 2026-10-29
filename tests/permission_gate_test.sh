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
[ "$(grep -c 'typesafe/jev-1.13' "$GATE_FILE")" = "1" ]
grep -q "JEV_PASS_AT = 0.9" "$GATE_FILE"
grep -q "JEV_TIMEOUT_MS = 1_500" "$GATE_FILE"

node --input-type=module <<'EOF'
import { pathToFileURL } from "node:url";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync, appendFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { homedir, tmpdir } from "node:os";

// The test imports the extension's real decision functions. It must not
// re-implement the order or the middle-band rules.
const { default: registerGate, evaluate, isJevEligible, parseJevDecision, bashRules, repoDecision } = await import(pathToFileURL(process.env.GATE_FILE).href);

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

// --- Repo rules from <cwd>/.claude/settings.json --------------------------
const repoDir = mkdtempSync(`${tmpdir()}/jev-repo-`);
const rulesFile = `${repoDir}/settings.json`;
writeFileSync(
  rulesFile,
  JSON.stringify({
    permissions: {
      allow: [
        "Bash(python3 .github/scripts/pytest_targets.py *)",
        "Bash(direnv allow)",
        "Bash(pytest)",
        "Bash(pytest *)",
        "Bash(databricks bundle validate *)",
        "Bash(git diff:*)",
        "Read(./secrets.env)",
        "Bash(sudo *)",
        "Bash(rm -rf /tmp/scratch)",
      ],
      deny: ["Bash(databricks bundle deploy*)", "Bash(pytest slow *)"],
    },
  }),
);
const rules = bashRules(rulesFile);
check("repo rules: Bash entries only", rules.allow.length + rules.deny.length, 10);
check("repo rules: non-Bash entry ignored", rules.allow.includes("Read(./secrets.env)"), false);
check("repo rules: legacy cmd:* normalised", rules.allow.includes("git diff*"), true);
check("repo rules: missing file", JSON.stringify(bashRules(`${repoDir}/nope.json`)), '{"allow":[],"deny":[]}');
writeFileSync(`${repoDir}/bad.json`, "{not json");
check("repo rules: malformed JSON", JSON.stringify(bashRules(`${repoDir}/bad.json`)), '{"allow":[],"deny":[]}');
check("repo allow: exact", repoDecision("direnv allow", rules), "allow");
check("repo allow: exact does not match extra args", repoDecision("direnv allow --verbose", rules), undefined);
check("repo allow: glob with space", repoDecision("pytest -x tests/", rules), "allow");
check("repo allow: bare command via its own entry", repoDecision("pytest", rules), "allow");
check("repo allow: prefix glob without space", repoDecision("databricks bundle validate --target prod", rules), "allow");
check("repo allow: legacy prefix form", repoDecision("git diff --stat", rules), "allow");
check("repo deny: prefix glob", repoDecision("databricks bundle deploy --target prod", rules), "block");
check("repo deny beats repo allow", repoDecision("pytest slow tests/", rules), "block");
check("repo rules: unrelated command", repoDecision("ls -la", rules), undefined);


// catalog. Use only the dedicated key, without changing chat authentication.
let handler;
registerGate({ on: (event, fn) => { if (event === "tool_call") handler = fn; } });
const savedEnv = { ...process.env };
const savedFetch = globalThis.fetch;
const home = mkdtempSync(`${tmpdir()}/jev-gate-`);
const command = "aws s3api head-object --bucket b --key k";
const context = { hasUI: false, get modelRegistry() { throw new Error("Catalog must not be used"); } };
const invoke = (cmd = command, ctx = context) => handler({ toolName: "bash", input: { command: cmd } }, ctx);
let calls = 0, request, probability = 0.95;
const fakeFetch = async (url, options) => {
  calls += 1;
  request = { url, options };
  return { ok: true, json: async () => ({ answers: { read_only: { type: "noul", noul: probability } } }) };
};

// --- Handler honours repo rules, but not for unoverridable denials ---------
const projectDir = mkdtempSync(`${tmpdir()}/jev-project-`);
mkdirSync(`${projectDir}/.claude`);
writeFileSync(
  `${projectDir}/.claude/settings.json`,
  JSON.stringify({
    permissions: {
      allow: ["Bash(databricks bundle run *)", "Bash(sudo *)", "Bash(rm -rf /tmp/scratch)"],
      deny: ["Bash(databricks bundle validate *)"],
    },
  }),
);
const projectCtx = { hasUI: false, cwd: projectDir };
const repoAllowCalls = calls;
const gitIn = (...args) =>
  execFileSync("git", ["-c", "user.email=t@t", "-c", "user.name=t", "-C", projectDir, ...args], { stdio: "ignore" });
check(
  "untracked repo rules are ignored",
  (await invoke("databricks bundle run --target prod", projectCtx))?.block,
  true,
);
gitIn("init", "-q");
gitIn("add", ".claude/settings.json");
check(
  "staged-but-uncommitted repo rules are ignored",
  (await invoke("databricks bundle run --target prod", projectCtx))?.block,
  true,
);
gitIn("commit", "-qm", "settings");
check(
  "repo allow runs a command the gate blocks",
  await invoke("databricks bundle run --target prod", projectCtx),
  undefined,
);
check("repo allow skips Jev", calls, repoAllowCalls);
check(
  "repo deny blocks a command the allowlist allows",
  (await invoke("databricks bundle validate --target prod", projectCtx))?.reason,
  "Blocked: listed in .claude/settings.json deny",
);
check(
  "repo allow cannot unlock rm -rf",
  (await invoke("rm -rf /tmp/scratch", projectCtx))?.reason,
  "Blocked: Recursive force delete",
);
check(
  "repo allow cannot unlock sudo",
  (await invoke("sudo aws s3 ls", projectCtx))?.block,
  true,
);
check("repo rules never call Jev", calls, repoAllowCalls);
appendFileSync(`${projectDir}/.claude/settings.json`, "\n");
check(
  "a dirty settings file is ignored",
  (await invoke("databricks bundle run --target prod", projectCtx))?.block,
  true,
);
check(
  "a dirty settings file drops its deny too",
  (await invoke("databricks bundle validate --target prod", projectCtx)),
  undefined,
);
rmSync(projectDir, { recursive: true, force: true });
try {
  process.env.HOME = home;
  delete process.env.JEV_OPENROUTER_API_KEY;
  process.env.OPENROUTER_API_KEY = "unchanged-chat-key";
  writeFileSync(`${home}/.env`, 'JEV_OPENROUTER_API_KEY="  file-jev-key  "\nOPENROUTER_API_KEY=must-not-load\n');
  globalThis.fetch = fakeFetch;
  check("isolated home for credential test", homedir(), home);
  check("workspace-file pass runs with no catalog", await invoke(), undefined);
  check("one Jev call", calls, 1);
  check("fixed Jev endpoint", request?.url, "https://openrouter.ai/api/v1/systemone");
  check("only the workspace key is sent", request?.options.headers.authorization, "Bearer file-jev-key");
  check("chat authentication is unchanged", process.env.OPENROUTER_API_KEY, "unchanged-chat-key");
  check("dotenv key is not installed into process environment", process.env.JEV_OPENROUTER_API_KEY, undefined);
  check("request judges the command alone", JSON.stringify(JSON.parse(request?.options.body ?? "{}").state), JSON.stringify({ command }));
  check("request has an abort signal", request?.options.signal instanceof AbortSignal, true);

  process.env.JEV_OPENROUTER_API_KEY = "  environment-jev-key  ";
  check("exported workspace key also passes", await invoke(), undefined);
  check("exported key overrides file key", request?.options.headers.authorization, "Bearer environment-jev-key");
  probability = 0.1;
  check("live-handler deny names Jev", (await invoke())?.reason?.startsWith("Blocked by Jev:"), true);
  for (const [label, fetcher] of [
    ["non-200", async () => ({ ok: false })],
    ["network error", async () => { throw new Error("offline"); }],
    ["bad JSON", async () => ({ ok: true, json: async () => { throw new Error("bad JSON"); } })],
  ]) {
    globalThis.fetch = fetcher;
    check(`${label} retains catch-all deny`, (await invoke())?.reason, "Blocked: AWS outside read-only allowlist");
  }
  globalThis.fetch = fakeFetch;
  const aborted = AbortSignal.abort();
  await invoke(command, { hasUI: false, signal: aborted });
  check("tool abort is composed into request", request?.options.signal.aborted, true);

  const before = calls;
  for (const cmd of ["aws s3 cp s3://b/k .", "aws s3api head-object --bucket b && echo x", "sudo aws s3 ls", "rm -rf /tmp/x"]) {
    check(`unsafe command remains blocked: ${cmd}`, (await invoke(cmd))?.block, true);
  }
  check("unsafe commands never call Jev", calls, before);
  check("sudo still uses confirmation", await invoke("sudo aws s3 ls", { hasUI: true, ui: { select: async () => "Yes" } }), undefined);
  delete process.env.JEV_OPENROUTER_API_KEY;
  writeFileSync(`${home}/.env`, "OPENROUTER_API_KEY=not-a-jev-key\n");
  check("missing dedicated key retains catch-all deny", (await invoke())?.reason, "Blocked: AWS outside read-only allowlist");
  rmSync(`${home}/.env`);
  check("missing dotenv retains catch-all deny", (await invoke())?.reason, "Blocked: AWS outside read-only allowlist");
  check("missing key never calls Jev", calls, before);
  // A guardrail block is the key's state, not the command's. Keep this last: the
  // latch is process-global, so every later Jev check would silently skip.
  const beforeBlock = calls;
  process.env.JEV_OPENROUTER_API_KEY = "blocked-key";
  globalThis.fetch = async () => {
    calls += 1;
    return { ok: false, status: 404, text: async () => '{"error":{"message":"Model blocked by guardrail"}}' };
  };
  check("guardrail block retains catch-all deny", (await invoke())?.reason, "Blocked: AWS outside read-only allowlist");
  check("guardrail block spends one call", calls, beforeBlock + 1);
  globalThis.fetch = fakeFetch;
  check("guardrail block is not retried", (await invoke())?.reason, "Blocked: AWS outside read-only allowlist");
  check("no Jev call after a guardrail block", calls, beforeBlock + 1);
} finally {
  globalThis.fetch = savedFetch;
  for (const key of Object.keys(process.env)) if (!(key in savedEnv)) delete process.env[key];
  Object.assign(process.env, savedEnv);
  rmSync(home, { recursive: true, force: true });
  rmSync(repoDir, { recursive: true, force: true });
}

process.exit(failed);
EOF
