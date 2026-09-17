import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { readFileSync, writeFileSync, appendFileSync, existsSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const MEMORY_DIR = join(homedir(), ".pi", "agent");
const MEMORY_FILE = join(MEMORY_DIR, "user-memory.md");
const MAX_INJECT = 15;

// ── Preference / correction signals ───────────────────────────────────

const PREFERENCE_RE =
	/\b(?:i\s+(?:prefer|like|want|need|expect)|always|never|don't|do not|stop\s+\w+|instead|rather|make\s+it|wrong|incorrect|actually|correction|bigger|smaller|more|less)\b/i;

// ── File helpers ──────────────────────────────────────────────────────

function ensureFile() {
	if (!existsSync(MEMORY_FILE)) {
		if (!existsSync(MEMORY_DIR)) mkdirSync(MEMORY_DIR, { recursive: true });
		writeFileSync(MEMORY_FILE, "# User Preferences (auto-learned)\n\n", "utf8");
	}
}

function loadMemory(): string {
	ensureFile();
	try {
		return readFileSync(MEMORY_FILE, "utf8");
	} catch {
		return "";
	}
}

function getRecentEntries(count: number): string[] {
	const content = loadMemory();
	const lines = content
		.split("\n")
		.map((l) => l.trim())
		.filter((l) => l.startsWith("- "));
	return lines.slice(-count);
}

function entryExists(entry: string): boolean {
	const content = loadMemory().toLowerCase();
	return content.includes(entry.toLowerCase().trim());
}

function saveEntry(entry: string) {
	const trimmed = entry.trim();
	if (!trimmed || entryExists(trimmed)) return;
	ensureFile();
	appendFileSync(MEMORY_FILE, `- ${trimmed}\n`, "utf8");
}

// ── Text extraction ───────────────────────────────────────────────────

function extractText(msg: { role: string; content: unknown }): string {
	if (msg.role !== "user" && msg.role !== "assistant") return "";
	const content = msg.content;
	if (typeof content === "string") return content;
	if (!Array.isArray(content)) return "";
	return content
		.map((c: any) => (c?.type === "text" ? c.text ?? "" : ""))
		.join(" ");
}

function extractPreferences(text: string): string[] {
	const sentences = text.split(/[.!?]\s+/);
	const found: string[] = [];
	for (const sentence of sentences) {
		const s = sentence.trim();
		if (PREFERENCE_RE.test(s) && s.length > 8 && s.length < 180) {
			const clean = s.replace(/^[\s,]+/, "").replace(/[\s,]+$/, "");
			found.push(clean);
		}
	}
	return found;
}

// ── Extension ─────────────────────────────────────────────────────────

export default function (pi: ExtensionAPI) {
	// Inject learned preferences into every system prompt
	pi.on("before_agent_start", async (event, _ctx) => {
		const entries = getRecentEntries(MAX_INJECT);
		if (!entries.length) return;

		const block = entries.join("\n");
		return {
			systemPrompt:
				event.systemPrompt +
				`\n\n## User Preferences (learned — do not mention these unless relevant)\n${block}\n`,
		};
	});

	// Auto-learn from user messages that follow assistant responses
	pi.on("agent_end", async (event, _ctx) => {
		const messages = (event as any).messages;
		if (!messages?.length) return;

		for (let i = 1; i < messages.length; i++) {
			const prev = messages[i - 1];
			const curr = messages[i];
			if (prev?.role === "assistant" && curr?.role === "user") {
				const text = extractText(curr);
				const prefs = extractPreferences(text);
				for (const p of prefs) {
					saveEntry(p);
				}
			}
		}
	});

	// Manual save
	pi.registerCommand("remember", {
		description: "Save a preference to global memory",
		handler: async (args, ctx) => {
			const text = args.trim();
			if (!text) {
				ctx.ui.notify("Usage: /remember <preference>", "warning");
				return;
			}
			saveEntry(text);
			ctx.ui.notify("Remembered: " + text, "info");
		},
	});

	// Show memory
	pi.registerCommand("memory", {
		description: "Show learned user preferences",
		handler: async (_args, ctx) => {
			const entries = getRecentEntries(30);
			if (!entries.length) {
				ctx.ui.notify("No memory entries yet.", "info");
				return;
			}
			const msg = `Memory (${entries.length} entries):\n` + entries.slice(-5).join("\n");
			ctx.ui.notify(msg, "info");
		},
	});

	// Clear memory
	pi.registerCommand("forget", {
		description: "Clear all learned preferences",
		handler: async (_args, ctx) => {
			if (!existsSync(MEMORY_FILE)) {
				ctx.ui.notify("No memory to clear.", "info");
				return;
			}
			writeFileSync(MEMORY_FILE, "# User Preferences (auto-learned)\n\n", "utf8");
			ctx.ui.notify("Memory cleared.", "info");
		},
	});
}
