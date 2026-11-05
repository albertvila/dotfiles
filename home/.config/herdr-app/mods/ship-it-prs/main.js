// Pull requests: every open PR in the repo, in the side panel. A row opens to
// its details and actions (worktree, GitHub, copy link); its number copies the
// link; its branch button opens the PR in a worktree space. This branch's PR
// is marked.
//
// Its logic (checks, worktrees, spaces) is in prs.js. data.js is a copy: edit
// mods/ship-it/data.js and run scripts/install.sh.

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { exec, shared, setShared, notify, theme, nextCommand } from "herdr";
import { READ, location, ago, prLook, reviewLook, panelShown, Recent, tilde } from "./data.js";
import { checkState, checkCounts, localBranch, worktrees, addWorktree, places, spaceAt, showSpace, treeLook } from "./prs.js";

const ICON = (name) => `mods/ship-it/icons/${name}.svg`;
const FIELDS = "number,title,author,isDraft,state,url,headRefName,isCrossRepository,labels,baseRefName,reviewDecision,reviewRequests,updatedAt,additions,deletions,statusCheckRollup";
const FILTERS = [["all", "All"], ["mine", "Mine"], ["review", "To review"]];
const SEARCH = { all: "sort:updated-desc", mine: "author:@me sort:updated-desc", review: "review-requested:@me sort:updated-desc" };
const PAGE = 10;
// All open PRs, counted without fetching them (gh fills in {owner} and {repo}).
const TOTAL = "query($owner:String!,$name:String!){repository(owner:$owner,name:$name){pullRequests(states:OPEN){totalCount}}}";

const CHECK = { fail: ["circle-x", "ansi1", "Checks failing"], pending: ["circle-dot", "ansi3", "Checks running"], pass: ["circle-check", "ansi2", "Checks passed"] };

export default class PullRequests extends View {
  init(_p, cx) {
    this.prs = []; this.filter = "all"; this.last = null; this.limit = PAGE; this.trees = {};
    this.expanded = null; // the PR whose details show
    // Last list per folder: switching back shows it at once.
    this.memo = new Recent(12);
    this.refresh(cx);
    cx.timer.every(60000, (cx) => this.refresh(cx));
    cx.spawn(async (cx) => { for (;;) { this.command(await nextCommand(), cx); cx.notify(); } });
  }

  // ship-it-prs.more, .refresh, .all, .mine, .review, .worktree-<n>, .details-<n>: bindable to keys.
  command(name, cx) {
    const c = String(name).replace(/^ship-it-prs[.:]/, ""), n = /^worktree[-:](\d+)$/.exec(c)?.[1];
    if (n) { const pr = this.prs.find((p) => p.number === Number(n)); if (pr) this.worktree(pr, cx); }
    else if (/^details[-:]\d+$/.test(c)) { const d = Number(c.split(/[-:]/)[1]); this.expanded = this.expanded === d ? null : d; }
    else if (c === "more") { if (this.more) this.loadMore(cx); }
    else if (c === "refresh") this.refresh(cx, true);
    else if (SEARCH[c]) this.pick(c, cx);
  }

  key() {
    this.last = location(this.last);
    return JSON.stringify([this.last.cwd, this.last.on]);
  }

  // Hidden, it only notes that it is out of date; showing it catches up.
  shown() { return panelShown("ship-it-prs"); }

  // From render (rendering), the spinner shows in this same render: a notify
  // there is refused ("not allowed during the render phase").
  refresh(cx, force, rendering) {
    if (!this.shown()) { this.stale = true; return; }
    // A load that never came back (its task dropped) blocks for 30 s at most.
    if (this.loading && !force && Date.now() - this.loading < 30000) return;
    const context = this.key(), { cwd, on } = this.last;
    if (context !== this.context) { this.context = context; this.limit = PAGE; this.recall(); }
    if (!cwd) return;
    const filter = this.filter, limit = this.limit, memo = this.memoKey();
    const started = this.loading = Date.now(); this.stale = false;
    if (!rendering) cx.notify();
    cx.spawn(async (cx) => {
      try {
        const top = await exec("git", [...READ, "rev-parse", "--show-toplevel"], { cwd, on });
        if (this.key() !== context) return;
        if (top.code !== 0) { this.error = "Not a git repository"; return; }
        const root = top.stdout.trim();
        // The newest by update, a page at a time; the filters are GitHub searches,
        // so Mine and To review aren't limited to the page already loaded.
        const [list, total, branch, trees] = await Promise.all([
          exec("gh", ["pr", "list", "--state", "open", "--limit", String(limit), "--search", SEARCH[filter], "--json", FIELDS], { cwd: root, on }),
          exec("gh", ["api", "graphql", "-F", "owner={owner}", "-F", "name={repo}", "-f", `query=${TOTAL}`, "--jq", ".data.repository.pullRequests.totalCount"], { cwd: root, on }).catch(() => null),
          exec("git", [...READ, "branch", "--show-current"], { cwd: root, on }),
          worktrees(root, on),
        ]);
        if (this.key() !== context || this.filter !== filter) return;
        if (list.code !== 0) {
          const err = (list.stderr || "").toLowerCase();
          this.error = err.includes("no git remote") || err.includes("no default remote") ? "No GitHub remote" : err.includes("auth") ? "gh is not logged in" : (list.stderr || "gh failed").trim().split("\n")[0];
          this.root = root; this.prs = []; return;
        }
        this.root = root; this.on = on; this.branch = branch.stdout.trim() || null; this.trees = trees;
        this.prs = JSON.parse(list.stdout || "[]");
        this.more = this.prs.length >= limit;
        const n = Number(total?.stdout?.trim());
        if (total?.code === 0 && total.stdout.trim() && Number.isFinite(n)) this.total = n;
        this.error = null;
        this.memo.set(memo, { root, on, branch: this.branch, trees, prs: this.prs, more: this.more, total: this.total, limit });
        // Shared state redraws every mod: write it only when it changes.
        const count = this.total ?? this.prs.length, was = shared("ship-it.prs");
        if (was?.root !== root || (was?.on ?? null) !== (on ?? null) || was?.count !== count) setShared("ship-it.prs", { root, on: on ?? null, count });
      } catch (e) { if (this.key() === context) this.error = String(e); }
      finally { if (this.loading === started) this.loading = 0; cx.notify(); }
    });
  }

  memoKey() { return `${this.context}#${this.filter}`; }

  // This folder and filter's last list, or nothing: shown while it loads.
  recall() {
    this.root = null; this.prs = []; this.error = null; this.branch = null; this.more = false; this.total = null; this.trees = {};
    const m = this.memo.get(this.memoKey());
    if (m) Object.assign(this, m);
  }

  pick(filter, cx) {
    if (filter === this.filter) return;
    const total = this.total;
    this.filter = filter; this.limit = PAGE; this.recall(); this.total ??= total;
    this.refresh(cx, true);
  }

  loadMore(cx) {
    if (this.loading) return;
    this.limit = this.prs.length + PAGE;
    this.refresh(cx, true);
  }

  // Open the PR in its worktree space: the one there is, else a new checkout.
  worktree(pr, cx) {
    if (this.opening || !this.root) return;
    const root = this.root, on = this.on, branch = localBranch(pr);
    this.opening = pr.number; cx.notify();
    cx.spawn(async (cx) => {
      try {
        const trees = await worktrees(root, on), path = trees[branch] ?? await addWorktree(root, on, pr);
        if (this.root === root) this.trees = { ...trees, [branch]: path };
        showSpace(path, on, Object.values(trees));
      } catch (e) { notify({ title: `Couldn't open #${pr.number} in a worktree`, body: String(e.message ?? e), level: "error", timeout: 8 }); }
      finally { this.opening = null; cx.notify(); }
    });
  }

  icon(name, color, size = 14) { return svg(ICON(name)).size(size).flex_none().text_color(color); }

  row(pr, t, where) {
    const look = prLook(pr), review = reviewLook(pr.reviewDecision), check = CHECK[checkState(pr.statusCheckRollup)];
    const here = pr.headRefName === this.branch;
    return v_flex().id(`pr-${pr.number}`).flex_none().px(10).py(7).gap(3).rounded(7).cursor_pointer()
      .when(here, (e) => e.bg(t.selected)).hover((s) => s.bg(t.hover))
      .when(this.expanded === pr.number, (e) => e.bg(t.hover))
      .on_click((_e, cx) => { this.expanded = this.expanded === pr.number ? null : pr.number; cx.notify(); })
      .child(h_flex().gap(8).items_center().min_w(0)
        .child(this.icon(look.icon, t[look.color] ?? t.muted, 13))
        .child(div().flex_1().min_w(0).truncate().text_color(t.foreground).child(pr.title))
        .when(Boolean(check), (e) => e.child(div().id(`pr-check-${pr.number}`).flex_none().tooltip(check[2]).child(this.icon(check[0], t[check[1]], 13)))))
      .child(h_flex().pl(21).gap(6).items_center().min_w(0).text_size(11).text_color(t.dim)
        .child(div().id(`pr-n-${pr.number}`).flex_none().text_color(t.muted).rounded(4).px(2).hover((s) => s.bg(t.raised)).tooltip("Copy link")
          .on_click((_e, cx) => { cx.stop_propagation(); cx.write_to_clipboard(pr.url); notify({ title: `#${pr.number} link copied`, body: pr.url, level: "info", timeout: 2 }); })
          .child(`#${pr.number}`))
        .child(div().min_w(0).truncate().child(pr.author?.login ?? ""))
        .child(div().flex_none().child(`· ${ago(pr.updatedAt)}`))
        .when(here, (e) => e.child(div().flex_none().text_color(t.accent).child("· this branch")))
        .child(div().flex_1())
        .when(!here, (e) => {
          const path = this.trees[localBranch(pr)], look = treeLook(path, spaceAt(path, where, Object.values(this.trees))), busy = this.opening === pr.number;
          return e.child(div().id(`pr-tree-${pr.number}`).flex_none().rounded(4).p(2).hover((s) => s.bg(t.raised)).tooltip(look.tip)
            .on_click((_e, cx) => { cx.stop_propagation(); this.worktree(pr, cx); })
            .child(this.icon(busy ? "loader" : look.icon, t[look.color], 12).when(busy, (i) => i.spin(800))));
        })
        .when(Boolean(review) && pr.reviewDecision !== "REVIEW_REQUIRED", (e) => e.child(div().flex_none().text_color(t[review.color]).child(review.label)))
        .child(div().flex_none().text_color(t.ansi2).child(`+${pr.additions}`))
        .child(div().flex_none().text_color(t.ansi1).child(`−${pr.deletions}`)))
      .when(this.expanded === pr.number, (e) => e.child(this.details(pr, here, t, where)));
  }

  // An open row: what the PR is and what it waits on, then its actions.
  details(pr, here, t, where) {
    const n = checkCounts(pr.statusCheckRollup), review = reviewLook(pr.reviewDecision);
    const asked = (pr.reviewRequests ?? []).map((r) => r.login ?? r.name ?? r.slug).filter(Boolean);
    const path = this.trees[localBranch(pr)], space = spaceAt(path, where, Object.values(this.trees)), look = treeLook(path, space), busy = this.opening === pr.number;
    const line = (icon, ...kids) => h_flex().gap(6).items_center().min_w(0).child(this.icon(icon, t.dim, 12)).children(kids);
    const checks = [[n.fail, "failed", "ansi1"], [n.pending, "running", "ansi3"], [n.pass, "passed", "ansi2"]].filter(([k]) => k)
      .map(([k, what, color], i) => div().flex_none().text_color(t[color]).child(`${i ? "· " : ""}${k} ${what}`));
    const button = (id, icon, label, primary, click) => h_flex().id(`pr-${id}-${pr.number}`).h(26).px(9).gap(6).items_center().flex_none().rounded(6).cursor_pointer().text_size(12)
      .when(primary, (e) => e.bg(t.accent).text_color(t.background)).when(!primary, (e) => e.border_1().border_color(t.border).text_color(t.foreground).hover((s) => s.bg(t.raised)))
      .on_click((_e, cx) => { cx.stop_propagation(); click(cx); })
      .child(this.icon(icon, primary ? t.background : t.muted, 12)).child(label);
    return v_flex().pl(21).pt(6).gap(5).text_size(11).text_color(t.muted)
      .child(div().text_size(12).text_color(t.foreground).child(pr.title))
      .child(line("git-branch", div().min_w(0).truncate().child(`${pr.headRefName} → ${pr.baseRefName}`)))
      .child(line("square-check", ...(checks.length ? checks : [div().child("No checks")])))
      .child(line("message-square", div().flex_none().when(Boolean(review), (e) => e.text_color(t[review?.color] ?? t.muted)).child(review?.label ?? "No review yet"),
        ...(asked.length ? [div().min_w(0).truncate().child(`· asked: ${asked.join(", ")}`)] : [])))
      .when((pr.labels ?? []).length > 0, (e) => e.child(line("circle-dot", div().min_w(0).truncate().child(pr.labels.map((l) => l.name).join(", ")))))
      .child(line("folder", div().min_w(0).truncate().child(here ? "Checked out here" : path ? `${tilde(path)}${space ? "" : " · no space open"}` : "No worktree yet")))
      .child(h_flex().pt(3).gap(6).flex_wrap()
        .when(!here, (e) => e.child(button("open-tree", busy ? "loader" : look.icon, busy ? (path ? "Opening…" : "Creating…") : look.label, true, (cx) => this.worktree(pr, cx))))
        .child(button("github", "external-link", "GitHub", false, (cx) => cx.open_url(pr.url)))
        .child(button("copy", "copy", "Copy link", false, (cx) => { cx.write_to_clipboard(pr.url); notify({ title: `#${pr.number} link copied`, body: pr.url, level: "info", timeout: 2 }); })));
  }

  render(cx) {
    if (this.shown() && (this.stale || this.key() !== this.context)) this.refresh(cx, false, true);
    const t = theme(), list = this.prs, where = list.length ? places(this.on) : [];
    const empty = this.error || (this.loading ? "Loading pull requests…" : this.filter === "all" ? "No open pull requests" : this.filter === "mine" ? "No open pull requests of yours" : "Nothing waiting for your review");
    return v_flex().id("ship-it-prs").size_full().min_h(0).rounded(10).overflow_hidden().bg(t.background).border_1().border_color(t.border).text_color(t.foreground).text_size(13)
      .child(h_flex().h(42).flex_none().px(14).gap(8).items_center().border_b(1).border_color(t.border)
        .child(div().font_semibold().whitespace_nowrap().child("Pull requests"))
        .child(div().px(5).py(1).rounded(4).border_1().border_color(t.border).text_size(10).text_color(t.muted).whitespace_nowrap().child(`${this.total ?? this.prs.length} open`))
        .child(div().flex_1())
        .child(div().id("prs-refresh").size(22).flex_none().flex().items_center().justify_center().rounded(5).cursor_pointer().hover((s) => s.bg(t.hover)).tooltip("Refresh")
          .on_click((_e, cx) => this.refresh(cx, true)).child(this.icon(this.loading ? "loader" : "refresh-cw", t.dim, 12))))
      .child(h_flex().flex_none().px(10).py(8).gap(4).border_b(1).border_color(t.border).children(FILTERS.map(([id, label]) => {
        const on = this.filter === id;
        return div().id(`prs-filter-${id}`).h(24).px(9).flex().items_center().rounded(6).cursor_pointer().text_size(12)
          .when(on, (e) => e.bg(t.selected).text_color(t.foreground)).when(!on, (e) => e.text_color(t.muted).hover((s) => s.bg(t.hover)))
          .on_click((_e, cx) => this.pick(id, cx)).child(label);
      })))
      .child(v_flex().id("prs-list").flex_1().min_h(0).overflow_y_scrollbar().p(6).gap(2)
        .children(list.map((pr) => this.row(pr, t, where)))
        .when(this.more && list.length > 0, (e) => e.child(div().id("prs-more").mx(4).my(6).h(28).flex_none().flex().items_center().justify_center().rounded(7)
          .border_1().border_color(t.border).text_size(12).text_color(t.muted).cursor_pointer().hover((s) => s.bg(t.hover))
          .on_click((_e, cx) => this.loadMore(cx)).child(this.loading ? "Loading…" : `Load ${PAGE} more`)))
        .when(!list.length, (e) => e.child(div().p(8).text_color(t.dim).child(empty))));
  }
}
