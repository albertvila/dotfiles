// Ship it · Review: the branch's pull request in a pane beside the terminals.
// Overview (description, conversation, a comment box), Files (every change
// since the base, with viewed marks and inline review threads) and Checks
// (failing first, the failed log's tail, re-run). Opened by the ship-it strip,
// which says what to show through shared("ship-it.target").

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex, Scrollbar, v_virtual_list, VirtualListScrollHandle, TextView, TextareaState, Textarea } from "gpui-base";
import { theme, settings, props, shared, setShared, run, panes, focused, exec, notify, watchFolder, nextCommand } from "herdr";
import { gitFacts, prFacts, PR_DETAIL, checks, tally, baseRef, threads, conflicts, gql, ago, duration, prLook, reviewLook, tilde, modShown, panelShown, Recent, sharedPr } from "./data.js";
import { branchFiles, fileDiff, diffRows, logTail, MAX_FILES } from "./files.js";

const ICON = (name) => `mods/ship-it-review/icons/${name}.svg`;
const TABS = [["overview", "Overview"], ["files", "Files"], ["checks", "Checks"]];
const STATUS = { A: "ansi2", M: "ansi3", D: "ansi1", R: "accent", U: "ansi1" };
const BUCKETS = [
  ["fail", "Failing", "circle-x", "ansi1"],
  ["pending", "Pending", "circle-dot", "ansi3"],
  ["pass", "Passed", "circle-check", "ansi2"],
  ["skipping", "Skipped", "circle-minus", "dim"],
];
const bucketOf = (c) => (c.bucket === "cancel" ? "fail" : BUCKETS.some((b) => b[0] === c.bucket) ? c.bucket : "pending");

const REPLY = `mutation($id:ID!,$body:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$id,body:$body}){comment{id}}}`;
const RESOLVE = `mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}`;
const UNRESOLVE = `mutation($id:ID!){unresolveReviewThread(input:{threadId:$id}){thread{isResolved}}}`;

const store = {
  get(key) { try { return JSON.parse(localStorage.getItem(key) || "{}"); } catch { return {}; } },
  set(key, value) { try { localStorage.setItem(key, JSON.stringify(value)); } catch {} },
};

export default class Review extends View {
  init(_p, cx) {
    const p = props() ?? _p;
    // In the side panel (a layout block, no props) it follows the strip's repo;
    // as a pane it keeps the repo it was opened on.
    this.inPanel = !p?.root;
    this.handle = cx.focus_handle();
    this.diffScroll = VirtualListScrollHandle.new();
    this.fileScroll = VirtualListScrollHandle.new();
    this.logScroll = VirtualListScrollHandle.new();
    this.seen = shared("ship-it.target")?.at ?? 0;
    this.tab = p?.tab ?? "overview";
    this.width = 800;
    // Last facts per repo: going back to one shows them at once while a refresh runs.
    this.memo = new Recent(12);
    this.reset(p?.root ?? null, p?.on ?? null);

    this.composer = TextareaState.new({ placeholder: "Leave a comment" });
    this.composer.set_auto_grow(2, 8);
    this.comment = "";
    this.wire(this.composer, "comment", (cx) => this.postComment(cx));
    this.replyBox = TextareaState.new({ placeholder: "Reply…" });
    this.replyBox.set_auto_grow(1, 6);
    this.reply = "";
    this.wire(this.replyBox, "reply", (cx) => this.postReply(cx));

    this.refresh(cx);
    // Pending checks move; everything else waits for r, the strip or a file change.
    // Timers and watches only work while a review pane is on screen.
    cx.timer.every(20000, (cx) => {
      if (this.shown() && this.pr?.kind === "ok" && tally(this.checks).pending > 0) this.refreshChecks(cx);
    });
    cx.timer.every(10000, (cx) => { if (this.on) this.refreshFiles(cx); });
    // Bindable from keys.json ("ship-it-review.checks") or `herdr-app do`.
    cx.spawn(async (cx) => { for (;;) { this.command(await nextCommand(), cx); cx.notify(); } });
  }

  // Text boxes: track their text and focus, and post on cmd/ctrl-enter.
  wire(state, field, submit) {
    state.on("change", (_e, cx) => {
      const had = Boolean(this[field].trim());
      this[field] = state.value();
      if (had !== Boolean(this[field].trim())) cx.notify();
    });
    state.on("submit", (e, cx) => { if (e?.secondary) submit(cx); });
    state.on("focus", (_e, cx) => { this.typing = field; cx.notify(); });
    state.on("blur", (_e, cx) => { if (this.typing === field) this.typing = null; cx.notify(); });
  }

  reset(root, on) {
    this.root = root; this.on = on;
    this.git = null; this.pr = null; this.checks = null; this.threads = []; this.base = null; this.mb = null;
    this.files = []; this.limited = false; this.open = null; this.closed = false; this.rows = []; this.shows = null; this.rowThreads = new Map();
    this.diffWidth = 0; this.cut = false; this.note = null; this.error = null;
    this.drawer = null; this.log = null; this.watched = null; this.loaded = false; this.checkIndex = -1; this.conflicts = null; this.offer = null;
    this.viewedKey = root ? `viewed:${on ?? ""}:${root}` : null;
    this.viewed = this.viewedKey ? store.get(this.viewedKey) : {};
    // Loads for the last repo finish on their own and are dropped by gen.
    this.gen = (this.gen ?? 0) + 1;
    this.loading = false; this.filesBusy = false; this.diffBusy = false; this.checksBusy = false; this.filesStale = false;
    this.recall();
  }

  memoKey() { return `${this.on ?? ""}:${this.root}`; }

  // What this repo showed last time, else the strip's PR for it.
  recall() {
    if (!this.root) return;
    const m = this.memo?.get(this.memoKey());
    if (m) {
      Object.assign(this, m); this.loaded = true;
      if (this.files.length) { this.open = this.files[0].path; this.filesStale = true; }
      return;
    }
    const s = sharedPr(this.root, this.on);
    if (s) { this.pr = s.kind === "ok" ? { kind: "ok", pr: s.pr } : { kind: s.kind }; this.checks = s.checks; this.threads = s.threads ?? []; this.prAt = s.at; this.loaded = true; }
  }

  remember() {
    if (!this.root || !this.memo) return;
    this.memo.set(this.memoKey(), { git: this.git, pr: this.pr, checks: this.checks, threads: this.threads, prAt: this.prAt, base: this.base, mb: this.mb, files: this.files, limited: this.limited, conflicts: this.conflicts });
  }

  // The strip's PR facts, when they are for this repo and branch.
  stripPr() {
    const s = sharedPr(this.root, this.on);
    return s && this.git && s.branch === this.git.branch ? s : null;
  }

  adopt(s) {
    this.pr = s.kind === "ok" ? { kind: "ok", pr: s.pr } : { kind: s.kind }; this.checks = s.checks; this.threads = s.threads ?? []; this.prAt = s.at;
    this.mapThreads();
  }

  // ---- loading

  // Hidden (another tab, another space), it loads nothing until it shows.
  // `force` (r, a posted comment, a reply) asks GitHub even when the strip's
  // facts are fresh.
  refresh(cx, force) {
    const root = this.root, on = this.on, gen = this.gen;
    if (root && !this.shown()) { this.stale = true; return; }
    if (!root || this.loading) return;
    this.stale = false;
    this.loading = true;
    cx.spawn(async (cx) => {
      try {
        const facts = await gitFacts(root, on);
        if (gen !== this.gen) return;
        if (!facts) { this.error = "Not a git repository"; return; }
        this.git = facts;
        // The strip already found this repo's base: read the files while GitHub answers.
        const known = shared("ship-it.base");
        const early = known?.root === root && (known.on ?? null) === (on ?? null) ? known.ref : null;
        let files = null;
        if (early && this.tab === "files") {
          this.base = early;
          files = this.loadFiles(cx, gen).then(() => cx.notify());
        }
        // The strip asked GitHub under a minute ago: no need to ask again.
        const strip = this.stripPr();
        let pr, list, threadList, base;
        if (!force && strip && Date.now() - strip.at < 60000) {
          this.adopt(strip); pr = this.pr; list = this.checks; threadList = this.threads;
          cx.notify();
          base = await baseRef(root, on, pr.pr);
        } else {
          pr = await prFacts(root, on, PR_DETAIL);
          if (gen !== this.gen) return;
          this.pr = pr; this.prAt = Date.now();
          cx.notify();
          const ok = pr.kind === "ok";
          [list, threadList, base] = await Promise.all([
            ok ? checks(root, on) : null,
            ok ? threads(root, on, pr.pr).catch(() => []) : [],
            baseRef(root, on, pr.pr),
          ]);
        }
        if (gen !== this.gen) return;
        const ok = pr.kind === "ok";
        this.checks = list; this.threads = threadList; this.base = base; this.mapThreads();
        // Only when GitHub says so: the in-memory merge stores loose objects.
        this.conflicts = ok && (pr.pr.mergeable === "CONFLICTING" || pr.pr.mergeStateStatus === "DIRTY") && base ? await conflicts(root, on, base).catch(() => null) : null;
        if (gen !== this.gen) return;
        if (!on) this.watch(root, cx);
        if (files) await files;
        if (this.tab !== "files") this.filesStale = true;
        else if (!files || base !== early) await this.loadFiles(cx, gen);
      } catch (e) { if (gen === this.gen) this.error = String(e?.message ?? e); }
      finally { if (gen === this.gen) { this.loading = false; this.loaded = true; this.remember(); } cx.notify(); }
    });
  }

  refreshChecks(cx) {
    const root = this.root, on = this.on, gen = this.gen;
    if (!root || this.checksBusy) return;
    this.checksBusy = true;
    cx.spawn(async (cx) => {
      try { const list = await checks(root, on); if (gen === this.gen && list) this.checks = list; }
      finally { this.checksBusy = false; cx.notify(); }
    });
  }

  shown() { return this.inPanel ? panelShown("ship-it-review") : modShown("ship-it-review"); }

  // Files load when the Files tab shows (Overview and Checks don't need them);
  // hidden or on another tab, a change only marks them stale.
  refreshFiles(cx) {
    if (!this.shown() || this.tab !== "files") { this.filesStale = true; return; }
    if (!this.base || this.loading || this.filesBusy) return;
    this.filesStale = false;
    const gen = this.gen;
    cx.spawn(async (cx) => { await this.loadFiles(cx, gen); cx.notify(); });
  }

  watch(root, cx) {
    if (this.watched === root) return;
    this.watched = root;
    cx.spawn(async (cx) => {
      try {
        while (this.watched === root) {
          await watchFolder(root);
          // A burst of writes (a build, an agent's edits) becomes one refresh.
          await cx.sleep(1500);
          if (this.watched === root) this.refreshFiles(cx);
        }
      } catch { this.watched = null; }
    });
  }

  async loadFiles(cx, gen) {
    if (!this.base) { this.error = "No base branch to compare with"; return; }
    this.filesBusy = true;
    try {
      const { mb, files, limited } = await branchFiles(this.root, this.on, this.base);
      if (gen !== this.gen) return;
      const before = this.files.find((f) => f.path === this.open)?.key;
      this.mb = mb; this.files = files; this.limited = limited; this.error = null;
      if (this.open && !files.some((f) => f.path === this.open)) { this.open = null; this.setRows([]); }
      if (!this.open && !this.closed && files.length) this.open = files[0].path;
      const now = files.find((f) => f.path === this.open);
      if (now && (now.key !== before || this.shows !== now.key)) await this.loadDiff(now, gen);
      if (gen === this.gen) this.remember();
    } catch (e) { if (gen === this.gen) this.error = String(e?.message ?? e); }
    finally { this.filesBusy = false; }
  }

  async loadDiff(file, gen) {
    this.diffBusy = true;
    try {
      const { lines, cut } = await fileDiff(this.root, this.on, this.mb, file);
      if (gen !== this.gen || this.open !== file.path) return;
      if (this.shows !== file.key) this.diffScroll.scroll_to_item(0);
      this.setRows(lines); this.cut = cut; this.shows = file.key;
    } catch (e) {
      if (gen === this.gen && this.open === file.path) { this.setRows([]); this.shows = file.key; this.note = `Cannot show this diff: ${e?.message ?? e}`; }
    } finally { this.diffBusy = false; }
  }

  // this.shows: the key of the file the rows are for (null: none yet).
  // The open file without its diff (a load that lost a race, or one skipped
  // while hidden) loads it now.
  healDiff(cx) {
    const file = this.open && this.files.find((f) => f.path === this.open);
    if (!file || this.shows === file.key || !this.shown()) return;
    const gen = this.gen;
    cx.spawn(async (cx) => { await this.loadDiff(file, gen); cx.notify(); });
  }

  setRows(lines) {
    this.rows = diffRows(lines); this.note = null; this.cut = false; this.shows = null;
    this.diffWidth = Math.max(320, ...this.rows.map((r) => r.text.length * 6.7 + 130));
    this.mapThreads();
  }

  // Which diff rows carry review threads (the open file's, not outdated).
  mapThreads() {
    this.rowThreads = new Map();
    const mine = this.threads.filter((th) => th.path === this.open && th.line != null && !th.outdated);
    this.rows.forEach((row, i) => {
      const here = mine.filter((th) => (th.side === "LEFT" ? row.old === th.line && row.kind !== "+" : row.new === th.line && row.kind !== "-"));
      if (here.length) this.rowThreads.set(i, here);
    });
  }

  // ---- actions

  pick(path, cx) {
    this.open = this.open === path ? null : path; this.closed = !this.open; this.drawer = null;
    this.setRows([]);
    const file = this.files.find((f) => f.path === path), gen = this.gen;
    if (this.open && file) { this.diffBusy = true; cx.spawn(async (cx) => { await this.loadDiff(file, gen); cx.notify(); }); }
    cx.notify();
  }

  step(dir, cx) {
    if (!this.files.length) return;
    const i = this.files.findIndex((f) => f.path === this.open);
    const next = this.files[(i < 0 ? 0 : i + dir + this.files.length) % this.files.length];
    this.openFile(next.path, cx);
  }

  openFile(path, cx) {
    if (this.open === path) return;
    this.pick(path, cx);
    const i = this.files.findIndex((f) => f.path === path);
    if (i >= 0) this.fileScroll.scroll_to_item(i, "center");
  }

  isViewed(f) { return this.viewed[f.path] === f.key; }

  toggleViewed(path, cx) {
    const f = this.files.find((x) => x.path === path);
    if (!f || !this.viewedKey) return;
    if (this.isViewed(f)) delete this.viewed[f.path];
    else this.viewed[f.path] = f.key;
    // Marks for files that left the branch go too.
    for (const p of Object.keys(this.viewed)) if (!this.files.some((x) => x.path === p)) delete this.viewed[p];
    store.set(this.viewedKey, this.viewed);
    cx.notify();
  }

  nextUnviewed(cx) {
    const n = this.files.length, i = this.files.findIndex((f) => f.path === this.open);
    for (let k = 1; k <= n; k++) {
      const f = this.files[(Math.max(i, -1) + k + n) % n];
      if (!this.isViewed(f)) { this.openFile(f.path, cx); return; }
    }
  }

  openUrl(url, cx) { if (url) cx.open_url(url); }

  postComment(cx) {
    const body = this.comment.trim(), pr = this.pr?.pr, root = this.root, on = this.on, gen = this.gen;
    if (!body || !pr || this.posting) return;
    this.posting = "comment";
    cx.spawn(async (cx) => {
      try {
        const r = await exec("gh", ["pr", "comment", String(pr.number), "--body", body], { cwd: root, on });
        if (r.code !== 0) throw new Error((r.stderr || r.stdout).trim());
        if (gen === this.gen) { this.comment = ""; this.composer.set_value(""); }
        notify({ title: "Comment posted", body: `#${pr.number}`, level: "success", timeout: 3 });
        this.refresh(cx, true);
      } catch (e) { notify({ title: "Comment not posted", body: String(e?.message ?? e), level: "error" }); }
      finally { this.posting = null; cx.notify(); }
    });
    cx.notify();
  }

  postReply(cx) {
    const body = this.reply.trim(), id = this.drawer?.replyTo, root = this.root, on = this.on, gen = this.gen;
    if (!body || !id || this.posting) return;
    this.posting = "reply";
    cx.spawn(async (cx) => {
      try {
        const r = await gql(root, on, REPLY, { id, body });
        if (r.code !== 0) throw new Error((r.stderr || r.stdout).trim());
        if (gen === this.gen) { this.reply = ""; this.replyBox.set_value(""); }
        await this.reloadThreads(gen);
      } catch (e) { notify({ title: "Reply not posted", body: String(e?.message ?? e), level: "error" }); }
      finally { this.posting = null; cx.notify(); }
    });
    cx.notify();
  }

  resolve(th, cx) {
    const root = this.root, on = this.on, gen = this.gen;
    if (this.posting) return;
    this.posting = th.id;
    cx.spawn(async (cx) => {
      try {
        const r = await gql(root, on, th.resolved ? UNRESOLVE : RESOLVE, { id: th.id });
        if (r.code !== 0) throw new Error((r.stderr || r.stdout).trim());
        await this.reloadThreads(gen);
      } catch (e) { notify({ title: th.resolved ? "Not reopened" : "Not resolved", body: String(e?.message ?? e), level: "error" }); }
      finally { this.posting = null; cx.notify(); }
    });
    cx.notify();
  }

  async reloadThreads(gen) {
    const list = await threads(this.root, this.on, this.pr?.pr).catch(() => null);
    if (gen === this.gen && list) { this.threads = list; this.mapThreads(); }
  }

  openThreads(title, list, cx) {
    if (!list.length) return;
    this.drawer = { title, ids: list.map((th) => th.id), replyTo: list[list.length - 1].id };
    cx.notify();
  }

  showLog(c, cx) {
    if (this.log?.job === c.job && this.log?.name === c.name) { this.log = null; cx.notify(); return; }
    if (!c.job) { this.openUrl(c.link, cx); return; }
    const root = this.root, on = this.on, gen = this.gen;
    this.log = { name: c.name, job: c.job, lines: [], loading: true };
    cx.spawn(async (cx) => {
      let lines;
      try {
        const r = await exec("gh", ["run", "view", "--job", c.job, "--log-failed"], { cwd: root, on });
        lines = r.code === 0 ? logTail(r.stdout) : [(r.stderr || "gh could not read this log").trim()];
        if (!lines.length) lines = ["No failed steps in this log."];
      } catch (e) { lines = [String(e?.message ?? e)]; }
      if (gen === this.gen && this.log?.job === c.job) {
        this.log = { ...this.log, lines, loading: false };
        this.logScroll.scroll_to_bottom();
      }
      cx.notify();
    });
    cx.notify();
  }

  rerunFailed(cx) {
    const runs = [...new Set((this.checks ?? []).filter((c) => bucketOf(c) === "fail" && c.run).map((c) => c.run))];
    const root = this.root, on = this.on;
    if (!runs.length || this.rerunning) return;
    this.rerunning = true;
    cx.spawn(async (cx) => {
      const failed = [];
      for (const run of runs) {
        const r = await exec("gh", ["run", "rerun", run, "--failed"], { cwd: root, on }).catch((e) => ({ code: 1, stderr: String(e) }));
        if (r.code !== 0) failed.push((r.stderr || "").trim().split("\n")[0]);
      }
      notify(failed.length
        ? { title: "Re-run failed", body: failed[0], level: "error" }
        : { title: `Re-running ${runs.length} workflow run${runs.length > 1 ? "s" : ""}`, level: "success", timeout: 3 });
      this.rerunning = false;
      this.refreshChecks(cx);
      cx.notify();
    });
    cx.notify();
  }

  command(name, cx) {
    const c = String(name).replace(/^ship-it-review[.:]/, "");
    if (c === "overview" || c === "files" || c === "checks") this.tab = c;
    else if (c === "refresh") this.refresh(cx, true);
    else if (c.startsWith("file:")) { this.tab = "files"; this.openFile(c.slice(5), cx); }
    else if (c === "next" || c === "prev") { this.tab = "files"; this.step(c === "next" ? 1 : -1, cx); }
    else if (c === "next-unviewed") { this.tab = "files"; this.nextUnviewed(cx); }
    else if (c === "open-file") this.openLocal(this.files.find((f) => f.path === this.open));
    else if (c === "threads") {
      const mine = this.threads.filter((th) => th.path === this.open);
      this.tab = "files"; this.openThreads(this.open?.split("/").pop() ?? "", mine, cx);
    } else if (c === "log") {
      const failed = this.sortedChecks().find((x) => bucketOf(x) === "fail");
      this.tab = "checks"; if (failed) this.showLog(failed, cx);
    }
  }

  key(e, cx) {
    if (this.typing) {
      if (e.key === "escape") { this.handle.focus(); this.typing = null; cx.stop_propagation(); cx.notify(); }
      return;
    }
    const k = e.key, mods = e.modifiers ?? {};
    if (mods.control || mods.platform || mods.alt) return;
    if (k === "1" || k === "2" || k === "3") { this.tab = TABS[+k - 1][0]; cx.notify(); }
    else if (k === "r") this.refresh(cx, true);
    else if (k === "o") this.openUrl(this.pr?.pr?.url, cx);
    else if (k === "escape" && (this.drawer || this.log)) { this.drawer = null; this.log = null; cx.notify(); }
    else if (this.tab === "files") {
      if (k === "j" || k === "down") this.step(1, cx);
      else if (k === "k" || k === "up") this.step(-1, cx);
      else if (k === "v" && this.open) this.toggleViewed(this.open, cx);
      else if (k === "n") this.nextUnviewed(cx);
      else if (k === "e") this.openLocal(this.files.find((f) => f.path === this.open));
      else return;
    } else if (this.tab === "checks") {
      const list = this.sortedChecks();
      if (!list.length) return;
      if (k === "j" || k === "down") this.checkIndex = Math.min(list.length - 1, this.checkIndex + 1);
      else if (k === "k" || k === "up") this.checkIndex = Math.max(0, this.checkIndex - 1);
      else if (k === "enter" && list[this.checkIndex]) {
        const c = list[this.checkIndex];
        if (bucketOf(c) === "fail") this.showLog(c, cx); else this.openUrl(c.link, cx);
      } else return;
      cx.notify();
    } else return;
    cx.stop_propagation();
  }

  sortedChecks() {
    const order = Object.fromEntries(BUCKETS.map((b, i) => [b[0], i]));
    return [...(this.checks ?? [])].sort((a, b) => order[bucketOf(a)] - order[bucketOf(b)] || a.name.localeCompare(b.name));
  }

  // ---- drawing helpers

  icon(name, color, size = 14) { return svg(ICON(name)).size(size).flex_none().text_color(color); }

  iconButton(id, t, icon, tip, onClick, { spin = false, disabled = false } = {}) {
    return div().id(id).size(26).flex_none().flex().items_center().justify_center().rounded(6)
      .when(!disabled, (e) => e.cursor_pointer().hover((s) => s.bg(t.hover)).on_click(onClick))
      .tooltip(tip)
      .child(svg(ICON(icon)).size(14).text_color(disabled ? t.dim : t.muted).when(spin, (e) => e.spin(900)));
  }

  button(id, t, label, onClick, { icon, primary = false, disabled = false, tip } = {}) {
    const bg = primary && !disabled ? t.solid : t.background, fg = disabled ? t.dim : primary ? t.solid_foreground : t.foreground;
    return h_flex().id(id).h(28).px(10).gap(6).flex_none().items_center().rounded(6).text_size(12).font_medium()
      .bg(bg).text_color(fg).when(!primary || disabled, (e) => e.border_1().border_color(t.border))
      .when(!disabled, (e) => e.cursor_pointer().hover((s) => s.opacity(0.88)).on_click(onClick))
      .when(Boolean(tip), (e) => e.tooltip(tip))
      .when(Boolean(icon), (e) => e.child(this.icon(icon, fg, 13)))
      .child(label);
  }

  pill(text, color, t, { filled = false } = {}) {
    return div().h(20).px(8).flex_none().flex().items_center().rounded(10).text_size(11).font_medium().whitespace_nowrap()
      .text_color(color).when(filled, (e) => e.bg(color + "22")).when(!filled, (e) => e.border_1().border_color(t.border))
      .child(text);
  }

  empty(t, icon, title, body, action) {
    return v_flex().flex_1().min_h(0).items_center().justify_center().gap(10).p(24)
      .child(this.icon(icon, t.dim, 28))
      .child(div().text_size(14).font_semibold().text_color(t.foreground).child(title))
      .when(Boolean(body), (e) => e.child(div().max_w(380).text_center().text_size(12).text_color(t.muted).child(body)))
      .when(Boolean(action), (e) => e.child(div().mt(6).child(action)));
  }

  markdown(id, text, t) {
    return TextView.markdown(id, text.replace(/<!--[\s\S]*?-->/g, "").trim()).selectable(true).scrollable(false)
      .w_full().text_size(13).text_color(t.foreground);
  }

  // ---- header and footer

  header(t) {
    const pr = this.pr?.kind === "ok" ? this.pr.pr : null, files = this.files.length || (this.filesStale ? pr?.changedFiles ?? 0 : 0), c = tally(this.checks);
    const badge = (text, color) => div().h(18).min_w(18).px(5).flex().items_center().justify_center().rounded(9).bg(t.raised).text_size(10.5).font_medium().text_color(color).child(text);
    const extra = {
      files: files ? badge(this.limited ? `${MAX_FILES}+` : String(files), t.muted) : null,
      checks: c.fail + c.cancel ? badge(String(c.fail + c.cancel), t.ansi1) : c.pending ? badge(String(c.pending), t.ansi3) : c.pass ? h_flex().child(this.icon("check", t.ansi2, 12)) : null,
      overview: pr && (pr.comments?.length || 0) + (pr.reviews?.length || 0) ? badge(String((pr.comments?.length || 0) + (pr.reviews?.length || 0)), t.muted) : null,
    };
    return h_flex().h(42).flex_none().pl(6).pr(8).gap(2).items_center().border_b(1).border_color(t.border).bg(t.chrome)
      .children(TABS.map(([id, label]) => {
        const on = this.tab === id;
        return h_flex().id(`tab-${id}`).h_full().px(10).gap(6).items_center().relative().cursor_pointer()
          .text_size(12.5).font_medium().text_color(on ? t.foreground : t.muted).hover((s) => s.text_color(t.foreground))
          .on_click((_e, cx) => { this.tab = id; cx.notify(); })
          .child(label).when(Boolean(extra[id]), (e) => e.child(extra[id]))
          .when(on, (e) => e.child(div().absolute().bottom(0).left(8).right(8).h(2).rounded(1).bg(t.accent)));
      }))
      .child(div().flex_1().min_w(8))
      .when(Boolean(this.git) && this.width > 520, (e) => e.child(h_flex().min_w(0).gap(5).items_center().text_size(11.5).text_color(t.muted)
        .child(this.icon("git-branch", t.dim, 12))
        .child(div().min_w(0).truncate().child(this.git.branch ?? this.git.sha ?? ""))
        .when(Boolean(this.base), (e) => e.child(div().text_color(t.dim).child("→")).child(div().flex_none().child(this.base.replace(/^origin\//, ""))))))
      .child(div().w(6))
      .child(this.iconButton("refresh", t, "refresh-cw", "Refresh (r)", (_e, cx) => this.refresh(cx, true), { spin: this.loading }))
      .when(Boolean(pr), (e) => e.child(this.iconButton("open-pr", t, "external-link", "Open on GitHub (o)", (_e, cx) => this.openUrl(pr.url, cx))));
  }

  footer(t) {
    const hints = {
      overview: ["1 2 3 tabs", "r refresh", "o open on GitHub", "⌘↵ comment"],
      files: ["j/k files", "v viewed", "n next unviewed", "e open file", "r refresh"],
      checks: ["j/k checks", "↵ log", "r refresh", "o open on GitHub"],
    }[this.tab];
    return h_flex().h(28).flex_none().px(12).gap(14).items_center().border_t(1).border_color(t.border).bg(t.chrome)
      .text_size(11).text_color(t.dim).children(hints.map((h) => div().whitespace_nowrap().child(h)));
  }

  // ---- Overview

  overview(t) {
    const p = this.pr;
    if (!p) return this.empty(t, "loader", this.error ?? "Loading pull request…", null);
    if (p.kind === "unavailable") return this.empty(t, "git-pull-request", "GitHub is not reachable", `${p.reason}. Files still work.`);
    if (p.kind === "none") {
      const branch = this.git?.branch ?? "this branch";
      return this.empty(t, "git-pull-request", `No pull request for ${branch}`, "Push the branch and open one to get a description, reviews and checks here.",
        this.button("create", t, "Create pull request", () => exec("gh", ["pr", "create", "--web"], { cwd: this.root, on: this.on }), { icon: "git-pull-request", primary: true }));
    }
    const pr = p.pr, look = prLook(pr), color = t[look.color] ?? t.muted, review = reviewLook(pr.reviewDecision), c = tally(this.checks);
    const people = (pr.reviewRequests ?? []).map((r) => r.login ?? r.name ?? r.slug).filter(Boolean);
    const merge = { CLEAN: ["Ready to merge", t.ansi2], BLOCKED: ["Merge blocked", t.ansi3], BEHIND: ["Behind base", t.ansi3], DIRTY: ["Has conflicts", t.ansi1], UNSTABLE: ["Checks failing", t.ansi1], DRAFT: ["Draft", t.muted], HAS_HOOKS: ["Ready to merge", t.ansi2] }[pr.mergeStateStatus];

    const facts = h_flex().flex_wrap().gap(6).items_center()
      .when(Boolean(this.checks?.length), (e) => e.child(h_flex().id("ov-checks").h(24).px(8).gap(8).items_center().rounded(6).border_1().border_color(t.border).cursor_pointer().hover((s) => s.bg(t.hover))
        .on_click((_e, cx) => { this.tab = "checks"; cx.notify(); }).tooltip("Show checks")
        .when(c.pass > 0, (e) => e.child(h_flex().gap(4).items_center().text_size(11.5).text_color(t.ansi2).child(this.icon("circle-check", t.ansi2, 12)).child(String(c.pass))))
        .when(c.fail + c.cancel > 0, (e) => e.child(h_flex().gap(4).items_center().text_size(11.5).text_color(t.ansi1).child(this.icon("circle-x", t.ansi1, 12)).child(String(c.fail + c.cancel))))
        .when(c.pending > 0, (e) => e.child(h_flex().gap(4).items_center().text_size(11.5).text_color(t.ansi3).child(this.icon("circle-dot", t.ansi3, 12)).child(String(c.pending))))))
      .when(Boolean(review), (e) => e.child(this.pill(review.label, t[review.color] ?? t.muted, t)))
      .when(Boolean(merge), (e) => e.child(this.pill(merge[0], merge[1], t)))
      .children((pr.labels ?? []).map((l) => this.pill(l.name, l.color ? `#${l.color}` : t.muted, t, { filled: true })))
      .when(people.length > 0, (e) => e.child(div().text_size(11.5).text_color(t.muted).child(`Waiting on ${people.join(", ")}`)));

    const items = [
      ...(pr.comments ?? []).map((x) => ({ kind: "comment", who: x.author?.login ?? "ghost", at: x.createdAt, body: x.body, url: x.url })),
      ...(pr.reviews ?? []).map((x) => ({ kind: "review", who: x.author?.login ?? "ghost", at: x.submittedAt, body: x.body, state: x.state })),
    ].sort((a, b) => Date.parse(a.at) - Date.parse(b.at));

    // One centred reading column, as wide as a GitHub conversation.
    const body = v_flex().id("overview").flex_1().min_h(0).overflow_y_scrollbar().child(h_flex().w_full().justify_center().child(v_flex().flex_1().min_w(0).max_w(860).px(20).py(18).gap(16)
      // Title
      .child(v_flex().gap(8)
        .child(h_flex().gap(8).items_center()
          .child(h_flex().h(22).px(8).gap(5).flex_none().items_center().rounded(11).bg(color + "22").text_size(11.5).font_semibold().text_color(color)
            .child(this.icon(look.icon, color, 12)).child(look.label))
          .child(h_flex().id("pr-number").gap(4).items_center().px(4).rounded(4).cursor_pointer().text_size(12).text_color(t.dim)
            .hover((s) => s.text_color(t.accent)).tooltip("Copy link")
            .on_click((_e, cx) => { cx.write_to_clipboard(pr.url); notify({ title: `#${pr.number} link copied`, body: pr.url, level: "info", timeout: 2 }); })
            .child(`#${pr.number}`).child(this.icon("copy", t.dim, 11))))
        .child(div().text_size(17).font_semibold().line_height(1.3).text_color(t.foreground).child(pr.title))
        .child(h_flex().flex_wrap().gap(5).items_center().text_size(12).text_color(t.muted)
          .child(div().font_medium().text_color(t.foreground).child(pr.author?.login ?? ""))
          .child("wants to merge")
          .child(this.branchChip(pr.headRefName, t)).child("into").child(this.branchChip(pr.baseRefName, t))
          .child(div().text_color(t.dim).child(`· opened ${ago(pr.createdAt)} ago`)))
        .child(h_flex().gap(10).items_center().text_size(12)
          .child(div().text_color(t.muted).child(`${pr.changedFiles} files`))
          .child(div().text_color(t.ansi2).child(`+${pr.additions}`))
          .child(div().text_color(t.ansi1).child(`−${pr.deletions}`)))
        .child(facts))
      .when(pr.mergeable === "CONFLICTING" || pr.mergeStateStatus === "DIRTY", (e) => e.child(this.conflictCard(t, pr)))
      .when(this.threads.some((th) => !th.resolved), (e) => e.child(this.openThreadsCard(t)))
      // Description
      .child(this.card(t, pr.author?.login ?? "", "wrote", pr.createdAt,
        pr.body?.trim() ? this.markdown("pr-body", pr.body, t) : div().text_size(12.5).italic().text_color(t.dim).child("No description.")))
      // Conversation
      .when(items.length > 0, (e) => e.child(h_flex().gap(8).items_center().pt(4)
        .child(div().text_size(11).font_semibold().text_color(t.muted).child("CONVERSATION"))
        .child(div().h(1).flex_1().bg(t.border))))
      .children(items.map((x, i) => this.event(x, i, t)))));

    return v_flex().flex_1().min_h(0).child(body).child(this.composerBar(t, pr));
  }

  // The strip is on another repo: switch to it, or stay.
  offerBar(t) {
    const o = this.offer;
    return h_flex().h(36).flex_none().px(12).gap(8).items_center().bg(t.accent + "1a").border_b(1).border_color(t.border).text_size(12)
      .child(this.icon("git-branch", t.accent, 13))
      .child(div().flex_1().min_w(0).truncate().text_color(t.foreground).child(`The strip is on ${tilde(o.root)}`))
      .child(this.button("offer-switch", t, "Switch", (_e, cx) => { this.reset(o.root, o.on ?? null); if (o.tab) this.tab = o.tab; this.refresh(cx); cx.notify(); }, { primary: true }))
      .child(this.iconButton("offer-dismiss", t, "x", "Stay on this repo", (_e, cx) => { this.offer = null; cx.notify(); }));
  }

  conflictCard(t, pr) {
    const files = this.conflicts, base = pr.baseRefName;
    const details = () => [
      `#${pr.number} ${pr.title}`,
      `${pr.headRefName} conflicts with ${base}${files?.length ? ` in ${files.length} file${files.length > 1 ? "s" : ""}:` : "."}`,
      ...(files ?? []).map((f) => `  ${f}`),
      "",
      "To resolve:",
      "  git fetch origin",
      `  git merge origin/${base}`,
      "  # fix the files above, then",
      "  git add <files> && git commit && git push",
    ].join("\n");
    return v_flex().w_full().rounded(8).border_1().border_color(t.ansi1 + "66").overflow_hidden()
      .child(h_flex().h(36).px(12).gap(8).items_center().bg(t.ansi1 + "14")
        .child(this.icon("git-merge", t.ansi1, 14))
        .child(div().text_size(12.5).font_semibold().text_color(t.foreground).child(`Conflicts with ${base}`))
        .child(div().text_size(12).text_color(t.muted).child(files?.length ? `${files.length} file${files.length > 1 ? "s" : ""}` : files ? "" : "GitHub reports conflicts"))
        .child(div().flex_1())
        .child(this.button("copy-conflicts", t, "Copy details", (_e, cx) => { cx.write_to_clipboard(details()); notify({ title: "Conflict details copied", level: "info", timeout: 2 }); }, { icon: "copy" })))
      .when(Boolean(files?.length), (e) => e.child(v_flex().px(12).py(8).gap(2).bg(t.background).font_family(settings().font_family ?? "JetBrains Mono").text_size(11.5)
        .children(files.map((f, i) => h_flex().id(`conflict-${i}`).h(22).px(6).gap(8).items_center().rounded(4).cursor_pointer().hover((s) => s.bg(t.hover))
          .on_click((_e, cx) => { this.tab = "files"; this.openFile(f, cx); cx.notify(); })
          .child(div().text_color(t.ansi1).child("U")).child(div().min_w(0).truncate().text_color(t.foreground).child(f))))))
      .child(div().px(12).py(8).border_t(1).border_color(t.border).text_size(11.5).text_color(t.muted)
        .child(`Merge or rebase origin/${base} locally to resolve. Compared with your last fetch of ${base}.`));
  }

  // Unresolved review threads, newest first; a click opens the file with the thread.
  openThreadsCard(t) {
    const open = this.threads.filter((th) => !th.resolved)
      .sort((a, b) => Date.parse(b.comments[b.comments.length - 1]?.createdAt ?? 0) - Date.parse(a.comments[a.comments.length - 1]?.createdAt ?? 0));
    return v_flex().w_full().rounded(8).border_1().border_color(t.accent + "55").overflow_hidden()
      .child(h_flex().h(36).px(12).gap(8).items_center().bg(t.accent + "12")
        .child(this.icon("message-square", t.accent, 14))
        .child(div().text_size(12.5).font_semibold().text_color(t.foreground).child("Open threads"))
        .child(div().text_size(12).text_color(t.muted).child(String(open.length))))
      .children(open.map((th, i) => {
        const first = th.comments[0], last = th.comments[th.comments.length - 1];
        const text = (first?.body ?? "").replace(/<!--[\s\S]*?-->/g, "").replace(/[#*_`>]/g, "").replace(/\s+/g, " ").trim();
        return v_flex().id(`open-thread-${i}`).px(12).py(8).gap(3).border_t(1).border_color(t.border).bg(t.background).cursor_pointer().hover((s) => s.bg(t.hover))
          .on_click((_e, cx) => { this.tab = "files"; this.openFile(th.path, cx); this.openThreads(`${th.path.split("/").pop()}${th.line ? `:${th.line}` : ""}`, [th], cx); })
          .child(h_flex().gap(8).items_center().text_size(11.5)
            .child(div().min_w(0).truncate().font_family(settings().font_family ?? "JetBrains Mono").text_color(t.foreground).child(`${th.path}${th.line ? `:${th.line}` : ""}`))
            .when(th.outdated, (e) => e.child(this.pill("Outdated", t.ansi3, t)))
            .child(div().flex_1())
            .child(div().flex_none().text_color(t.dim).child(`${th.comments.length} · ${ago(last?.createdAt)} ago`)))
          .child(h_flex().gap(6).text_size(12).min_w(0)
            .child(div().flex_none().font_medium().text_color(t.muted).child(first?.author ?? ""))
            .child(div().min_w(0).truncate().text_color(t.foreground).child(text || "…")));
      }));
  }

  // A branch name; a click copies it.
  branchChip(name, t) {
    return div().id(`branch-${name}`).h(20).px(6).flex().items_center().rounded(4).bg(t.raised).cursor_pointer().hover((s) => s.bg(t.hover)).tooltip("Copy the branch name")
      .font_family(settings().font_family ?? "JetBrains Mono").text_size(11).text_color(t.foreground).child(name ?? "")
      .on_click((_e, cx) => { if (!name) return; cx.write_to_clipboard(name); notify({ title: "Branch copied", body: name, level: "info", timeout: 2 }); });
  }

  card(t, who, verb, at, content, accent) {
    return v_flex().w_full().rounded(8).border_1().border_color(accent ?? t.border).overflow_hidden()
      .child(h_flex().h(34).px(12).gap(6).items_center().bg(t.raised).border_b(1).border_color(t.border).text_size(12)
        .child(div().font_semibold().text_color(t.foreground).child(who))
        .child(div().text_color(t.muted).child(verb))
        .child(div().flex_1())
        .child(div().text_color(t.dim).child(at ? `${ago(at)} ago` : "")))
      .child(div().w_full().px(14).py(12).bg(t.background).child(content));
  }

  event(x, i, t) {
    if (x.kind === "review") {
      const verb = { APPROVED: "approved", CHANGES_REQUESTED: "requested changes", DISMISSED: "review dismissed", COMMENTED: "reviewed", PENDING: "has a pending review" }[x.state] ?? "reviewed";
      const tint = x.state === "APPROVED" ? t.ansi2 : x.state === "CHANGES_REQUESTED" ? t.ansi1 : null;
      if (!x.body?.trim()) {
        return h_flex().h(30).px(4).gap(8).items_center().text_size(12)
          .child(this.icon(x.state === "APPROVED" ? "circle-check" : x.state === "CHANGES_REQUESTED" ? "circle-x" : "message-square", tint ?? t.dim, 14))
          .child(div().font_semibold().text_color(t.foreground).child(x.who)).child(div().text_color(t.muted).child(verb))
          .child(div().text_color(t.dim).child(`${ago(x.at)} ago`));
      }
      return this.card(t, x.who, verb, x.at, this.markdown(`ev-${i}`, x.body, t), tint ? tint + "66" : null);
    }
    return this.card(t, x.who, "commented", x.at, this.markdown(`ev-${i}`, x.body ?? "", t));
  }

  composerBar(t, pr) {
    const enabled = Boolean(this.comment.trim()) && !this.posting;
    return h_flex().flex_none().justify_center().border_t(1).border_color(t.border).bg(t.chrome).child(h_flex().flex_1().min_w(0).max_w(860).px(20).py(10).gap(8).items_end()
      .child(div().id("composer").flex_1().min_w(0).px(10).py(6).rounded(8).bg(t.background).border_1().border_color(this.typing === "comment" ? t.accent : t.input ?? t.border)
        .cursor_text().on_mouse_down("left", (_e, cx) => cx.stop_propagation())
        .child(Textarea.new(this.composer).w_full().text_size(12.5).text_color(t.foreground)))
      .child(this.button("post-comment", t, this.posting === "comment" ? "Posting…" : "Comment", (_e, cx) => this.postComment(cx),
        { icon: "send", primary: true, disabled: !enabled, tip: `Comment on #${pr.number} (⌘↵)` })));
  }

  // ---- Files

  filesTab(t) {
    if (!this.files.length) {
      if (this.error) return this.empty(t, "file-diff", "Cannot list changes", this.error);
      if (!this.loaded || this.loading) return this.empty(t, "loader", "Reading the branch…", null);
      return this.empty(t, "file-diff", "No changes on this branch", this.base ? `Nothing differs from ${this.base}.` : null);
    }
    const add = this.files.reduce((n, f) => n + f.add, 0), del = this.files.reduce((n, f) => n + f.del, 0);
    const viewed = this.files.filter((f) => this.isViewed(f)).length;
    // The thread drawer takes the list's room before the diff's.
    const listH = Math.min(this.drawer ? 92 : 240, this.files.length * 28 + 8);
    const summary = h_flex().h(34).flex_none().px(14).gap(10).items_center().border_b(1).border_color(t.border).text_size(12)
      .child(div().font_medium().text_color(t.foreground).child(`${this.files.length}${this.limited ? "+" : ""} files`))
      .child(div().text_color(t.ansi2).child(`+${add}`)).child(div().text_color(t.ansi1).child(`−${del}`))
      .child(div().flex_1())
      .child(h_flex().gap(8).items_center()
        .child(div().w(80).h(4).rounded(2).bg(t.raised).child(div().h_full().rounded(2).bg(t.ansi2).w(Math.round(80 * viewed / this.files.length))))
        .child(div().text_color(viewed === this.files.length ? t.ansi2 : t.muted).child(`${viewed} / ${this.files.length} viewed`)));

    const list = div().id("file-list").h(listH).flex_none().relative().border_b(1).border_color(t.border)
      .child(v_virtual_list("files", this.files.length, 28, (i) => this.files[i].path,
        (range) => this.files.slice(range.start, range.end).map((f) => this.fileRow(f, t))).track_scroll(this.fileScroll).size_full().py(4)
        .on_item_click((path, cx) => { this.pick(path, cx); this.handle.focus(); }))
      .child(Scrollbar.vertical("files").viewport_from_layout().absolute().inset_0());

    const file = this.files.find((f) => f.path === this.open);
    return v_flex().flex_1().min_h(0).child(summary).child(list)
      .child(file ? this.fileHeader(file, t) : div())
      .child(this.diff(t, file))
      .when(Boolean(this.drawer), (e) => e.child(this.threadDrawer(t)));
  }

  fileRow(f, t) {
    const parts = f.path.split("/"), name = parts.pop(), seen = this.isViewed(f), sel = this.open === f.path;
    const count = this.threads.filter((th) => th.path === f.path && !th.resolved).length;
    return h_flex().h(28).mx(6).px(8).gap(8).items_center().rounded(6).cursor_pointer()
      .when(sel, (e) => e.bg(t.selected)).when(!sel, (e) => e.hover((s) => s.bg(t.hover)))
      .child(div().w(12).flex_none().text_size(11).font_semibold().text_color(t[STATUS[f.status]] ?? t.muted).child(f.status))
      .child(h_flex().flex_1().min_w(0).text_size(12).when(seen, (e) => e.opacity(0.5))
        .child(div().min_w(0).flex_shrink_1().text_color(t.dim).truncate().child(parts.length ? parts.join("/") + "/" : ""))
        .child(div().flex_none().max_w(300).truncate().text_color(t.foreground).child(name)))
      .when(f.dirty, (e) => e.child(div().size(6).flex_none().rounded_full().bg(t.ansi3)))
      .when(count > 0, (e) => e.child(h_flex().gap(3).items_center().text_size(11).text_color(t.accent).child(this.icon("message-square", t.accent, 11)).child(String(count))))
      .when(f.add > 0, (e) => e.child(div().text_size(11).text_color(t.ansi2).child(`+${f.add}`)))
      .when(f.del > 0, (e) => e.child(div().text_size(11).text_color(t.ansi1).child(`−${f.del}`)))
      .child(this.icon(seen ? "square-check" : "square", seen ? t.ansi2 : t.dim, 14));
  }

  // The file as it is in this worktree, whole and read-only, in a pane: this
  // tab's file pane if it has one, else a new one to the right of this pane.
  openLocal(f) {
    const at = focused();
    if (!this.root || !f || f.status === "D" || !at) return;
    setShared("ship-it.file", { root: this.root, on: this.on ?? null, path: f.path, at: Date.now() });
    const existing = panes().find((p) => p.mod === "ship-it-file" && p.tab === at.tab);
    if (existing) { run("pane.focus", { pane: existing.pane }); return; }
    const own = panes().find((p) => p.pane === at.pane && p.tab === at.tab);
    const from = own?.pane ?? panes().find((p) => p.tab === at.tab)?.pane;
    run("pane.split", { direction: "right", ...(from ? { pane: from } : {}), mod: "ship-it-file", props: { root: this.root, on: this.on ?? null, path: f.path } });
  }

  fileHeader(f, t) {
    const seen = this.isViewed(f), parts = f.path.split("/"), name = parts.pop();
    const mine = this.threads.filter((th) => th.path === f.path);
    const open = mine.filter((th) => !th.resolved).length;
    return h_flex().h(36).flex_none().px(12).gap(8).items_center().border_b(1).border_color(t.border).bg(t.raised).text_size(12)
      .child(div().text_size(11).font_semibold().text_color(t[STATUS[f.status]] ?? t.muted).child(f.status))
      .child(h_flex().flex_1().min_w(0)
        .child(div().min_w(0).flex_shrink_1().truncate().text_color(t.muted).child(parts.length ? parts.join("/") + "/" : ""))
        .child(div().flex_none().font_semibold().text_color(t.foreground).child(name)))
      .when(f.dirty, (e) => e.child(div().text_size(11).text_color(t.ansi3).whitespace_nowrap().child("● uncommitted")))
      .when(mine.length > 0, (e) => e.child(h_flex().id("file-threads").h(24).px(8).gap(5).items_center().rounded(6).cursor_pointer().hover((s) => s.bg(t.hover))
        .text_size(11.5).text_color(open ? t.accent : t.muted)
        .on_click((_e, cx) => this.openThreads(name, mine, cx))
        .child(this.icon("message-square", open ? t.accent : t.muted, 12))
        .child(`${mine.length} thread${mine.length > 1 ? "s" : ""}`)))
      .when(f.status !== "D", (e) => e.child(h_flex().id("open-local").h(24).px(8).gap(6).items_center().rounded(6).cursor_pointer().border_1()
        .border_color(t.border).bg(t.background).hover((s) => s.bg(t.hover)).text_size(11.5).text_color(t.muted)
        .on_click((_e, cx) => this.openLocal(f)).tooltip(`Open ${f.path} from this worktree (e)`)
        .child(this.icon("external-link", t.muted, 12)).child("Open")))
      .child(h_flex().id("viewed").h(24).px(8).gap(6).items_center().rounded(6).cursor_pointer().border_1()
        .border_color(seen ? t.ansi2 + "88" : t.border).bg(seen ? t.ansi2 + "18" : t.background).hover((s) => s.bg(t.hover))
        .text_size(11.5).text_color(seen ? t.ansi2 : t.muted)
        .on_click((_e, cx) => this.toggleViewed(f.path, cx)).tooltip("Mark viewed (v)")
        .child(this.icon(seen ? "square-check" : "square", seen ? t.ansi2 : t.muted, 13)).child("Viewed"));
  }

  diff(t, file) {
    const mono = settings().font_family ?? "JetBrains Mono";
    return div().flex_1().min_h(0).relative().bg(t.background).font_family(mono).text_size(11.5)
      .child(div().id("diff-x").size_full().overflow_x_scrollbar()
        .child(div().w_full().min_w(this.diffWidth).h_full()
          .child(v_virtual_list("diff", this.rows.length, 20, (i) => String(i),
            (range) => this.rows.slice(range.start, range.end).map((row, k) => this.diffRow(row, range.start + k, t))).track_scroll(this.diffScroll).size_full()
            .on_item_click((key, cx) => {
              const list = this.rowThreads.get(Number(key));
              if (list) this.openThreads(`${this.open.split("/").pop()}:${list[0].line}`, list, cx);
            }))))
      .child(Scrollbar.vertical("diff").viewport_from_layout().absolute().inset_0())
      .when(!file, (e) => e.child(div().absolute().top(10).left(14).font_family(settings().ui_font_family ?? "Geist").text_size(12).text_color(t.dim).child("Select a file to see its changes")))
      .when(Boolean(this.note), (e) => e.child(div().absolute().top(10).left(14).text_size(11.5).text_color(t.ansi1).child(this.note)))
      .when(this.cut, (e) => e.child(div().absolute().bottom(6).right(14).px(8).py(2).rounded(4).bg(t.raised).text_size(10.5).text_color(t.muted).child("Showing the first 1,500 lines")));
  }

  diffRow(row, i, t) {
    if (row.kind === "@") {
      return h_flex().w_full().h(20).px(12).items_center().bg(t.accent + "12").text_color(t.muted).child(div().truncate().child(row.text));
    }
    const list = this.rowThreads.get(i), active = list && this.drawer?.ids.includes(list[0].id);
    const open = list?.some((th) => !th.resolved);
    const num = (n) => div().w(38).flex_none().pr(8).text_right().text_color(t.dim).child(n === undefined ? "" : String(n));
    return h_flex().w_full().h(20).items_center()
      .when(row.kind === "+", (e) => e.bg(t.ansi2 + "1c")).when(row.kind === "-", (e) => e.bg(t.ansi1 + "1c"))
      .when(Boolean(active), (e) => e.bg(t.accent + "26"))
      .child(h_flex().w(30).h_full().flex_none().items_center().justify_center()
        .when(Boolean(list), (e) => e.child(h_flex().h(16).px(4).gap(2).items_center().rounded(4).bg(open ? t.accent : t.raised).cursor_pointer()
          .text_size(10).text_color(open ? t.accent_foreground : t.muted)
          .child(this.icon("message-square", open ? t.accent_foreground : t.muted, 10)).child(String(list.reduce((n, th) => n + th.comments.length, 0))))))
      .child(num(row.old)).child(num(row.new))
      .child(div().w(14).flex_none().text_color(row.kind === "+" ? t.ansi2 : row.kind === "-" ? t.ansi1 : t.dim).child(row.kind === "+" || row.kind === "-" ? row.kind : ""))
      .child(div().flex_1().whitespace_nowrap().text_color(row.kind === "" ? t.dim : t.foreground).child(row.text));
  }

  threadDrawer(t) {
    const list = this.drawer.ids.map((id) => this.threads.find((th) => th.id === id)).filter(Boolean);
    const enabled = Boolean(this.reply.trim()) && !this.posting;
    const target = list.find((th) => th.id === this.drawer.replyTo);
    return v_flex().h(Math.round((this.height ?? 600) * 0.42)).min_h(180).flex_none().border_t(1).border_color(t.border).bg(t.chrome)
      .child(h_flex().h(34).flex_none().px(12).gap(8).items_center().border_b(1).border_color(t.border)
        .child(this.icon("message-square", t.muted, 13))
        .child(div().text_size(12).font_semibold().text_color(t.foreground).child(this.drawer.title))
        .child(div().text_size(11.5).text_color(t.dim).child(`${list.length} thread${list.length > 1 ? "s" : ""}`))
        .child(div().flex_1())
        .child(this.iconButton("drawer-close", t, "x", "Close (esc)", (_e, cx) => { this.drawer = null; cx.notify(); })))
      .child(v_flex().id("drawer-body").flex_1().min_h(0).overflow_y_scrollbar().p(12).gap(12)
        .children(list.map((th) => v_flex().w_full().rounded(8).border_1().border_color(th.id === this.drawer.replyTo ? t.accent + "88" : t.border).bg(t.background).overflow_hidden()
          .child(h_flex().h(30).px(10).gap(8).items_center().border_b(1).border_color(t.border).text_size(11.5)
            .child(div().text_color(th.resolved ? t.ansi2 : th.outdated ? t.ansi3 : t.muted).child(th.resolved ? "Resolved" : th.outdated ? "Outdated" : `Line ${th.line}`))
            .child(div().flex_1())
            .child(div().id(`reply-${th.id}`).px(6).py(2).rounded(4).cursor_pointer().text_color(t.accent).hover((s) => s.bg(t.hover)).child("Reply")
              .on_click((_e, cx) => { this.drawer.replyTo = th.id; this.replyBox.focus(); cx.notify(); }))
            .child(div().id(`resolve-${th.id}`).px(6).py(2).rounded(4).cursor_pointer().text_color(t.muted).hover((s) => s.bg(t.hover))
              .child(this.posting === th.id ? "…" : th.resolved ? "Reopen" : "Resolve").on_click((_e, cx) => this.resolve(th, cx))))
          .children(th.comments.map((cm, k) => v_flex().px(12).py(10).gap(6).when(k > 0, (e) => e.border_t(1).border_color(t.border))
            .child(h_flex().gap(6).items_center().text_size(11.5)
              .child(div().font_semibold().text_color(t.foreground).child(cm.author))
              .child(div().text_color(t.dim).child(`${ago(cm.createdAt)} ago`)))
            .child(this.markdown(`cm-${cm.id}`, cm.body, t)))))))
      .child(h_flex().flex_none().p(10).gap(8).items_end().border_t(1).border_color(t.border)
        .child(div().id("reply-box").flex_1().min_w(0).px(10).py(6).rounded(8).bg(t.background).border_1().border_color(this.typing === "reply" ? t.accent : t.input ?? t.border)
          .cursor_text().on_mouse_down("left", (_e, cx) => cx.stop_propagation())
          .child(Textarea.new(this.replyBox).w_full().text_size(12.5).text_color(t.foreground)))
        .child(this.button("post-reply", t, this.posting === "reply" ? "Replying…" : "Reply", (_e, cx) => this.postReply(cx),
          { icon: "send", primary: true, disabled: !enabled, tip: target ? `Reply to the thread on line ${target.line ?? "?"} (⌘↵)` : "Reply" })));
  }

  // ---- Checks

  checksTab(t) {
    const p = this.pr;
    if (!p || (p.kind === "ok" && this.checks === null && this.loading)) return this.empty(t, "loader", "Loading checks…", null);
    if (p.kind === "unavailable") return this.empty(t, "circle-dot", "GitHub is not reachable", p.reason);
    if (p.kind === "none") return this.empty(t, "circle-dot", "No checks yet", "Checks run on a pull request. Create one from Overview.");
    const list = this.sortedChecks();
    if (!list.length) return this.empty(t, "circle-check", "No checks on this pull request", null);
    const c = tally(this.checks), failing = list.filter((x) => bucketOf(x) === "fail" && x.run).length;
    const summary = h_flex().h(40).flex_none().px(14).gap(12).items_center().border_b(1).border_color(t.border).text_size(12)
      .child(div().font_medium().text_color(c.fail + c.cancel ? t.ansi1 : c.pending ? t.ansi3 : t.ansi2)
        .child(c.fail + c.cancel ? `${c.fail + c.cancel} failing` : c.pending ? `${c.pending} running` : "All checks passed"))
      .child(div().text_color(t.muted).child([c.pass && `${c.pass} passed`, c.pending && (c.fail + c.cancel) && `${c.pending} pending`, c.skipping && `${c.skipping} skipped`].filter(Boolean).join(" · ")))
      .child(div().flex_1())
      .when(failing > 0, (e) => e.child(this.button("rerun", t, this.rerunning ? "Re-running…" : "Re-run failed", (_e, cx) => this.rerunFailed(cx), { icon: "rotate-ccw", disabled: this.rerunning, tip: "gh run rerun --failed" })));

    let index = 0;
    const rows = v_flex().w_full().py(6);
    for (const [bucket, label, icon, color] of BUCKETS) {
      const group = list.filter((x) => bucketOf(x) === bucket);
      if (!group.length) continue;
      rows.child(h_flex().h(28).px(16).gap(6).items_center().text_size(11).font_semibold().text_color(t.muted)
        .child(label.toUpperCase()).child(div().text_color(t.dim).child(String(group.length))));
      for (const x of group) rows.child(this.checkRow(x, index++, icon, t[color] ?? t.muted, t));
    }
    const listEl = div().id("checks-list").w_full().when(Boolean(this.log), (e) => e.h(Math.min(260, list.length * 34 + 80)).flex_none().border_b(1).border_color(t.border))
      .when(!this.log, (e) => e.flex_1().min_h(0)).overflow_y_scrollbar().child(rows);
    return v_flex().flex_1().min_h(0).child(summary).child(listEl).when(Boolean(this.log), (e) => e.child(this.logView(t)));
  }

  checkRow(x, i, icon, color, t) {
    const sel = this.checkIndex === i || (this.log && this.log.job === x.job && this.log.name === x.name);
    const failed = bucketOf(x) === "fail", pending = bucketOf(x) === "pending";
    const time = x.startedAt && x.completedAt && !x.completedAt.startsWith("0001") ? duration(x.startedAt, x.completedAt) : pending && x.startedAt ? `${ago(x.startedAt)}` : "";
    return h_flex().id(`check-${i}`).h(34).mx(6).px(10).gap(10).items_center().rounded(6).cursor_pointer()
      .when(Boolean(sel), (e) => e.bg(t.selected)).when(!sel, (e) => e.hover((s) => s.bg(t.hover)))
      .on_click((_e, cx) => { this.checkIndex = i; if (failed) this.showLog(x, cx); else this.openUrl(x.link, cx); cx.notify(); })
      .tooltip(failed ? (x.job ? "Show the failed log" : "Open on GitHub") : "Open on GitHub")
      .child(svg(ICON(pending ? "loader" : icon)).size(15).flex_none().text_color(color).when(pending, (e) => e.spin(1200)))
      .child(h_flex().flex_1().min_w(0).gap(8).items_center().text_size(12.5)
        .child(div().min_w(0).truncate().text_color(t.foreground).font_medium().child(x.name))
        .when(Boolean(x.workflow), (e) => e.child(div().flex_none().max_w(220).truncate().text_size(11.5).text_color(t.dim).child(x.workflow))))
      .when(Boolean(x.description) && this.width > 640, (e) => e.child(div().max_w(220).truncate().text_size(11.5).text_color(t.muted).child(x.description)))
      .child(div().w(64).flex_none().text_right().text_size(11.5).text_color(t.dim).child(time))
      .child(div().id(`check-link-${i}`).size(22).flex_none().flex().items_center().justify_center().rounded(5).hover((s) => s.bg(t.raised))
        .on_click((_e, cx) => { cx.stop_propagation(); this.openUrl(x.link, cx); })
        .child(this.icon("external-link", t.dim, 12)));
  }

  logView(t) {
    const lines = this.log.lines, mono = settings().font_family ?? "JetBrains Mono";
    return v_flex().flex_1().min_h(0)
      .child(h_flex().h(34).flex_none().px(12).gap(8).items_center().border_b(1).border_color(t.border).bg(t.raised).text_size(12)
        .child(this.icon("circle-x", t.ansi1, 13))
        .child(div().font_semibold().text_color(t.foreground).child(this.log.name))
        .child(div().text_color(t.dim).child(this.log.loading ? "reading the failed log…" : `last ${lines.length} lines`))
        .child(div().flex_1())
        .child(this.iconButton("log-close", t, "x", "Close (esc)", (_e, cx) => { this.log = null; cx.notify(); })))
      .child(div().flex_1().min_h(0).relative().bg(t.background).font_family(mono).text_size(11)
        .child(div().id("log-x").size_full().overflow_x_scrollbar()
          .child(div().w_full().min_w(Math.max(320, ...lines.map((l) => l.length * 6.5 + 60))).h_full()
            .child(v_virtual_list("log", lines.length, 18, (i) => String(i), (range) => lines.slice(range.start, range.end).map((line, k) => {
              const err = /##\[error\]|\berror\b|FAIL|panic:/i.test(line), group = line.startsWith("##[group]") || line.startsWith("##[endgroup]");
              return h_flex().w_full().h(18).px(12).items_center().when(err, (e) => e.bg(t.ansi1 + "14"))
                .child(div().w(34).flex_none().text_right().pr(10).text_color(t.dim).child(String(range.start + k + 1)))
                .child(div().whitespace_nowrap().text_color(err ? t.ansi1 : group ? t.muted : t.foreground).child(line.replace(/^##\[(error|group|endgroup|warning)\]/, "") || " "));
            })).track_scroll(this.logScroll).size_full())))
        .child(Scrollbar.vertical("log").viewport_from_layout().absolute().inset_0()));
  }

  // ---- root

  render(cx) {
    // The strip says what to show; props are the fallback.
    const target = shared("ship-it.target");
    if (target?.at > this.seen) {
      this.seen = target.at;
      // A pane can't tell whether it is the one the strip meant (props carry
      // no pane id), so another repo is offered, never switched to silently.
      if (!target.root || (target.root === this.root && (target.on ?? null) === this.on)) { if (target.tab) this.tab = target.tab; this.offer = null; }
      else if (this.root && !this.inPanel) this.offer = target;
      else { this.reset(target.root, target.on ?? null); if (target.tab) this.tab = target.tab; this.refresh(cx); }
    }
    const base = this.inPanel ? shared("ship-it.base") : null;
    if (base?.root && (base.root !== this.root || (base.on ?? null) !== this.on)) { this.reset(base.root, base.on ?? null); this.refresh(cx); }
    if (!this.root && props()?.root) { this.reset(props().root, props().on ?? null); this.refresh(cx); }
    // The strip refreshed this branch's PR: take it (its polling is ours too).
    const strip = this.loading ? null : this.stripPr();
    if (strip && strip.at > (this.prAt ?? 0)) this.adopt(strip);
    if (this.stale && this.shown()) this.refresh(cx);
    else if (this.filesStale && this.tab === "files" && !this.loading) this.refreshFiles(cx);
    else if (this.tab === "files" && !this.loading && !this.filesBusy && !this.diffBusy) this.healDiff(cx);
    const t = theme();
    const content = !this.root
      ? this.empty(t, "rocket", "Nothing to review", "Click the pull request on the Ship it strip.")
      : this.tab === "files" ? this.filesTab(t) : this.tab === "checks" ? this.checksTab(t) : this.overview(t);
    return v_flex().id("ship-it-review").size_full().min_h(0).bg(t.background).text_color(t.foreground).text_size(13)
      .track_focus(this.handle).on_key_down((e, cx) => this.key(e, cx))
      .on_mouse_down("left", () => this.handle.focus())
      .on_size_change((size, cx) => {
        if (Math.abs(size.width - this.width) < 1 && Math.abs(size.height - (this.height ?? 0)) < 1) return;
        this.width = size.width; this.height = size.height; cx.notify();
      })
      .child(this.header(t))
      .when(Boolean(this.offer), (e) => e.child(this.offerBar(t)))
      .child(content)
      .child(this.footer(t));
  }
}
