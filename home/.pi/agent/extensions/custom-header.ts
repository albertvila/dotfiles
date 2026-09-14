/**
 * Custom Header Extension
 *
 * Knob in ~/.pi/agent/settings.json → "customHeader": { "skillsMode" }
 * - skillsMode: render our own resource listing as the header: [Context],
 *   [Skills: automatic] (model-invocable), [Skills: manual] (/skill:name
 *   only), [Prompts], [Extensions]. Empty data renders a blank header.
 *
 * Designed to run with pi's native "quietStartup": true, which suppresses
 * the "Model scope:" line (printed before extensions load) and pi's own
 * listing — which this header replaces.
 *
 * ponytail: extension/prompt lists are re-derived from settings.json and a
 * dir scan; names can drift from pi's own listing (extension subpaths, and
 * skills from git: packages are not included — npm: packages are).
 */

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI, Skill } from "@earendil-works/pi-coding-agent";
import { loadProjectContextFiles, loadSkills } from "@earendil-works/pi-coding-agent";

const AGENT_DIR = join(homedir(), ".pi", "agent");
const SETTINGS_PATH = join(AGENT_DIR, "settings.json");
const NPM_MODULES_DIR = join(AGENT_DIR, "npm", "node_modules");

export type SkillGroups = { automatic: string[]; manual: string[] };
type ListingData = { contextNames: string[]; groups: SkillGroups; prompts: string[]; extensions: string[] };
type Fg = (color: "mdHeading" | "dim", text: string) => string;

function readSettings(): Record<string, unknown> {
	try {
		return JSON.parse(readFileSync(SETTINGS_PATH, "utf8"));
	} catch {
		return {};
	}
}

/** Split skills by invocation mode: automatic (model-invocable) vs manual (/skill:name only). */
export function splitSkills(skills: Skill[]): SkillGroups {
	const automatic: string[] = [];
	const manual: string[] = [];
	for (const skill of skills) (skill.disableModelInvocation ? manual : automatic).push(skill.name);
	automatic.sort();
	manual.sort();
	return { automatic, manual };
}

/** One listing section: bold label + dim comma list, or nothing when empty. */
function section(fg: Fg, label: string, names: string[]): string[] {
	return names.length ? [fg("mdHeading", label), fg("dim", `  ${names.join(", ")}`)] : [];
}

/** Prompt template names: /name from .md files in the global and project prompt dirs. */
function listPrompts(): string[] {
	const names = [join(AGENT_DIR, "prompts"), join(process.cwd(), ".pi", "prompts")].flatMap((dir) =>
		safeReaddir(dir).filter((f) => f.endsWith(".md")).map((f) => `/${f.replace(/\.md$/, "")}`),
	);
	return names.sort();
}

function safeReaddir(dir: string): string[] {
	return existsSync(dir) ? readdirSync(dir) : [];
}

/** Raw package sources from settings (string or {source} entries). */
function packageSources(settings: Record<string, unknown>): string[] {
	return ((settings.packages as (string | { source?: string })[] | undefined) ?? [])
		.map((pkg) => (typeof pkg === "string" ? pkg : pkg.source))
		.filter((source): source is string => !!source);
}

/** Extension labels: configured extension dirs (file names) + package sources. */
function listExtensions(settings: Record<string, unknown>): string[] {
	const dirs = (settings.extensions as string[] | undefined) ?? [];
	const files = dirs.flatMap((dir) => safeReaddir(dir.replace(/^~/, homedir())).filter((f) => f.endsWith(".ts")));
	const packages = packageSources(settings).map((source) => source.replace(/^(npm|git):/, "").replace(/^github\.com\//, ""));
	return [...files, ...packages].sort();
}

/** Gather listing data (no theming — that happens in the header factory). */
function gatherListingData(settings: Record<string, unknown>): ListingData {
	const cwd = process.cwd();
	// pi discovers package-contributed skills via its package manager, not loadSkills — add their dirs explicitly.
	const skillPaths = [
		join(homedir(), ".agents", "skills"),
		join(cwd, ".agents", "skills"),
		...packageSources(settings)
			.filter((source) => source.startsWith("npm:"))
			.map((source) => join(NPM_MODULES_DIR, source.replace(/^npm:/, ""), "skills"))
			.filter(existsSync),
	];
	const groups = splitSkills(loadSkills({ cwd, agentDir: AGENT_DIR, skillPaths, includeDefaults: true }).skills);
	return {
		groups,
		contextNames: loadProjectContextFiles({ cwd, agentDir: AGENT_DIR }).map((f) => f.path.replace(homedir(), "~")),
		prompts: listPrompts(),
		extensions: listExtensions(settings),
	};
}

/** Format the listing with the live theme: sections separated by one blank line. */
export function renderListing(data: ListingData, fg: Fg): string {
	return [
		section(fg, "[Context]", data.contextNames),
		section(fg, "[Skills: automatic]", data.groups.automatic),
		section(fg, "[Skills: manual]", data.groups.manual),
		section(fg, "[Prompts]", data.prompts),
		section(fg, "[Extensions]", data.extensions),
	]
		.filter((b) => b.length)
		.map((b) => b.join("\n"))
		.join("\n\n");
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", async (_event, ctx) => {
		if (ctx.mode !== "tui") return;
		const settings = readSettings();
		if ((settings.customHeader as { skillsMode?: boolean } | undefined)?.skillsMode !== true) return;

		const { Text } = await import("@earendil-works/pi-tui");

		try {
			const data = gatherListingData(settings);
			ctx.ui.setHeader((_tui, theme) => new Text("\n" + renderListing(data, (c, t) => theme.fg(c, t)), 0, 0) as never);
		} catch {
			// Discovery failed: no listing.
		}
	});
}
