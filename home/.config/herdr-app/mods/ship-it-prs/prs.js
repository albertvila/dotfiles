// The PRs panel's logic, apart from its drawing: what a PR's checks say, and
// its worktree (find, create, the space showing it). The tests import this
// file (test/prs.test.mjs) with a stand-in for "herdr".
//
// data.js is a copy: edit mods/ship-it/data.js and run scripts/install.sh.

import { exec, run, spaces, panes } from "herdr";
import { READ, tilde } from "./data.js";

// One word for a PR's checks: "fail", "pending", "pass" or null (none).
export function checkState(rollup) {
  let pending = false;
  for (const c of rollup ?? []) {
    const v = (c.conclusion || c.state || "").toUpperCase(), done = c.status ? c.status === "COMPLETED" : !["PENDING", "EXPECTED"].includes(v);
    if (!done) { pending = true; continue; }
    if (["FAILURE", "ERROR", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE"].includes(v)) return "fail";
  }
  return rollup?.length ? (pending ? "pending" : "pass") : null;
}
// How many checks passed, failed and still run.
export function checkCounts(rollup) {
  const n = { pass: 0, fail: 0, pending: 0 };
  for (const c of rollup ?? []) n[checkState([c]) ?? "pass"]++;
  return n;
}
// ---- worktrees: a PR's branch checked out beside the repo, as a space

// The branch a PR is checked out on here: its own, or pr-<n> for a fork's.
export const localBranch = (pr) => (pr.isCrossRepository ? `pr-${pr.number}` : pr.headRefName);
// Where Herdr's worktree mod puts checkouts, so the space nests under the repo's.
export const slug = (branch) => branch.replace(/[^A-Za-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "");

// The repo's checkouts by branch: { branch: path }.
export async function worktrees(root, on) {
  const r = await exec("git", [...READ, "worktree", "list", "--porcelain"], { cwd: root, on });
  const out = {};
  for (const block of (r.code === 0 ? r.stdout : "").split("\n\n")) {
    const path = /^worktree (.+)$/m.exec(block)?.[1], branch = /^branch refs\/heads\/(.+)$/m.exec(block)?.[1];
    if (path && branch) out[branch] = path;
  }
  return out;
}

// Fetch the PR's head from origin and check it out in a new worktree:
// its branch, tracking origin's (a local branch of that name is used as it
// is), or for a fork's PR pull/<n>/head on pr-<n>. Returns the path.
export async function addWorktree(root, on, pr) {
  const git = async (args, what) => {
    const r = await exec("git", args, { cwd: root, on });
    if (r.code !== 0) throw new Error((r.stderr || `${what} failed`).trim().split("\n").pop());
    return r.stdout.trim();
  };
  const branch = localBranch(pr);
  const common = await git(["rev-parse", "--path-format=absolute", "--git-common-dir"], "git rev-parse");
  const main = common.endsWith("/.git") ? common.slice(0, -5) : common;
  const home = (await exec("sh", ["-c", 'printf %s "$HOME"'], { on })).stdout.trim();
  if (!home) throw new Error("Couldn't find the home folder");
  const path = `${home}/.herdr/worktrees/${main.split("/").pop()}/${slug(branch)}`;
  const local = (await exec("git", [...READ, "show-ref", "--verify", "--quiet", `refs/heads/${branch}`], { cwd: root, on })).code === 0;
  if (pr.isCrossRepository) {
    await git(["fetch", "origin", `pull/${pr.number}/head`], "git fetch");
    await git(local ? ["worktree", "add", path, branch] : ["worktree", "add", "-b", branch, path, "FETCH_HEAD"], "git worktree add");
  } else {
    await git(["fetch", "origin", `+refs/heads/${branch}:refs/remotes/origin/${branch}`], "git fetch");
    await git(local ? ["worktree", "add", path, branch] : ["worktree", "add", "--track", "-b", branch, path, `origin/${branch}`], "git worktree add");
  }
  return path;
}

// Where each space on the machine is: its first terminal's folder, else the
// one it was made in. Read once per render: panes() copies every pane.
export function places(on) {
  const ps = panes();
  return spaces().filter((s) => (s.machine ?? null) === (on ?? null)).map((s) => {
    const tabs = new Set((s.tabs ?? []).map((t) => t.id));
    return { s, at: ps.find((p) => tabs.has(p.tab) && p.cwd)?.cwd || s.folder || null };
  });
}

// The space showing a checkout, if one does. A space in a deeper checkout
// (.worktrees/x inside the repo's own) is that checkout's, not this one's.
export function spaceAt(path, where, paths = []) {
  if (!path) return undefined;
  const inside = (p, dir) => p === dir || p?.startsWith(dir + "/");
  return where.find(({ at }) => inside(at, path) && !paths.some((c) => c.length > path.length && inside(at, c)))?.s;
}

// Show the space on that checkout, or make one (unnamed: it is called after
// the checkout and nests under the repo's space).
export function showSpace(path, on, paths) {
  const s = spaceAt(path, places(on), paths);
  if (s) run("space.select", { id: s.id });
  else run("space.new", { folder: path, ...(on ? { machine: on } : {}) });
}

// What a PR's worktree button does: go to its space, open its checkout as a
// space, or create the checkout.
export function treeLook(path, space) {
  if (space) return { icon: "git-branch", label: "Go to space", tip: `Go to the space on ${tilde(path)}`, color: "accent" };
  if (path) return { icon: "folder", label: "Open worktree", tip: `Open ${tilde(path)} as a space`, color: "accent" };
  return { icon: "git-branch-plus", label: "Create worktree", tip: "Check it out in a new worktree and open it as a space", color: "dim" };
}
