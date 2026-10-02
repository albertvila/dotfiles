/**
 * Permission Gate Extension
 *
 * Adapted from xriu/dotfiles permission-gate.ts (originally migrated from
 * pi-guardrails permissionGate). Adds a Databricks allowlist/denylist pair
 * mirroring the AWS one.
 * Order: allowlist bypasses checks, then auto-deny blocks, then prompt patterns ask.
 * Matching: case-insensitive substring unless marked regex.
 *
 * Strict mode: any non-read-only `aws`/`databricks` command is blocked
 * outright, with no prompt-to-allow. Narrow the denylists if that gets in
 * the way. Chained commands (&&, ||, ;) never match an allowlist, so mixing
 * a read with a write fails closed.
 *
 * Middle band: an `aws`/`databricks` command outside the allowlist that still
 * looks like a read gets one yes/no from Jev before it is denied. A pass runs
 * it; a deny blocks it and names Jev; any failure falls through to the
 * catch-all deny. Writes, exports, unknown verbs, SQL misses, chains,
 * destructive hard denials, `sudo`, and world-writable permission changes
 * never reach Jev. The Jev design comes from Xavier Riu's private
 * `pi-extensions` package, recovered from his public dotfiles history on
 * 2026-09-27. That package is private and cannot be fetched from this machine,
 * so this file is the only copy; do not look for the upstream.
 */

import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { parseEnv } from "node:util";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

type Decision = "allow" | "block" | "prompt";
type Pattern = { pattern: string; regex?: boolean; flags?: string; description: string; enabled: boolean };

// Jev middle-band tuning. Threshold, timeout, and alias live here and nowhere else.
const JEV_PASS_AT = 0.9;
const JEV_TIMEOUT_MS = 1_500;
const JEV_MODEL = "~typesafe/jev-latest";
const JEV_ENDPOINT = "https://openrouter.ai/api/v1/systemone";

// Bypass all checks (no prompt).
const allowedPatterns: Pattern[] = [
	{
		pattern: "^(AWS_[A-Z_]+=\\S* +)*aws +[a-z0-9.-]+ +(list|get|describe|ls|filter)[a-z0-9.-]*( +[^;&|`$<>()\\n\\r]+)* *$",
		regex: true,
		description: "Read-only AWS ops (list/get/describe/ls/filter)",
		enabled: true,
	},
	{
		pattern: "^(DATABRICKS_[A-Z_]+=\\S* +)*databricks +[a-z0-9_.-]+ +(list|get|ls|cat|status|validate)[a-z0-9.-]*( +[^;&|`$<>()\\n\\r]+)* *$",
		regex: true,
		description: "Read-only Databricks ops (list/get/ls/cat/status/validate)",
		enabled: true,
	},
	{
		// ponytail: regex can't parse SQL — ceiling is "query starts with a read verb, no semicolons".
		// Fails closed: legit queries with ; inside string literals get blocked too. Upgrade path: a real SQL parser.
		// Double-quoted queries also exclude $ and backticks — bash would expand them before databricks runs.
		pattern:
			'^(DATABRICKS_[A-Z_]+=\\S* +)*databricks +sql +execute( +--[a-z0-9-]+( +=?[^ "\';&|`$<>()\\\\]+)?)* +--query +("(select|with|show|desc|describe|explain)\\b[^;"`$]*;?"|\'(select|with|show|desc|describe|explain)\\b[^;\']*;?\')( +--[a-z0-9-]+( +=?[^ "\';&|`$<>()\\\\]+)?)* *$',
		regex: true,
		flags: "i",
		description: "Read-only Databricks SQL (SELECT/WITH/SHOW/DESC/EXPLAIN, single statement)",
		enabled: true,
	},
];

// Always blocked without prompting: any aws/databricks command outside the
// allowlist. This is the only hard deny Jev may be offered.
const catchAllDenyPatterns: Pattern[] = [
	{ pattern: "(^|&&|\\|\\||;) *(AWS_[A-Z_]+=\\S* +)*aws\\b", regex: true, description: "AWS outside read-only allowlist", enabled: true },
	{ pattern: "(^|&&|\\|\\||;) *(DATABRICKS_[A-Z_]+=\\S* +)*databricks\\b", regex: true, description: "Databricks outside read-only allowlist", enabled: true },
];

// Destructive hard denials. Unoverridable, and never offered to Jev.
const destructiveDenyPatterns: Pattern[] = [
	{ pattern: "rm -rf", description: "Recursive force delete", enabled: true },
	{ pattern: "diskutil", description: "Disk utility operation", enabled: true },
	{ pattern: "git reset --hard", description: "Discards uncommitted changes", enabled: true },
	{ pattern: "mkfs", description: "Filesystem format", enabled: true },
	{ pattern: "npm publish", description: "Publishes npm package", enabled: true },
	{ pattern: "terraform apply", description: "Applies infra changes", enabled: true },
	{ pattern: "terraform destroy", description: "Destroys infra", enabled: true },
];

const autoDenyPatterns: Pattern[] = [...catchAllDenyPatterns, ...destructiveDenyPatterns];

// Prompt for confirmation (not covered by the guardrails config).
const promptPatterns: Pattern[] = [
	{ pattern: "\\bsudo\\b", regex: true, flags: "i", description: "Privileged command (sudo)", enabled: true },
	{ pattern: "\\b(chmod|chown)\\b.*777", regex: true, flags: "i", description: "World-writable permission change", enabled: true },
];

// Substring patterns are the destructive hard denials, matched case-insensitively
// so a case-shifted payload cannot slip past. Regex patterns use their own flags.
const matches = (command: string, p: Pattern) =>
	p.enabled && (p.regex ? new RegExp(p.pattern, p.flags).test(command) : command.toLowerCase().includes(p.pattern.toLowerCase()));

/** Today's deterministic policy: allowlist, then hard deny, then prompt class. No Jev. */
export function evaluate(command: string): Decision {
	if (allowedPatterns.some((p) => matches(command, p))) return "allow";
	if (autoDenyPatterns.some((p) => matches(command, p))) return "block";
	if (promptPatterns.some((p) => matches(command, p))) return "prompt";
	return "allow";
}

// A middle-band command needs a read-shaped token and no write or export token.
const READ_TOKENS = ["list", "get", "describe", "ls", "filter", "cat", "status", "validate", "select", "show", "desc", "explain", "tail", "head"];
const WRITE_TOKENS = ["cp", "copy", "sync", "mv", "rm", "put", "create", "delete", "update", "start", "stop", "run", "invoke", "apply", "login", "export"];
// Newline is a chain separator too, and the allowlist already rejects it.
const CHAIN = /[;&|\n\r]/;
// Chained commands are already excluded, so the target must be the command itself.
const JEV_TARGET = /^(AWS_[A-Z_]+=\S* +)*aws\b|^(DATABRICKS_[A-Z_]+=\S* +)*databricks\b/;
// `databricks` with `sql` anywhere in the invocation, including behind global flags
// such as `--profile x`. Broad on purpose: Jev must not become a SQL parser.
const DATABRICKS_SQL = /\bdatabricks\b.*\bsql\b/i;

const hasToken = (command: string, token: string) => new RegExp(`\\b${token}\\b`, "i").test(command);

// The read-shaped verb sits at the head of the command, before the first flag, so
// `--output list` cannot rescue an unknown verb. Ceiling: a positional argument
// before the first flag can still look like a verb; upgrade path is per-CLI verb
// parsing. The leading flag/value run is skipped so `--profile x` does not hide it.
function commandHead(command: string): string {
	const tokens = command.split(/\s+/);
	// Drop the env prefix and the `aws`/`databricks` word.
	let i = 0;
	while (i < tokens.length && !/^(aws|databricks)$/i.test(tokens[i])) i += 1;
	if (i < tokens.length) i += 1;
	// Skip a leading run of global flags and their values (e.g. `--profile x`).
	while (i < tokens.length && tokens[i].startsWith("-")) {
		i += 1;
		if (i < tokens.length && !tokens[i].startsWith("-")) i += 1;
	}
	return tokens.slice(i).join(" ").split("--")[0];
}

/** True only for a command the deterministic gate blocks and Jev may be asked about. */
export function isJevEligible(command: string): boolean {
	if (evaluate(command) !== "block") return false;
	// Only the aws/databricks catch-all deny is middle band. A destructive hard
	// denial or a prompt-class match anywhere in the command is not, even when it
	// sits inside a parameter value of an otherwise generic aws/databricks call.
	if (destructiveDenyPatterns.some((p) => matches(command, p))) return false;
	if (promptPatterns.some((p) => matches(command, p))) return false;
	if (CHAIN.test(command)) return false;
	if (!JEV_TARGET.test(command)) return false;
	if (DATABRICKS_SQL.test(command)) return false;
	// A write or export token anywhere disqualifies; only the verb position can qualify.
	if (WRITE_TOKENS.some((token) => hasToken(command, token))) return false;
	return READ_TOKENS.some((token) => hasToken(commandHead(command), token));
}

/** Jev's answer from a raw Decisions payload: true/pass, false/deny, undefined on anything else. */
export function parseJevDecision(payload: unknown): boolean | undefined {
	if (typeof payload !== "object" || payload === null) return undefined;
	const answers = (payload as { answers?: unknown }).answers;
	if (typeof answers !== "object" || answers === null) return undefined;
	const answer = Object.values(answers as Record<string, unknown>)[0];
	if (typeof answer !== "object" || answer === null) return undefined;
	const { type, noul } = answer as { type?: unknown; noul?: unknown };
	if (type !== "noul" || typeof noul !== "number" || !Number.isFinite(noul) || noul < 0 || noul > 1) return undefined;
	return noul >= JEV_PASS_AT;
}

/** One Decisions call on the command alone. Any failure means fall through. */
async function consultJev(command: string, ctx: ExtensionContext): Promise<boolean | undefined> {
	try {
		// Reuse the experiment's workspace key. BB may not inherit the shell env;
		// read the same key from ~/.env without loading or changing chat credentials.
		const key = (process.env.JEV_OPENROUTER_API_KEY || parseEnv(readFileSync(`${homedir()}/.env`, "utf8")).JEV_OPENROUTER_API_KEY)?.trim();
		if (!key) return undefined;

		const signals = [AbortSignal.timeout(JEV_TIMEOUT_MS)];
		if (ctx.signal) signals.push(ctx.signal);

		const response = await fetch(JEV_ENDPOINT, {
			method: "POST",
			headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
			body: JSON.stringify({
				model: JEV_MODEL,
				state: { command },
				questions: {
					read_only: {
						type: "noul",
						instructions: "Is this shell command still a read with no side effects?",
						criteria: {
							true: "The command only reads data and cannot change or export anything.",
							false: "The command writes, deletes, exports, or otherwise changes state.",
						},
					},
				},
			}),
			signal: AbortSignal.any(signals),
		});
		if (!response.ok) return undefined;
		return parseJevDecision(await response.json());
	} catch {
		return undefined;
	}
}

export default function (pi: ExtensionAPI) {
	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "bash") return undefined;
		const command = (event.input as { command?: unknown }).command;
		if (typeof command !== "string") return undefined;

		const decision = evaluate(command);
		if (decision === "allow") return undefined;

		if (decision === "block") {
			if (isJevEligible(command)) {
				const verdict = await consultJev(command, ctx);
				if (verdict === true) return undefined;
				if (verdict === false) {
					return { block: true, reason: "Blocked by Jev: not a read with no side effects" };
				}
			}
			const description = autoDenyPatterns.find((p) => matches(command, p))?.description ?? "command denied";
			return { block: true, reason: `Blocked: ${description}` };
		}

		if (!ctx.hasUI) {
			return { block: true, reason: "Dangerous command blocked (no UI for confirmation)" };
		}

		const choice = await ctx.ui.select(`⚠️ Dangerous command:\n\n  ${command}\n\nAllow?`, ["Yes", "No"]);
		if (choice !== "Yes") {
			return { block: true, reason: "Blocked by user" };
		}

		return undefined;
	});
}
