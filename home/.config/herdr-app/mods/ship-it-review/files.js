// What the branch changes: the working tree against the merge base of HEAD and
// its base, so the review shows what the PR will hold after the next push.

import { exec, readTextFile } from "herdr";
import { READ } from "./data.js";

export const MAX_FILES = 1000;
export const MAX_LINES = 1500;

const git = (args, root, on) => exec("git", [...READ, ...args], { cwd: root, on });
const split0 = (text) => (text || "").split("\0");

// [{ path, status, add, del, binary, fresh, dirty, key }] plus the merge base.
// `key` names both sides of the file's diff (base blob, current blob): when
// either changes, so does the diff, and a "viewed" mark made against it clears.
export async function branchFiles(root, on, base) {
  const mb = (await git(["merge-base", base, "HEAD"], root, on)).stdout.trim();
  if (!mb) return { mb: null, files: [], limited: false };
  const [num, raw, status, untracked] = await Promise.all([
    git(["diff", mb, "--numstat", "-z", "--no-renames"], root, on),
    git(["diff", mb, "--raw", "-z", "--no-renames", "--abbrev=40"], root, on),
    git(["status", "--porcelain=v1", "-z", "--no-renames", "--untracked-files=all"], root, on),
    git(["ls-files", "--others", "--exclude-standard", "-z"], root, on),
  ]);
  if (num.code !== 0) throw new Error(num.stderr.trim() || "git diff failed");

  const stats = {};
  for (const entry of split0(num.stdout)) {
    const [a, d, ...parts] = entry.split("\t");
    if (!parts.length) continue;
    stats[parts.join("\t")] = { add: Number(a) || 0, del: Number(d) || 0, binary: a === "-" };
  }
  // ":100644 100644 <old> <new> M\0path\0"
  const rawParts = split0(raw.stdout), meta = {};
  for (let i = 0; i + 1 < rawParts.length; i += 2) {
    const [, , old, , s] = rawParts[i].split(" ");
    if (s) meta[rawParts[i + 1]] = { old, status: s[0] };
  }
  const dirty = new Set();
  for (const entry of split0(status.stdout)) if (entry.length > 3) dirty.add(entry.slice(3));

  const files = Object.keys(meta).map((path) => {
    const m = meta[path], st = stats[path] ?? { add: 0, del: 0, binary: false };
    const s = m.status === "A" ? "A" : m.status === "D" ? "D" : m.status === "U" ? "U" : "M";
    return { path, status: s, ...st, fresh: false, dirty: dirty.has(path), old: m.old };
  });
  for (const path of split0(untracked.stdout).filter(Boolean)) {
    if (!meta[path]) files.push({ path, status: "A", add: 0, del: 0, binary: false, fresh: true, dirty: true, old: "" });
  }
  files.sort((a, b) => a.path.localeCompare(b.path));
  const limited = files.length > MAX_FILES;
  const shown = files.slice(0, MAX_FILES);

  // The current side, hashed as git would store it (nothing is written).
  const present = shown.filter((f) => f.status !== "D");
  const hashed = present.length ? await git(["hash-object", "--", ...present.map((f) => f.path)], root, on) : null;
  const shas = hashed?.code === 0 ? hashed.stdout.trim().split("\n") : [];
  present.forEach((f, i) => { f.now = shas[i] ?? `${f.add}+${f.del}`; });
  for (const f of shown) {
    f.key = `${f.old}:${f.status === "D" ? "gone" : f.now}`;
    delete f.old; delete f.now;
  }
  // Untracked files have no numstat: count their lines in one grep, so no file's
  // text comes into the script (-I leaves binary files out; -H names every file).
  const fresh = shown.filter((f) => f.fresh).slice(0, 200);
  if (fresh.length) {
    const r = await exec("grep", ["-IcH", "", "--", ...fresh.map((f) => f.path)], { cwd: root, on }).catch(() => null);
    const counts = {};
    for (const line of (r?.stdout ?? "").split("\n")) {
      const i = line.lastIndexOf(":");
      if (i > 0) counts[line.slice(0, i)] = Number(line.slice(i + 1)) || 0;
    }
    for (const f of fresh) { f.add = counts[f.path] ?? 0; f.binary = r?.code <= 1 && !(f.path in counts); }
  }
  return { mb, files: shown, limited };
}

// Numbers each diff line on both sides, so review threads find their rows
// (RIGHT side → new number, LEFT → old) and a frame draws only what's on screen.
export function diffRows(lines) {
  let old = 0, next = 0;
  return lines.map((line) => {
    const m = /^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@(.*)$/.exec(line);
    if (m) { old = +m[1]; next = +m[2]; return { kind: "@", text: line }; }
    const kind = line[0], text = (line.slice(1) || " ").replace(/\t/g, "    ");
    if (kind === "-") return { kind, old: old++, text };
    if (kind === "+") return { kind, new: next++, text };
    if (kind === " ") return { kind, old: old++, new: next++, text };
    return { kind: "", text: line };
  });
}

// The diff lines for one file, capped.
export async function fileDiff(root, on, mb, file) {
  let lines;
  if (file.fresh) {
    const text = await readTextFile(`${root}/${file.path}`, { on }).catch(() => null);
    if (text === null) lines = ["Cannot preview this file (binary, too large, or unreadable)"];
    else if (text.includes("\0")) lines = ["Binary file added"];
    else {
      const body = text.slice(0, 400000).replace(/\n$/, "").split("\n");
      lines = [`@@ -0,0 +1,${body.length} @@`, ...body.map((l) => `+${l}`)];
    }
  } else {
    const r = await git(["diff", mb, "--no-ext-diff", "--no-textconv", "--no-color", "--", file.path], root, on);
    if (r.code !== 0) throw new Error(r.stderr.trim());
    const all = r.stdout.replace(/\n$/, "").split("\n"), first = all.findIndex((l) => l.startsWith("@@"));
    lines = first < 0 ? [file.binary ? "Binary file changed" : "No text changes"] : all.slice(first);
  }
  const cut = lines.length > MAX_LINES;
  return { lines: lines.slice(0, MAX_LINES).map((l) => (l.length > 4000 ? l.slice(0, 4000) + "…" : l)), cut };
}

// The tail of a failed job's log, without gh's "job<TAB>step<TAB>" prefix,
// timestamps or colour codes (raw, or spelled ^[[ when gh isn't on a terminal).
export function logTail(text, count = 200) {
  const lines = (text || "").replace(/\r/g, "").split("\n").map((line) => {
    const parts = line.split("\t");
    const body = parts.length >= 3 ? parts.slice(2).join("\t") : line;
    return body.replace(/(?:\x1b|\^\[)\[[0-9;]*[A-Za-z]/g, "").replace(/^\uFEFF?\d{4}-\d\d-\d\dT[\d:.]+Z ?/, "");
  });
  while (lines.length && !lines[lines.length - 1].trim()) lines.pop();
  return lines.slice(-count);
}
