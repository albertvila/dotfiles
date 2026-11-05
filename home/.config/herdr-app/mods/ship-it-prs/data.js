// Facts about where the work is: git (local or on the space's machine) and
// its GitHub pull request (through the person's own `gh`).
//
// mods/ship-it-review/data.js is a copy (a mod can't import from another
// mod's folder): edit this one and run scripts/install.sh.

import { exec, spaces, panes, focused, home, layout, shared } from "herdr";

// Reads write nothing under .git (no index refresh or lock, no fsmonitor cookie):
// a folder watch would see it, and every refresh would start the next one.
export const READ = ["--no-optional-locks", "-c", "core.fsmonitor=false", "-c", "diff.autoRefreshIndex=false"];

export const tilde = (path) => {
  const h = home();
  return !path ? "" : path === h ? "~" : path.startsWith(h + "/") ? "~" + path.slice(h.length) : path;
};

// The focused pane's live folder and the machine it is on. A mod pane has no
// folder, so the last terminal's stays (`last`).
export function location(last) {
  const space = spaces().find((s) => s.active), f = focused();
  const pane = f?.pane ? panes().find((p) => p.pane === f.pane) : null;
  if (pane && !pane.terminal && last && last.space === space?.id) return last;
  const on = f?.pane === null ? (f.terminal?.includes("/") ? f.terminal.split("/")[0] : null) : space?.machine ?? null;
  // A mod pane focused first in this space: the tab's first terminal, not the space's starting folder.
  const sibling = pane && !pane.terminal ? panes().find((p) => p.tab === pane.tab && p.terminal && p.cwd) : null;
  return { cwd: pane?.cwd || sibling?.cwd || f?.cwd || space?.folder || null, on, space: space?.id ?? null };
}

// ---- caches
//
// The last facts for each repo or branch, newest kept: going back to a
// worktree shows them at once while a refresh runs.

export class Recent {
  constructor(size = 24) { this.size = size; this.map = new Map(); }
  get(key) {
    const v = this.map.get(key);
    if (v !== undefined) { this.map.delete(key); this.map.set(key, v); }
    return v;
  }
  set(key, value) {
    this.map.delete(key); this.map.set(key, value);
    if (this.map.size > this.size) this.map.delete(this.map.keys().next().value);
  }
}

// The strip's pull request for the repo it shows, so the review needs no gh
// calls of its own: { root, on, branch, at, kind, pr, checks, threads }.
export function sharedPr(root, on) {
  const s = shared("ship-it.pr");
  return s && s.root === root && (s.on ?? null) === (on ?? null) ? s : null;
}

// ---- what is on screen, so hidden copies do no work
//
// A mod pane doesn't know its own pane id, so "shown" means a pane of that mod
// is in the tab on screen. Panels are shown when the panel is open on them.

export function shownTab() {
  const space = spaces().find((s) => s.active);
  return space?.tabs?.find((t) => t.active)?.id ?? null;
}

export function modShown(mod) {
  const tab = shownTab();
  return panes().some((p) => p.mod === mod && p.tab === tab);
}

function findNode(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) { const found = findNode(child, id); if (found) return found; }
  return null;
}

export function panelShown(id) {
  const root = layout(), panel = findNode(root, "panel"), body = findNode(root, "panel-body");
  return Boolean(panel && !panel.hidden && body?.active === id);
}

const git = (args, cwd, on) => exec("git", [...READ, ...args], { cwd, on });
const out = (r) => (r.code === 0 ? r.stdout.trim() : "");

// { root, sub, branch, sha, detached, upstream, ahead, behind, dirty, worktree }
// or null outside a repo.
export async function gitFacts(cwd, on) {
  const top = await git(["rev-parse", "--show-toplevel", "--git-dir", "--git-common-dir", "--short", "HEAD"], cwd, on);
  if (top.code !== 0 && !top.stdout) return null;
  const [root, gitDir, commonDir, sha] = top.stdout.trim().split("\n");
  if (!root) return null;
  const abs = (p) => (p?.startsWith("/") ? p : `${root}/${p}`);
  const [branch, counts, status] = await Promise.all([
    git(["branch", "--show-current"], root, on),
    git(["rev-list", "--left-right", "--count", "@{upstream}...HEAD"], root, on),
    git(["status", "--porcelain=v1", "-z", "--untracked-files=all"], root, on),
  ]);
  const [behind, ahead] = out(counts).split(/\s+/).map(Number);
  return {
    root, on,
    sub: cwd && cwd !== root && cwd.startsWith(root + "/") ? cwd.slice(root.length) : "",
    branch: out(branch) || null,
    sha: sha && !sha.startsWith("fatal") ? sha : null,
    detached: !out(branch),
    upstream: counts.code === 0,
    ahead: ahead || 0, behind: behind || 0,
    dirty: status.code === 0 ? status.stdout.split("\0").filter(Boolean).length : 0,
    worktree: Boolean(gitDir && commonDir && abs(gitDir) !== abs(commonDir)),
    // The repo's name: its main checkout's folder, also from a worktree.
    repo: (commonDir ? abs(commonDir).replace(/\/\.git\/?$/, "") : root).split("/").pop(),
  };
}

const PR_FIELDS = "number,title,state,isDraft,url,baseRefName,headRefName,headRefOid,reviewDecision,author,additions,deletions,changedFiles,mergeable,mergeStateStatus,createdAt,updatedAt,labels,reviewRequests";
export const PR_DETAIL = PR_FIELDS + ",body,comments,reviews";

// { kind: "ok", pr } | { kind: "none" } | { kind: "unavailable", reason }
export async function prFacts(root, on, fields = PR_FIELDS) {
  let r;
  try { r = await exec("gh", ["pr", "view", "--json", fields], { cwd: root, on }); }
  catch { return { kind: "unavailable", reason: "gh is not installed" }; }
  if (r.code === 0) {
    try { return { kind: "ok", pr: JSON.parse(r.stdout) }; } catch { return { kind: "unavailable", reason: "gh gave no JSON" }; }
  }
  const err = (r.stderr || "").toLowerCase();
  if (err.includes("no git remote")) return { kind: "none", remote: false };
  if (err.includes("no pull requests found") || err.includes("no default remote") || err.includes("not on any branch")) return { kind: "none" };
  if (err.includes("auth") || err.includes("gh auth login")) return { kind: "unavailable", reason: "gh is not logged in" };
  return { kind: "unavailable", reason: (r.stderr || "gh failed").trim().split("\n")[0] };
}

// Every check on the PR's head: [{ name, workflow, bucket, state, link, startedAt, completedAt, description, run, job }].
// gh exits 8 while checks are pending and 1 when one fails; the JSON is still there.
export async function checks(root, on) {
  let r;
  try { r = await exec("gh", ["pr", "checks", "--json", "name,workflow,bucket,state,link,startedAt,completedAt,description,event"], { cwd: root, on }); }
  catch { return null; }
  try {
    return JSON.parse(r.stdout || "[]").map((c) => {
      const m = /\/actions\/runs\/(\d+)(?:\/job\/(\d+))?/.exec(c.link || "");
      return { ...c, run: m?.[1] ?? null, job: m?.[2] ?? null };
    });
  } catch { return []; }
}

export function tally(list) {
  const t = { pass: 0, fail: 0, pending: 0, skipping: 0, cancel: 0 };
  for (const c of list ?? []) t[c.bucket] = (t[c.bucket] ?? 0) + 1;
  return t;
}

// The ref the branch is compared with: the PR's base, else origin/HEAD, else main, else master.
export async function baseRef(root, on, pr) {
  const candidates = [];
  if (pr?.baseRefName) candidates.push(`origin/${pr.baseRefName}`, pr.baseRefName);
  const head = out(await git(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], root, on));
  if (head) candidates.push(head);
  candidates.push("origin/main", "main", "origin/master", "master");
  for (const ref of candidates) {
    const r = await git(["rev-parse", "--verify", "--quiet", `${ref}^{commit}`], root, on);
    if (r.code === 0) return ref;
  }
  return null;
}

// Review threads on the PR, through GraphQL (only it knows resolved/outdated):
// [{ id, path, line, originalLine, side, resolved, outdated, comments: [{ id, author, body, createdAt, url }] }]
const THREADS = `query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){
  reviewThreads(first:100){nodes{id isResolved isOutdated path line originalLine diffSide
    comments(first:50){nodes{id author{login} body createdAt url}}}}}}}`;

export function repoOf(url) {
  const m = /github\.com\/([^/]+)\/([^/]+)\/pull\/(\d+)/.exec(url || "");
  return m ? { owner: m[1], name: m[2], number: Number(m[3]) } : null;
}

export async function threads(root, on, pr) {
  const repo = repoOf(pr?.url);
  if (!repo) return [];
  const r = await exec("gh", ["api", "graphql", "-f", `query=${THREADS}`, "-F", `owner=${repo.owner}`, "-F", `name=${repo.name}`, "-F", `number=${repo.number}`], { cwd: root, on });
  if (r.code !== 0) return [];
  try {
    const nodes = JSON.parse(r.stdout).data.repository.pullRequest.reviewThreads.nodes;
    return nodes.map((n) => ({
      id: n.id, path: n.path, line: n.line, originalLine: n.originalLine, side: n.diffSide,
      resolved: n.isResolved, outdated: n.isOutdated,
      comments: n.comments.nodes.map((c) => ({ id: c.id, author: c.author?.login ?? "ghost", body: c.body, createdAt: c.createdAt, url: c.url })),
    }));
  } catch { return []; }
}

export const gql = (root, on, query, vars) =>
  exec("gh", ["api", "graphql", "-f", `query=${query}`, ...Object.entries(vars).flatMap(([k, v]) => ["-f", `${k}=${v}`])], { cwd: root, on });

// "3m", "5h", "2d", "4mo" since an ISO time.
export function ago(iso) {
  const s = (Date.now() - Date.parse(iso)) / 1000;
  if (!isFinite(s)) return "";
  return s < 60 ? "now" : s < 3600 ? `${Math.round(s / 60)}m` : s < 86400 ? `${Math.round(s / 3600)}h` : s < 86400 * 60 ? `${Math.round(s / 86400)}d` : `${Math.round(s / 86400 / 30)}mo`;
}

export function duration(a, b) {
  const s = Math.max(0, (Date.parse(b) - Date.parse(a)) / 1000);
  if (!isFinite(s)) return "";
  return s < 60 ? `${Math.round(s)}s` : s < 3600 ? `${Math.floor(s / 60)}m ${Math.round(s % 60)}s` : `${Math.floor(s / 3600)}h ${Math.round((s % 3600) / 60)}m`;
}

// How a PR's state shows: label, icon and theme colour name.
export function prLook(pr) {
  if (!pr) return null;
  if (pr.state === "MERGED") return { label: "Merged", icon: "git-merge", color: "ansi5" };
  if (pr.state === "CLOSED") return { label: "Closed", icon: "git-pull-request-closed", color: "ansi1" };
  if (pr.isDraft) return { label: "Draft", icon: "git-pull-request-draft", color: "muted" };
  return { label: "Open", icon: "git-pull-request", color: "ansi2" };
}

export function reviewLook(decision) {
  if (decision === "APPROVED") return { label: "Approved", color: "ansi2" };
  if (decision === "CHANGES_REQUESTED") return { label: "Changes requested", color: "ansi1" };
  if (decision === "REVIEW_REQUIRED") return { label: "Review required", color: "muted" };
  return null;
}

// Files that conflict between the branch and its base, from a merge done in
// memory (git merge-tree: no worktree or index change; it stores loose objects,
// so call it only when GitHub says the PR conflicts). null when it can't tell.
export async function conflicts(root, on, base) {
  const r = await git(["merge-tree", "--write-tree", "--name-only", "--no-messages", base, "HEAD"], root, on);
  if (r.code === 0) return [];
  if (r.code !== 1) return null;
  return r.stdout.trim().split("\n").slice(1).filter(Boolean);
}
