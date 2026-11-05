// Ship it: a fixed strip under the tab bar that says where the work is (the
// folder, and what the pull request waits on: checks, threads, review) and takes it from there
// to shipped. On the right: the PR button (number, state, title) opens the
// ship-it-review pane, the changes button what the branch changes in the side
// panel, PRs the repo's open pull requests, and Ship merges this one (after a
// confirm). Checks, threads and the review beside the branch open the review
// too. It follows the focused pane.

import { View, div, svg } from "gpui-kit";
import { h_flex } from "gpui-base";
import { theme, run, layout, shared, setShared, panes, focused, watchFolder, notify, exec, openOverlay, nextCommand } from "herdr";
import { READ, tilde, location, gitFacts, prFacts, PR_DETAIL, checks, threads, tally, baseRef, prLook, reviewLook, Recent } from "./data.js";

const ICON = (name) => `mods/ship-it/icons/${name}.svg`;

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

export default class ShipIt extends View {
  init(_props, cx) {
    this.loc = null; this.git = null; this.pr = null; this.checks = null; this.threads = null; this.stat = null;
    this.width = 1200; this.first = true;
    // Last facts per folder and per branch: a worktree you come back to shows at once.
    this.gits = new Recent(); this.prs = new Recent();
    this.refreshGit(cx);
    // A local repo's folder watch catches edits, so its poll is only a backstop.
    cx.timer.every(5000, (cx) => { if (this.loc?.on || !this.watched || (this.poll = (this.poll ?? 0) + 1) % 6 === 0) this.refreshGit(cx); });
    cx.timer.every(30000, (cx) => {
      // Pending checks move fast; settled ones are polled gently.
      const pending = tally(this.checks).pending > 0;
      if (pending || (this.tick = (this.tick ?? 0) + 1) % 4 === 0) this.refreshPr(cx);
    });
    // "ship-it.merge" comes back from the confirm dialog Ship opens.
    cx.spawn(async (cx) => { for (;;) { const c = await nextCommand(); if (c === "merge" || c === "ship-it.merge") this.merge(cx); cx.notify(); } });
  }

  // Git facts for the focused folder; a new repo or branch also refreshes the PR.
  refreshGit(cx) {
    if (this.gitBusy) return;
    const loc = location(this.loc), key = JSON.stringify([loc.cwd, loc.on]);
    if (key !== this.locKey) {
      const known = this.gits.get(key);
      this.locKey = key; this.loc = loc; this.git = known ?? null; this.first = !known; this.arrived = true;
      this.restore(known ? this.branchOf(known) : null);
    }
    if (!loc.cwd) { this.first = false; return; }
    this.gitBusy = true;
    let changed = true;
    cx.spawn(async (cx) => {
      try {
        const facts = await gitFacts(loc.cwd, loc.on);
        if (key !== this.locKey) return;
        const was = this.git, branchKey = facts ? this.branchOf(facts) : null;
        if (facts) this.gits.set(key, facts);
        // Every redraw redraws the whole window: only notify when something shows differently.
        changed = this.first || JSON.stringify(was) !== JSON.stringify(facts);
        this.git = facts;
        if (facts && !loc.on && this.watched !== facts.root) this.watch(facts.root, cx);
        const arrived = this.arrived, moved = branchKey !== this.branchKey, known = branchKey && this.prs.get(branchKey);
        this.arrived = false;
        if (moved) { this.restore(branchKey); changed = true; }
        // Arriving shares what is known at once; it asks GitHub again for a new
        // branch, or when what is known is over 20 s old.
        if (arrived || moved) this.publish();
        if (branchKey && (moved || !known?.at || (arrived && Date.now() - known.at > 20000))) this.refreshPr(cx);
        else if (facts && (!this.stat || was?.dirty !== facts.dirty || was?.sha !== facts.sha)) this.refreshStat(cx);
      } catch { if (key === this.locKey) this.git = null; }
      finally { this.gitBusy = false; this.first = false; if (changed) cx.notify(); }
    });
  }

  watch(root, cx) {
    this.watched = root;
    cx.spawn(async (cx) => {
      try {
        while (this.watched === root) {
          await watchFolder(root);
          // A burst of writes (a build, an agent's edits) becomes one refresh.
          await cx.sleep(1000);
          if (this.watched === root) this.refreshGit(cx);
        }
      } catch { this.watched = null; }
    });
  }

  refreshPr(cx) {
    const g = this.git, key = this.branchKey;
    // One load per branch at a time; a load for a branch left behind doesn't block this one.
    if (!g || this.prBusy === key) return;
    this.prBusy = key;
    cx.spawn(async (cx) => {
      try {
        const pr = await prFacts(g.root, g.on, PR_DETAIL), ok = pr.kind === "ok";
        if (key === this.branchKey) this.pr = pr;
        const [list, threadList, base] = await Promise.all([
          ok ? checks(g.root, g.on) : null,
          ok ? threads(g.root, g.on, pr.pr).catch(() => []) : [],
          baseRef(g.root, g.on, pr.pr),
        ]);
        // Cached even when the branch was left meanwhile: going back shows it.
        const entry = { ...this.prs.get(key), pr, checks: list, threads: threadList, base: { ref: base, key }, at: Date.now() };
        this.prs.set(key, entry);
        if (key !== this.branchKey) return;
        this.pr = pr; this.checks = list; this.threads = threadList; this.base = entry.base;
        this.publish();
        await this.refreshStat(cx, key);
      } catch (e) { if (key === this.branchKey) this.pr = { kind: "unavailable", reason: String(e) }; }
      finally { if (this.prBusy === key) this.prBusy = null; cx.notify(); }
    });
  }

  // Files, additions and deletions on the branch since its base, uncommitted included.
  async refreshStat(cx, key = this.branchKey) {
    // The base belongs to the branch it was found for, never to the last repo.
    const g = this.git, base = this.base?.key === key ? this.base.ref : null;
    if (!g || !base) return;
    const run = (args) => exec("git", [...READ, ...args], { cwd: g.root, on: g.on });
    const mb = (await run(["merge-base", base, "HEAD"])).stdout.trim();
    if (!mb) return;
    const [num, untracked] = await Promise.all([run(["diff", mb, "--numstat", "-z", "--no-renames"]), run(["ls-files", "--others", "--exclude-standard", "-z"])]);
    if (key !== this.branchKey) return;
    let files = 0, add = 0, del = 0;
    for (const entry of num.stdout.split("\0")) {
      const [a, d, ...p] = entry.split("\t");
      if (!p.length) continue;
      files++; add += Number(a) || 0; del += Number(d) || 0;
    }
    files += untracked.stdout.split("\0").filter(Boolean).length;
    const stat = { files, add, del, base };
    if (JSON.stringify(stat) === JSON.stringify(this.stat)) return;
    this.stat = stat;
    this.remember(key);
    cx.notify();
  }

  branchOf(g) { return `${g.on ?? ""}:${g.root}#${g.branch ?? g.sha}`; }

  // The branch's last PR facts, or nothing: shown until the refresh lands.
  restore(branchKey) {
    const c = branchKey ? this.prs.get(branchKey) : null;
    this.branchKey = branchKey;
    this.pr = c?.pr ?? null; this.checks = c?.checks ?? null; this.threads = c?.threads ?? null;
    this.stat = c?.stat ?? null; this.base = c?.base ?? null;
  }

  // Keeps `at` (when GitHub was last asked): its age decides the next ask on arrival.
  remember(key) {
    if (key !== this.branchKey) return;
    this.prs.set(key, { ...this.prs.get(key), pr: this.pr, checks: this.checks, threads: this.threads, stat: this.stat, base: this.base });
  }

  // Shares the PR (with its details, checks and threads) and the base with the
  // panels and the review, so they show it without asking gh again. Shared
  // state redraws every mod: written only when it changes.
  publish() {
    const g = this.git, p = this.pr;
    if (!g || !p) return;
    const base = this.base?.key === this.branchKey ? this.base.ref : null, now = shared("ship-it.base");
    if (base && (now?.root !== g.root || (now?.on ?? null) !== (g.on ?? null) || now?.ref !== base)) setShared("ship-it.base", { root: g.root, on: g.on ?? null, ref: base });
    const next = { root: g.root, on: g.on ?? null, branch: g.branch, kind: p.kind, pr: p.kind === "ok" ? p.pr : null, checks: this.checks, threads: this.threads };
    const was = shared("ship-it.pr"), { at, ...old } = was ?? {};
    if (JSON.stringify(old) !== JSON.stringify(next)) setShared("ship-it.pr", { ...next, at: Date.now() });
    this.published = Date.now();
  }

  panel() {
    const root = layout(), panel = find(root, "panel"), body = find(root, "panel-body");
    const has = (id) => Boolean(body?.children?.some((c) => c.id === id));
    return { panel, body, has, open: (id) => panel && !panel.hidden && body?.active === id };
  }

  // The block that holds the Changes panel: "changes" when it took the place
  // of Herdr's own, else "ship-it-changes"; null without one.
  changesHost() {
    return this.panel().body?.children?.find((c) => c.content?.mod === "ship-it-changes")?.id ?? null;
  }

  // The changes button: Changes on its branch view (since the base). Open on
  // that view already, it closes.
  toggleChanges() {
    const id = this.changesHost(), p = this.panel(), branch = shared("ship-it.changes")?.mode !== "dirty";
    if (!id) return;
    if (p.open(id) && branch) { run("layout.hide", { id: "panel" }); return; }
    if (!branch) setShared("ship-it.changes", { mode: "branch", at: Date.now() });
    run("layout.select", { stack: "panel-body", child: id }); run("layout.show", { id: "panel" });
  }

  togglePanel(id) {
    const p = this.panel();
    if (!p.has(id)) return;
    if (p.open(id)) run("layout.hide", { id: "panel" });
    else { run("layout.select", { stack: "panel-body", child: id }); run("layout.show", { id: "panel" }); }
  }

  // The review: in the side panel when the layout has a ship-it-review block
  // (a second click on the same tab closes it), else this tab's review pane,
  // else a new one to the right.
  openReview(tab) {
    const g = this.git, f = focused(), p = this.panel();
    if (!g) return;
    if (p.has("ship-it-review")) {
      const now = shared("ship-it.target");
      if (p.open("ship-it-review") && now?.tab === tab && now?.root === g.root) { run("layout.hide", { id: "panel" }); return; }
      setShared("ship-it.target", { root: g.root, on: g.on, tab, at: Date.now() });
      run("layout.select", { stack: "panel-body", child: "ship-it-review" }); run("layout.show", { id: "panel" });
      return;
    }
    if (!f) return;
    setShared("ship-it.target", { root: g.root, on: g.on, tab, at: Date.now() });
    const existing = panes().find((p) => p.mod === "ship-it-review" && p.tab === f.tab);
    if (existing) { run("pane.focus", { pane: existing.pane }); return; }
    // Split from a pane in the tab on screen: focus can still sit in another space's tab.
    const own = panes().find((p) => p.pane === f.pane && p.tab === f.tab);
    const from = own?.pane ?? panes().find((p) => p.tab === f.tab)?.pane;
    run("pane.split", { direction: "right", ...(from ? { pane: from } : {}), mod: "ship-it-review", props: { root: g.root, on: g.on, tab } });
  }

  // ---- shipping

  // Why Ship can't merge now, or null when it can.
  shipBlock() {
    const p = this.pr;
    if (!p || p.kind === "unavailable") return p ? p.reason : "Loading…";
    if (p.kind !== "ok") return "No pull request for this branch";
    const pr = p.pr;
    if (pr.state === "MERGED") return "Already merged";
    if (pr.state === "CLOSED") return "The pull request is closed";
    if (pr.isDraft) return "Draft: mark it ready for review first";
    if (pr.mergeable === "CONFLICTING" || pr.mergeStateStatus === "DIRTY") return `Conflicts with ${pr.baseRefName}`;
    if (this.merging) return "Merging…";
    return null;
  }

  // Asks first: what merges into what, how, and anything that looks wrong.
  async ship(cx) {
    const g = this.git, pr = this.pr?.pr;
    if (!g || !pr || this.shipBlock()) return;
    const r = await exec("gh", ["repo", "view", "--json", "squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed"], { cwd: g.root, on: g.on }).catch(() => null);
    let allowed = {};
    try { allowed = JSON.parse(r?.stdout || "{}"); } catch {}
    const method = allowed.squashMergeAllowed !== false ? "squash" : allowed.mergeCommitAllowed ? "merge" : "rebase";
    const c = tally(this.checks), warn = [];
    if (c.fail + c.cancel) warn.push(`${c.fail + c.cancel} check${c.fail + c.cancel > 1 ? "s" : ""} failing`);
    if (c.pending) warn.push(`${c.pending} check${c.pending > 1 ? "s" : ""} still running`);
    if (pr.reviewDecision === "CHANGES_REQUESTED") warn.push("changes requested");
    else if (pr.reviewDecision === "REVIEW_REQUIRED") warn.push("not approved yet");
    const open = (this.threads ?? []).filter((th) => !th.resolved).length;
    if (open) warn.push(`${open} open thread${open > 1 ? "s" : ""}`);
    this.pendingMerge = { root: g.root, on: g.on, number: pr.number, sha: pr.headRefOid, method, at: Date.now() };
    const how = { squash: "Squash and merge", merge: "Merge", rebase: "Rebase and merge" }[method];
    openOverlay({ mod: "confirm", kind: "dialog", width: 420, height: 200, props: {
      title: `Ship #${pr.number}?`,
      detail: `${how} ${pr.headRefName} into ${pr.baseRefName}.${warn.length ? ` Note: ${warn.join(", ")}.` : ""} The branch stays.`,
      command: { name: "ship-it.merge" },
    } });
  }

  // Merges exactly the commit that was shown (--match-head-commit): a push in
  // between makes GitHub refuse rather than merge something unseen.
  merge(cx) {
    const m = this.pendingMerge, g = this.git;
    this.pendingMerge = null;
    if (!m || !g || Date.now() - m.at > 120000 || m.root !== g.root || this.merging) return;
    this.merging = true;
    cx.spawn(async (cx) => {
      try {
        const args = ["pr", "merge", String(m.number), `--${m.method}`, ...(m.sha ? ["--match-head-commit", m.sha] : [])];
        const r = await exec("gh", args, { cwd: m.root, on: m.on });
        if (r.code === 0) notify({ title: `#${m.number} shipped`, body: "Merged on GitHub", level: "info", timeout: 4 });
        else notify({ title: `#${m.number} not merged`, body: (r.stderr || r.stdout || "gh failed").trim().split("\n").slice(-2).join(" "), level: "error", timeout: 8 });
      } catch (e) { notify({ title: `#${m.number} not merged`, body: String(e), level: "error", timeout: 8 }); }
      finally { this.merging = false; this.refreshPr(cx); cx.notify(); }
    });
  }

  // ---- drawing

  icon(name, color, size = 14) { return svg(ICON(name)).size(size).flex_none().text_color(color); }

  sep(t) { return div().w(1).h(16).mx(12).flex_none().bg(t.border); }

  // A clickable group: hover lifts it a little.
  group(id, t, el, onClick, tip) {
    return h_flex().id(id).h(28).px(6).gap(6).min_w(0).items_center().rounded(6)
      .when(Boolean(onClick), (e) => e.cursor_pointer().hover((s) => s.bg(t.hover)).on_click(onClick))
      .when(Boolean(tip), (e) => e.tooltip(tip))
      .child(el);
  }

  button(id, t, { icon, label, extra, on, onClick, tip }) {
    return h_flex().id(id).h(26).px(9).gap(6).flex_none().items_center().rounded(6).cursor_pointer()
      .border_1().border_color(on ? t.accent : t.border).bg(on ? t.selected : t.background)
      .hover((s) => s.bg(t.hover)).on_click(onClick).when(Boolean(tip), (e) => e.tooltip(tip))
      .child(this.icon(icon, on ? t.accent : t.muted, 13))
      .when(Boolean(label), (e) => e.child(div().text_color(t.foreground).child(label)))
      .children(extra ?? []);
  }

  // Ship: solid when it can merge, quiet with the reason when it can't.
  shipButton(t) {
    const block = this.shipBlock(), merged = this.pr?.pr?.state === "MERGED";
    return h_flex().id("ship").h(26).px(10).gap(6).flex_none().items_center().rounded(6).border_1()
      .when(!block, (e) => e.border_color(t.solid).bg(t.solid).cursor_pointer().hover((s) => s.opacity(0.88)).on_click((_e, cx) => this.ship(cx)))
      .when(Boolean(block), (e) => e.border_color(t.border).bg(t.background))
      .tooltip(block ?? `Merge #${this.pr.pr.number} into ${this.pr.pr.baseRefName}`)
      .child(this.icon(merged ? "git-merge" : "rocket", block ? t.dim : t.solid_foreground, 13))
      .child(div().text_color(block ? t.dim : t.solid_foreground).font_semibold().child(this.merging ? "Shipping…" : merged ? "Shipped" : "Ship"));
  }



  folder(t, narrow) {
    const g = this.git, path = g ? tilde(g.root) : tilde(this.loc?.cwd);
    const name = path.split("/").pop() || path;
    const has = this.panel().has("files");
    return this.group("folder", t, h_flex().gap(6).min_w(0).items_center()
      .child(this.icon("folder", t.muted))
      .child(div().min_w(0).text_color(t.foreground).whitespace_nowrap().text_ellipsis_start().child(narrow ? name : path))
      .when(Boolean(g?.sub) && !narrow, (e) => e.child(div().flex_none().text_color(t.dim).whitespace_nowrap().child(g.sub))),
      has ? () => this.togglePanel("files") : null, g ? `${g.root}${g.sub}` : this.loc?.cwd ?? "");
  }



  // What the PR waits on, beside the folder: conflicts, open threads, the
  // review (its checks are a button on the right). Each opens the review. null when there is nothing to say.
  prSignals(t) {
    const p = this.pr;
    if (!p) return this.group("pr", t, div().text_color(t.dim).child("…"));
    if (p.kind === "unavailable") return this.group("pr", t, h_flex().gap(6).items_center().child(this.icon("git-pull-request", t.dim)).child(div().text_color(t.dim).child("gh unavailable")), null, p.reason);
    if (p.kind === "none") return null;
    const pr = p.pr, review = reviewLook(pr.reviewDecision);
    const open = (this.threads ?? []).filter((th) => !th.resolved).length;
    const conflicted = pr.mergeable === "CONFLICTING" || pr.mergeStateStatus === "DIRTY";
    if (!conflicted && !open && !review) return null;
    return h_flex().gap(2).min_w(0).items_center()
      .when(conflicted, (e) => e.child(this.group("conflicts", t, h_flex().gap(4).items_center().text_color(t.ansi1).whitespace_nowrap()
        .child(this.icon("git-merge", t.ansi1, 12)).child("Conflicts"), () => this.openReview("overview"), `Conflicts with ${pr.baseRefName}`)))
      .when(open > 0, (e) => e.child(this.group("threads", t, h_flex().gap(4).items_center().text_color(t.accent)
        .child(this.icon("message-square", t.accent, 12)).child(String(open)), () => this.openReview("overview"), `${open} open review thread${open > 1 ? "s" : ""}`)))
      .when(Boolean(review), (e) => e.child(this.group("review", t, div().text_color(t[review.color] ?? t.muted).whitespace_nowrap().child(review.label), () => this.openReview("overview"))));
  }

  // First on the left: the repo's name and its open PRs; a click toggles the
  // PRs panel. Without a GitHub remote (or the panel), only the name.
  repoButton(t) {
    const g = this.git, p = this.panel(), prs = p.has("ship-it-prs") && this.showPrs(), n = this.prCount(), on = prs && p.open("ship-it-prs");
    return h_flex().id("repo").h(26).px(9).gap(6).flex_none().items_center().rounded(6)
      .border_1().border_color(on ? t.accent : t.border).bg(on ? t.selected : t.background)
      .when(prs, (e) => e.cursor_pointer().hover((s) => s.bg(t.hover)).tooltip(`Open pull requests in ${g.repo}`).on_click(() => this.togglePanel("ship-it-prs")))
      .child(this.icon("git-pull-request", on ? t.accent : t.muted, 13))
      .child(div().font_semibold().text_color(t.foreground).whitespace_nowrap().child(g.repo))
      .when(prs, (e) => e.child(div().text_color(t.muted).whitespace_nowrap().child(n ? `${n} PR${n > 1 ? "s" : ""}` : "PRs")));
  }

  // CI on the right, between the changes and PRs buttons: the PR's checks
  // as passed, failed and running counts. Opens the review on Checks.
  checksButton(t) {
    if (this.pr?.kind !== "ok" || !this.checks?.length) return null;
    const c = tally(this.checks), on = this.panel().open("ship-it-review") && shared("ship-it.target")?.tab === "checks";
    if (!(c.pass + c.fail + c.cancel + c.pending)) return null; // only skipped: nothing to count
    const count = (icon, n, col) => n > 0 ? h_flex().gap(3).items_center().text_color(col).child(this.icon(icon, col, 12)).child(String(n)) : null;
    return h_flex().id("checks").h(26).px(9).gap(8).flex_none().items_center().rounded(6).cursor_pointer()
      .border_1().border_color(on ? t.accent : t.border).bg(on ? t.selected : t.background).hover((s) => s.bg(t.hover))
      .tooltip(`CI: ${c.pass} passed · ${c.fail} failed · ${c.pending} running · ${c.skipping} skipped`).on_click(() => this.openReview("checks"))
      .children([count("circle-check", c.pass, t.ansi2), count("circle-x", c.fail + c.cancel, t.ansi1), count("circle-dot", c.pending, t.ansi3)].filter(Boolean));
  }

  // The main action on the right: the PR (icon, number, state, the title's
  // first 30 characters) opens its review; with none, Create opens GitHub's form.
  prButton(t, narrow) {
    const p = this.pr;
    if (p?.kind === "none") return this.button("pr-create", t, { icon: "git-pull-request", label: "Create PR", tip: "Open a pull request for this branch on GitHub",
      onClick: () => { const g = this.git; exec("gh", ["pr", "create", "--web"], { cwd: g.root, on: g.on }); } });
    if (p?.kind !== "ok") return null;
    const pr = p.pr, look = prLook(pr), color = t[look.color] ?? t.muted;
    const title = pr.title.length > 30 ? `${pr.title.slice(0, 30).trimEnd()}…` : pr.title;
    const target = shared("ship-it.target"), on = this.panel().open("ship-it-review") && target?.root === this.git?.root && target?.tab !== "checks";
    return h_flex().id("pr").h(26).px(9).gap(6).flex_none().items_center().rounded(6).cursor_pointer()
      .border_1().border_color(on ? t.accent : t.border).bg(on ? t.selected : t.background).hover((s) => s.bg(t.hover))
      .tooltip(`#${pr.number} ${pr.title} · open the review`).on_click(() => this.openReview("overview"))
      .child(this.icon(look.icon, color, 13))
      .child(div().flex_none().text_color(t.muted).child(`#${pr.number}`))
      .child(div().h(18).px(7).flex_none().flex().items_center().rounded(9).bg(color + "22").text_size(10.5).font_semibold().text_color(color).child(look.label))
      .when(!narrow, (e) => e.child(div().flex_none().text_color(t.foreground).whitespace_nowrap().child(title)));
  }

  // The PR list needs a GitHub remote.
  showPrs() { return this.pr?.kind !== "none" || this.pr.remote !== false; }

  // Open PRs, as the PR list last counted them for this repo.
  prCount() {
    const s = shared("ship-it.prs"), g = this.git;
    return s && g && s.root === g.root && (s.on ?? null) === (g.on ?? null) ? s.count : 0;
  }

  // Hidden outside a repo, without a remote, and on the default branch with no PR.
  showPr() {
    const g = this.git, p = this.pr;
    if (!g) return false;
    if (p?.kind !== "none") return true;
    const base = (this.base?.ref ?? "").replace(/^origin\//, "");
    return p.remote !== false && !g.detached && g.branch !== base && !["main", "master"].includes(g.branch);
  }

  render(cx) {
    // render runs on every focus and space change: follow the new folder now,
    // not at the next poll.
    const loc = location(this.loc);
    if (JSON.stringify([loc.cwd, loc.on]) !== this.locKey) this.refreshGit(cx);
    const t = theme(), g = this.git, narrow = this.width < 900, p = this.panel();
    // Each is null when there is nothing to show (prButton while the PR loads).
    const s = this.stat, signals = this.showPr() ? this.prSignals(t) : null, prButton = this.showPr() ? this.prButton(t, narrow) : null, checks = this.checksButton(t);
    return h_flex().id("ship-it").size_full().px(10).items_center().bg(t.chrome).border_b(1).border_color(t.border)
      .text_size(12).text_color(t.foreground).overflow_hidden()
      .on_size_change((size, cx) => { if (Math.abs(size.width - this.width) > 1) { this.width = size.width; cx.notify(); } })
      // Left: the repo and its PRs, the folder when it says more than the name
      // (a worktree, a subfolder), and what the PR waits on, in what the
      // buttons leave: the folder's path shortens from its start, so nothing
      // runs under them. The machine and branch are in Herdr's status bar.
      .child(h_flex().flex_1().min_w(0).overflow_hidden().items_center()
        .when(Boolean(g), (e) => e.child(this.repoButton(t)))
        .when(!g || g.worktree || Boolean(g.sub), (e) => e.child(this.loc?.cwd ? this.folder(t, narrow) : div().text_color(t.dim).child(this.first ? "…" : "No folder")))
        .when(Boolean(signals), (e) => e.child(this.sep(t)).child(signals.flex_none())))
      .when(Boolean(g), (e) => e.child(h_flex().ml(8).gap(6).flex_none().items_center()
        .when(Boolean(prButton), (e) => e.child(prButton))
        .when(Boolean(this.changesHost()), (e) => e.child(this.button("pr-changes", t, {
          icon: "file-diff", label: null, on: p.open(this.changesHost()) && shared("ship-it.changes")?.mode !== "dirty", onClick: () => this.toggleChanges(),
          extra: s?.files ? [div().text_color(t.muted).child(`${s.files}`), div().text_color(t.ansi2).child(`+${s.add}`), div().text_color(t.ansi1).child(`−${s.del}`)] : [],
          tip: s ? `${s.files} files changed since ${s.base}` : "What this branch changes",
        })))
        .when(Boolean(checks), (e) => e.child(checks))
        .when(this.showPr(), (e) => e.child(this.shipButton(t)))));
  }
}
