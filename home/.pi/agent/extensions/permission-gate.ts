/**
 * Permission Gate Extension
 *
 * Adapted from xriu/dotfiles permission-gate.ts (originally migrated from
 * pi-guardrails permissionGate). Adds a Databricks allowlist/denylist pair
 * mirroring the AWS one.
 * Order: allowlist bypasses checks, then auto-deny blocks, then prompt patterns ask.
 * Matching: substring unless marked regex.
 *
 * Strict mode: any non-read-only `aws`/`databricks` command is blocked
 * outright, with no prompt-to-allow. Narrow the denylists if that gets in
 * the way. Chained commands (&&, ||, ;) never match an allowlist, so mixing
 * a read with a write fails closed.
 */

import { isToolCallEventType, type ExtensionAPI } from "@earendil-works/pi-coding-agent";

type Pattern = { pattern: string; regex?: boolean; flags?: string; description: string; enabled: boolean };

// Bypass all checks (no prompt).
const allowedPatterns: Pattern[] = [
	{
		pattern: "^(AWS_[A-Z_]+=\\S* +)*aws +[a-z0-9.-]+ +(list|get|describe|ls)[a-z0-9.-]*( +[^;&|`$<>()\\n\\r]+)* *$",
		regex: true,
		description: "Read-only AWS ops (list/get/describe/ls)",
		enabled: true,
	},
	{
		pattern: "^(DATABRICKS_[A-Z_]+=\\S* +)*databricks +[a-z0-9_.-]+ +(list|get|ls|cat|status|validate)\\b( +[^;&|`$<>()\\n\\r]+)* *$",
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

// Always blocked without prompting.
const autoDenyPatterns: Pattern[] = [
	{ pattern: "(^|&&|\\|\\||;) *(AWS_[A-Z_]+=\\S* +)*aws\\b", regex: true, description: "AWS outside read-only allowlist", enabled: true },
	{ pattern: "(^|&&|\\|\\||;) *(DATABRICKS_[A-Z_]+=\\S* +)*databricks\\b", regex: true, description: "Databricks outside read-only allowlist", enabled: true },
	{ pattern: "rm -rf", description: "Recursive force delete", enabled: true },
	{ pattern: "diskutil", description: "Disk utility operation", enabled: true },
	{ pattern: "git reset --hard", description: "Discards uncommitted changes", enabled: true },
	{ pattern: "mkfs", description: "Filesystem format", enabled: true },
	{ pattern: "npm publish", description: "Publishes npm package", enabled: true },
	{ pattern: "terraform apply", description: "Applies infra changes", enabled: true },
	{ pattern: "terraform destroy", description: "Destroys infra", enabled: true },
];

// Prompt for confirmation (not covered by the guardrails config).
const promptPatterns: Pattern[] = [
	{ pattern: "\\bsudo\\b", regex: true, description: "Privileged command (sudo)", enabled: true },
	{ pattern: "\\b(chmod|chown)\\b.*777", regex: true, description: "World-writable permission change", enabled: true },
];

const matches = (command: string, p: Pattern) =>
	p.enabled && (p.regex ? new RegExp(p.pattern, p.flags).test(command) : command.includes(p.pattern));

export default function (pi: ExtensionAPI) {
	pi.on("tool_call", async (event, ctx) => {
		if (!isToolCallEventType("bash", event)) return undefined;

		const command = event.input.command;

		if (allowedPatterns.some((p) => matches(command, p))) return undefined;

		const denied = autoDenyPatterns.find((p) => matches(command, p));
		if (denied) {
			return { block: true, reason: `Blocked: ${denied.description}` };
		}

		if (promptPatterns.some((p) => matches(command, p))) {
			if (!ctx.hasUI) {
				return { block: true, reason: "Dangerous command blocked (no UI for confirmation)" };
			}

			const choice = await ctx.ui.select(`⚠️ Dangerous command:\n\n  ${command}\n\nAllow?`, ["Yes", "No"]);
			if (choice !== "Yes") {
				return { block: true, reason: "Blocked by user" };
			}
		}

		return undefined;
	});
}
