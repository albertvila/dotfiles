/**
 * Permission Gate Extension
 *
 * Adapted from xriu/dotfiles permission-gate.ts (originally migrated from
 * pi-guardrails permissionGate). Adds a Databricks allowlist/denylist pair
 * mirroring the AWS one.
 * Order: allowlist bypasses checks, then auto-deny blocks, then prompt patterns ask.
 * Matching: case-insensitive substring unless marked regex, against what the
 * command RUNS: heredoc bodies are cut first (text written to a file is not a
 * command) and a `git commit` message is cut too (a commit that documents a
 * destructive command is not running it). `bash -c "…"` keeps its text, because
 * there the quotes hold a command. Scripts the command runs are opened and
 * scanned by `codeHits` below, which is the other half of the same rule.
 *
 * shortcut: a mention inside a quoted argument of anything other than
 * `git commit` still matches (`npm test --grep "terraform destroy"`). Upgrade by
 * masking quoted spans for the deny class, but keep allow matching unmasked: the
 * allowlist reads the SQL inside its own quotes.
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
 *
 * Repo rules: `<cwd>/.claude/settings.json` `permissions.allow` / `.deny`
 * `Bash(...)` entries are honoured before Jev and before the allowlist. Deny
 * wins over allow. Destructive hard denials and prompt-class matches stay
 * unoverridable, so a repo file cannot unlock `rm -rf`, `sudo`, or `chmod 777`.
 * The file only counts when it is tracked by git and unmodified: the gate does
 * not cover the write tools, so an uncommitted file would let an agent write
 * itself an allow rule. Uncommitted, untracked, or non-repo means no rules.
 */

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { parseEnv } from "node:util";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

type Decision = "allow" | "block" | "prompt";
type Pattern = { pattern: string; regex?: boolean; flags?: string; description: string; enabled: boolean };

// Jev middle-band tuning. Threshold, timeout, and alias live here and nowhere else.
const JEV_PASS_AT = 0.9;
const JEV_TIMEOUT_MS = 1_500;
const JEV_MODEL = "typesafe/jev-1.13";
const JEV_ENDPOINT = "https://openrouter.ai/api/v1/systemone";
/** A guardrail block belongs to the key, not to the command, so one is enough for the process. */
let jevBlocked = false;

// Bypass all checks (no prompt).
const allowedPatterns: Pattern[] = [
	{
		pattern: "^(AWS_[A-Z_]+=\\S* +)*aws +[a-z0-9.-]+ +(list|get|describe|ls|filter)[a-z0-9.-]*( +[^;&|`$<>()\\n\\r]+)* *$",
		regex: true,
		description: "Read-only AWS ops (list/get/describe/ls/filter)",
		enabled: true,
	},
	{
		pattern: "^(DATABRICKS_[A-Z_]+=\\S* +)*databricks +[a-z0-9_.-]+ +(list|get|ls|cat|status|validate|logs)[a-z0-9.-]*( +[^;&|`$<>()\\n\\r]+)* *$",
		regex: true,
		description: "Read-only Databricks ops (list/get/ls/cat/status/validate/logs)",
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
	{
		// SQL-shape enforcement lives in the script (one read statement, no ';'), which is more
		// reliable than a regex. Ceiling: this rule can't see the statement — ~/bin/dbsql is the
		// only thing that may be allowlisted here, so keep it that way.
		pattern: "^(DATABRICKS_[A-Z_]+=\\S* +)*dbsql\\b[^;&|`$\\n\\r]*$",
		regex: true,
		description: "Read-only Databricks SQL via ~/bin/dbsql (single SELECT/WITH/SHOW/DESC/EXPLAIN)",
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
	{ pattern: "\\bgh\\s+(repo|gist|release)\\s+delete\\b", regex: true, description: "Deletes a GitHub repo, gist or release", enabled: true },
	// AGENTS.md § Ports, held here from 2026-11-07: 8765 is the attention
	// dashboard and killing it looks like a crash. The human restarts it; an
	// agent never has a reason to, so this one blocks rather than asks.
	{ pattern: "\\blsof\\b[^;&|]*\\b8765\\b", regex: true, description: "The attention dashboard's port 8765 (leave it running)", enabled: true },
	{ pattern: "\\b(kill|pkill|killall)\\b[^;&|\\n]*(8765|attention-dashboard)", regex: true, description: "Kills the attention dashboard (leave it running)", enabled: true },
];

const autoDenyPatterns: Pattern[] = [...catchAllDenyPatterns, ...destructiveDenyPatterns];

// Prompt for confirmation (not covered by the guardrails config).
const promptPatterns: Pattern[] = [
	{ pattern: "\\bsudo\\b", regex: true, flags: "i", description: "Privileged command (sudo)", enabled: true },
	{ pattern: "\\b(chmod|chown)\\b.*777", regex: true, flags: "i", description: "World-writable permission change", enabled: true },
	// AGENTS.md no longer asks for a confirmation on every commit (2026-11-14): the
	// rule cost a plain `git commit` a dialog that read as a misfire, and the commit
	// message and file list are in the transcript anyway.
	{ pattern: "\\bgit\\s+push\\b[^\\n;&|]*\\s(-f|--force|--force-with-lease)\\b", regex: true, description: "Force-push rewrites published history", enabled: true },
];

// Substring patterns are the destructive hard denials, matched case-insensitively
// so a case-shifted payload cannot slip past. Regex patterns use their own flags.
const matches = (command: string, p: Pattern) =>
	p.enabled && (p.regex ? new RegExp(p.pattern, p.flags).test(command) : command.toLowerCase().includes(p.pattern.toLowerCase()));

// A heredoc body: `<<EOF` … `EOF`, quoted or bare, with the tab-strip variant.
const HEREDOC = /<<-?\s*['"]?(\w+)['"]?[^\n]*\n[\s\S]*?\n\s*\1\s*(?:\n|$)/g;
// `bash -c "…"`, `sh -c`, `eval`: there the quotes hold the command itself.
const INTERPRETER_PAYLOAD = /(^|[;&|]\s*)(bash|sh|zsh)\s+-\w+\s+-c\b|\beval\b/;
// A `git commit` message: `-m <quoted or bare>`, repeated.
const COMMIT_MESSAGE = /(\bgit\s+commit\b[^\n]*?)(?:-m|--message)\s+(?:"(?:[^"\\]|\\.)*"|'[^']*'|\$'(?:[^'\\]|\\.)*'|\S+)/g;

/**
 * The text a rule matches: what the shell runs, not what the command text
 * mentions. A heredoc body is data written to a file, so it is cut. A
 * `git commit` message is data too — the commit that documents `rm -rf` is not
 * running it (2026-11-07: a docs commit was blocked, twice in one session).
 */
export function runs(command: string): string {
	const shell = command.replace(HEREDOC, "\n");
	if (INTERPRETER_PAYLOAD.test(shell)) return shell;
	return shell.replace(COMMIT_MESSAGE, (_, head) => `${head} -m …`);
}

/** Today's deterministic policy: allowlist, then hard deny, then prompt class. No Jev. */
export function evaluate(command: string): Decision {
	const text = runs(command);
	if (allowedPatterns.some((p) => matches(text, p))) return "allow";
	if (autoDenyPatterns.some((p) => matches(text, p))) return "block";
	if (promptPatterns.some((p) => matches(text, p))) return "prompt";
	return "allow";
}

// Scanned extensions, and the ways a command names a file it runs.
const SCANNED = /\.(?:py|mjs|cjs|js|ts|sh|bash)$/;
const RUNS_FILE = /\b(?:python3?|py|node|bun|deno\s+run|bash|sh|zsh|source)\s+(?:-[\w-]+\s+)*([^\s;&|<>]+\.(?:py|mjs|cjs|js|ts|sh|bash))/g;
const RUNS_PATH = /(?:^|[\s;&|])((?:\.{1,2}\/)?[^\s;&|='"]+\.(?:py|mjs|cjs|js|ts|sh|bash))/g;
// A call, not a mention: comment lines never run, so they are cut first.
const CODE_RULES: Array<[RegExp, string]> = [
	[/\bshutil\.rmtree\s*\(/, "a recursive delete in Python (shutil.rmtree)"],
	[/\b(DROP|TRUNCATE)\s+(TABLE|DATABASE|SCHEMA|CATALOG)\b/i, "SQL DROP/TRUNCATE"],
	[/\bDELETE\s+FROM\b/i, "SQL DELETE"],
	[/\baws\s+[a-z0-9.-]+\s+(rm|delete|put|create|terminate|modify|apply|update|start|stop|invoke|run)\b/i, "an AWS write"],
	[/\bdatabricks\s+[a-z0-9_.-]+\s+(delete|reset|repair|run-now|put|create|update|start|stop|restart|export|destroy)\b/i, "a Databricks write"],
];

/**
 * What the command runs, read from disk: the script's own lines, comments cut.
 * This is the half a command-text gate cannot see — `python3 reset.py` says
 * nothing about what reset.py does (2026-11-07). Unreadable files are skipped:
 * the guard never breaks an unrelated call.
 */
export function codeHits(command: string, cwd: string): string[] {
	// The same view as the rules use: a script named in a commit message or
	// written into a file is not a script this command runs.
	const shell = runs(command);
	const hits: string[] = [];
	const scan = (source: string) => {
		const code = source
			.split("\n")
			.map((line) => (line.trimStart().startsWith("#") ? "" : line))
			.join("\n");
		for (const [pattern, why] of CODE_RULES) if (pattern.test(code)) hits.push(why);
	};
	// Heredoc bodies fed to an interpreter are code that never touched a file.
	// The match starts at `<<`, so the interpreter sits in the text before it on
	// the same line: `python3 - <<'EOF'`. Feeding a heredoc through a pipe
	// (`cat <<'EOF' | python3`) is not seen, and is not a thing anyone writes.
	for (const m of command.matchAll(HEREDOC)) {
		const start = command.lastIndexOf("\n", m.index) + 1;
		const head = command.slice(start, m.index);
		const body = m[0].replace(/^[^\n]*\n/, "").replace(/\n\s*\w+\s*$/, "");
		if (/\b(python3?|py|node|bun|deno\s+run|bash|sh|zsh)\b/.test(head)) scan(body);
	}
	const paths = new Set<string>();
	for (const m of shell.matchAll(RUNS_FILE)) paths.add(m[1]);
	for (const m of shell.matchAll(RUNS_PATH)) if (SCANNED.test(m[1])) paths.add(m[1]);
	for (const path of paths) {
		const clean = path.replace(/"/g, "").replace(/^\/([a-zA-Z])\//, (_, d) => `${d.toUpperCase()}:/`);
		for (const base of ["", cwd]) {
			const full = base ? join(base, clean) : clean;
			if (!existsSync(full)) continue;
			try {
				scan(readFileSync(full, "utf8"));
			} catch {
				// Unreadable is not a hit; the gate fails open on a file it cannot read.
			}
			break;
		}
	}
	return [...new Set(hits)];
}

type RepoRules = { allow: string[]; deny: string[] };
const NO_RULES: RepoRules = { allow: [], deny: [] };

/**
 * `permissions.allow` / `permissions.deny` `Bash(...)` entries from a Claude
 * settings file. Anything unreadable or malformed means no rules at all.
 */
export function bashRules(settingsPath: string): RepoRules {
	let json: unknown;
	try {
		json = JSON.parse(readFileSync(settingsPath, "utf8"));
	} catch {
		return NO_RULES;
	}
	const permissions = (json as { permissions?: Record<string, unknown> })?.permissions ?? {};
	const read = (key: "allow" | "deny") => {
		const entries = Array.isArray(permissions[key]) ? (permissions[key] as unknown[]) : [];
		return entries.flatMap((entry) => {
			const inner = typeof entry === "string" ? /^Bash\((.*)\)$/.exec(entry.trim()) : null;
			// `cmd:*` is Claude's older prefix form; both forms mean "any suffix".
			return inner ? [inner[1].replace(/:?\*$/, "*")] : [];
		});
	};
	return { allow: read("allow"), deny: read("deny") };
}

/** Repo deny beats repo allow; no match means the gate's own policy decides. */export function repoDecision(command: string, rules: RepoRules): Decision | undefined {
	const trimmed = command.trim();
	const hit = (patterns: string[]) =>
		patterns.some((p) => new RegExp(`^${p.replace(/[.*+?^${}()|[\]\\]/g, "\\$&").replace(/\\\*/g, ".*")}$`).test(trimmed));
	if (hit(rules.deny)) return "block";
	if (hit(rules.allow)) return "allow";
	return undefined;
}

const SETTINGS = join(".claude", "settings.json");

/**
 * Rules for a checkout, read only from a committed, unmodified settings file.
 * A dirty or untracked file is ignored, so an agent cannot authorize itself.
 */
export function trackedRules(cwd: string): RepoRules {
	const path = join(cwd, SETTINGS);
	if (!existsSync(path)) return NO_RULES;
	const git = (...args: string[]) => spawnSync("git", ["-C", cwd, ...args], { stdio: "ignore", timeout: 1_000 }).status === 0;
	if (!git("ls-files", "--error-unmatch", "--", SETTINGS)) return NO_RULES;
	if (!git("diff", "--quiet", "HEAD", "--", SETTINGS)) return NO_RULES;
	return bashRules(path);
}

// A middle-band command needs a read-shaped token and no write or export token.
const READ_TOKENS = ["list", "get", "describe", "ls", "filter", "cat", "status", "validate", "logs", "select", "show", "desc", "explain", "tail", "head"];
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
		if (jevBlocked) return undefined;

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
		if (!response.ok) {
			if (/guardrail/i.test(await response.text().catch(() => ""))) jevBlocked = true;
			return undefined;
		}
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

		// Unoverridable gate rules first, so a repo settings file cannot unlock them.
		const text = runs(command);
		const unoverridable = destructiveDenyPatterns.some((p) => matches(text, p)) || promptPatterns.some((p) => matches(text, p));
		if (!unoverridable) {
			const repo = repoDecision(command, ctx.cwd ? trackedRules(ctx.cwd) : NO_RULES);
			if (repo === "block") return { block: true, reason: "Blocked: listed in .claude/settings.json deny" };
			if (repo === "allow") return undefined;
		}

		// What the command runs: a script's own writes are the command's writes.
		const scriptHits = codeHits(command, ctx.cwd ?? process.cwd());
		if (scriptHits.length > 0) {
			return { block: true, reason: `Blocked: ${scriptHits.join("; ")} in a script this command runs` };
		}

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
			const description = autoDenyPatterns.find((p) => matches(text, p))?.description ?? "command denied";
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
