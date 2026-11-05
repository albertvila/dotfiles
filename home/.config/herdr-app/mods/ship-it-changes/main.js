// Changes: one panel for what you changed, in two views. Uncommitted is the
// working tree against HEAD, with a commit box (git add -A, git commit -m, as
// Herdr's own Changes panel does). Since <base> is what the branch changes
// since its base, uncommitted work included: the PR after the next push. The
// base is the one the strip found for this repo (shared "ship-it.base"), else
// origin/HEAD, main or master. Files above, the picked file's diff below.
// The layout's "changes" block can hold it, so Herdr's Changes button opens it.
//
// data.js and files.js are copies: edit mods/ship-it/data.js and
// mods/ship-it-review/files.js, then run scripts/install.sh.

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex, Scrollbar, v_virtual_list, InputState, Input } from "gpui-base";
import { exec, shared, setShared, run, panes, focused, watchFolder, theme, settings, layout } from "herdr";
import { location, baseRef, panelShown, Recent } from "./data.js";
import { branchFiles, fileDiff, diffRows, MAX_FILES } from "./files.js";

const STATUS = { A: "ansi2", D: "ansi1", U: "ansi1", M: "ansi3" };
const ICON = (name) => `mods/ship-it/icons/${name}.svg`;

// The view: "dirty" (uncommitted) or "branch" (since the base). Shared, so the
// strip's changes button can open the branch view.
const mode = () => (shared("ship-it.changes")?.mode === "dirty" ? "dirty" : "branch");

// The panel-body block that holds this mod: "changes" when it took the place
// of Herdr's own, else "ship-it-changes".
function host() {
  const find = (n) => n?.id === "panel-body" ? n : (n?.children ?? []).map(find).find(Boolean);
  return find(layout())?.children?.find((c) => c.content?.mod === "ship-it-changes")?.id ?? "ship-it-changes";
}

export default class PrChanges extends View {
  init(_props, cx) {
    this.files = []; this.rows = []; this.diffWidth = 0; this.last = null; this.message = "";
    this.input = InputState.new({ placeholder: "Commit message" });
    this.input.on("change", (_e, cx) => {
      const had = Boolean(this.message.trim());
      this.message = this.input.value();
      if (had !== Boolean(this.message.trim())) cx.notify();
    });
    this.input.on("submit", (_e, cx) => this.commit(cx));
    this.input.on("focus", (_e, cx) => { this.typing = true; cx.notify(); });
    this.input.on("blur", (_e, cx) => { this.typing = false; cx.notify(); });
    // Last list per folder and base: switching back shows it at once.
    this.memo = new Recent(12);
    this.refresh(cx);
    cx.timer.every(10000, (cx) => this.refresh(cx));
  }

  // Hidden, it only notes that it is out of date; showing it catches up.
  shown() { return panelShown(host()); }

  // Where the work is, and the base the strip found for that repo.
  where() {
    this.last = location(this.last);
    const base = shared("ship-it.base");
    return { cwd: this.last.cwd, on: this.last.on, base };
  }

  key() {
    const { cwd, on, base } = this.where();
    return JSON.stringify([cwd, on, base?.root, base?.ref, mode()]);
  }

  watch(root, cx) {
    if (this.on || this.watched === root) return;
    this.watched = root;
    cx.spawn(async (cx) => {
      try {
        while (this.watched === root) {
          await watchFolder(root);
          // A burst of writes (a build, an agent's edits) becomes one refresh.
          await cx.sleep(1500);
          if (this.watched === root) this.refresh(cx);
        }
      } catch { this.watched = null; }
    });
  }

  refresh(cx) {
    if (!this.shown()) { this.stale = true; return; }
    if (this.loading) return;
    this.stale = false;
    const { cwd, on, base: shown } = this.where(), context = this.key();
    if (context !== this.context) {
      this.context = context; this.root = null; this.files = []; this.open = null; this.base = null;
      this.setLines([]); this.error = null; this.note = null; this.watched = null; this.closed = false; this.limited = false;
      const m = this.memo.get(context);
      if (m) Object.assign(this, m);
    }
    if (!cwd) return;
    this.loading = true;
    cx.spawn(async (cx) => {
      try {
        const top = await exec("git", ["rev-parse", "--show-toplevel"], { cwd, on });
        if (this.key() !== context) return;
        if (top.code !== 0) { this.root = null; this.files = []; this.setLines([]); this.open = null; this.error = "Not a git repository"; return; }
        const root = top.stdout.trim();
        const base = mode() === "dirty" ? "HEAD" : shown?.root === root && (shown.on ?? null) === (on ?? null) && shown.ref ? shown.ref : await baseRef(root, on, null);
        if (this.key() !== context) return;
        if (!base) { this.root = root; this.files = []; this.error = "No base branch to compare with"; return; }
        const { mb, files, limited } = await branchFiles(root, on, base);
        if (this.key() !== context) return;
        this.root = root; this.on = on; this.base = base; this.mb = mb; this.files = files; this.limited = limited;
        this.memo.set(context, { root, on, base, mb, files, limited });
        this.error = mb ? null : `No common history with ${base}`;
        this.watch(root, cx);
        if (this.open && !files.some((f) => f.path === this.open)) { this.open = null; this.setLines([]); }
        // The first file's diff shows until you pick another.
        if (!this.open && !this.closed && files.length) this.open = files[0].path;
        if (this.open) {
          try { await this.load(this.open, context); }
          catch { if (this.key() === context) this.setLines(["Cannot preview this diff (too large or unreadable)"]); }
        }
      } catch (e) { if (this.key() === context) this.error = String(e); }
      finally { this.loading = false; cx.notify(); }
    });
  }

  async load(path, context) {
    const file = this.files.find((f) => f.path === path);
    if (!file || !this.mb) return;
    const { lines, cut } = await fileDiff(this.root, this.on, this.mb, file);
    if (this.key() === context && this.open === path) {
      this.setLines(cut ? [...lines, "… diff cut here; open it in Review for the rest"] : lines);
    }
  }

  setLines(lines) {
    this.rows = diffRows(lines);
    this.diffWidth = Math.max(300, ...lines.map((line) => line.length * 7 + 50));
  }

  pick(path, cx) {
    this.open = this.open === path ? null : path; this.setLines([]); this.note = null;
    this.closed = !this.open;
    const context = this.context;
    if (this.open) cx.spawn(async (cx) => {
      try { await this.load(path, context); }
      catch (e) { if (this.key() === context && this.open === path) this.note = `Cannot preview this diff (too large or unreadable): ${e}`; }
      cx.notify();
    });
    cx.notify();
  }

  // The whole file in a pane: this tab's file pane if it has one, else a new
  // one to the right of a pane in the tab on screen.
  openFile(path) {
    const f = focused(), file = this.files.find((x) => x.path === path);
    if (!this.root || !f || !file || file.status === "D") return;
    setShared("ship-it.file", { root: this.root, on: this.on ?? null, path, at: Date.now() });
    const existing = panes().find((p) => p.mod === "ship-it-file" && p.tab === f.tab);
    if (existing) { run("pane.focus", { pane: existing.pane }); return; }
    const own = panes().find((p) => p.pane === f.pane && p.tab === f.tab);
    const from = own?.pane ?? panes().find((p) => p.tab === f.tab)?.pane;
    run("pane.split", { direction: "right", ...(from ? { pane: from } : {}), mod: "ship-it-file", props: { root: this.root, on: this.on ?? null, path } });
  }

  setMode(m) {
    if (m !== mode()) setShared("ship-it.changes", { mode: m, at: Date.now() });
  }

  commit(cx) {
    if (!this.message.trim() || !this.root || this.busy || this.loading || mode() !== "dirty") return;
    const root = this.root, on = this.on, context = this.context, message = this.message.trim();
    this.busy = true; this.note = null;
    cx.spawn(async (cx) => {
      try {
        for (const args of [["add", "-A"], ["commit", "-m", message]]) {
          const r = await exec("git", args, { cwd: root, on });
          if (r.code !== 0) throw new Error((r.stderr || r.stdout).trim());
        }
        if (this.key() === context) { this.message = ""; this.input.set_value(""); }
      } catch (e) { if (this.key() === context) this.note = `Commit failed: ${e}`; }
      finally { this.busy = false; this.refresh(cx); cx.notify(); }
    });
    cx.notify();
  }

  diffRow(row, t) {
    const { kind, text } = row, number = kind === "-" ? row.old : row.new;
    if (kind === "@") return div().w_full().px(12).h(20).flex_none().truncate().bg(t.raised).text_color(t.dim).child(text);
    return h_flex().w_full().h(20).flex_none().gap(10).when(kind === "+", (e) => e.bg(t.ansi2 + "18")).when(kind === "-", (e) => e.bg(t.ansi1 + "18"))
      .child(div().w(30).flex_none().text_right().text_color(t.dim).child(number === undefined ? "" : String(number)))
      .child(div().flex_1().min_w(0).truncate().child(text));
  }

  render(cx) {
    if (this.shown() && (this.stale || this.key() !== this.context)) this.refresh(cx);
    const t = theme(), add = this.files.reduce((n, f) => n + f.add, 0), del = this.files.reduce((n, f) => n + f.del, 0);
    const dirty = mode() === "dirty", enabled = Boolean(this.message.trim() && this.root && !this.busy && !this.loading);
    const empty = this.error || (this.loading ? "Loading changes…" : dirty && this.root ? "No uncommitted changes" : this.base ? `No changes since ${this.base}` : this.root ? "Loading changes…" : "No folder");
    const since = (shared("ship-it.base")?.ref ?? this.base ?? "main").replace(/^origin\//, "");
    const tab = (m, label, tip) => div().id(`changes-${m}`).h(24).px(8).flex().items_center().rounded(6).cursor_pointer().text_size(12).whitespace_nowrap().tooltip(tip)
      .when(mode() === m, (e) => e.bg(t.selected).text_color(t.foreground)).when(mode() !== m, (e) => e.text_color(t.muted).hover((s) => s.bg(t.hover)))
      .on_click(() => this.setMode(m)).child(label);
    return v_flex().id("pr-changes").size_full().min_h(0).rounded(10).overflow_hidden().bg(t.background).border_1().border_color(t.border).text_color(t.foreground).text_size(13)
      .child(h_flex().h(42).flex_none().px(14).gap(8).items_center().border_b(1).border_color(t.border)
        .child(div().font_semibold().whitespace_nowrap().child("Changes"))
        .child(h_flex().gap(2).flex_none()
          .child(tab("dirty", "Uncommitted", "The working tree against HEAD, with a commit box"))
          .child(tab("branch", `Since ${since}`, `What the branch changes since ${shared("ship-it.base")?.ref ?? this.base ?? "its base"}, uncommitted work included`)))
        .child(div().px(5).py(1).rounded(4).border_1().border_color(t.border).text_size(10).text_color(t.muted).whitespace_nowrap().child(`${this.files.length} files`))
        .child(div().flex_1()).child(div().text_size(11).text_color(t.ansi2).child(`+${add}`)).child(div().text_size(11).text_color(t.ansi1).child(`−${del}`)))
      .child(v_flex().id("pr-changes-list").flex_none().h(Math.min(200, Math.max(44, this.files.length * 28 + 12))).overflow_y_scrollbar().p(6).border_b(1).border_color(t.border).children(this.files.map((f) => {
        const parts = f.path.split("/"), name = parts.pop();
        return h_flex().id(`pr-change-${f.path}`).h(28).flex_none().px(8).gap(8).items_center().rounded(7).cursor_pointer().when(this.open === f.path, (e) => e.bg(t.selected)).hover((s) => s.bg(t.hover)).on_click((e, cx) => {
            if (e.click_count < 2) this.pick(f.path, cx);
            else { if (this.open !== f.path) this.pick(f.path, cx); this.openFile(f.path); }
          })
          .child(div().w(14).text_size(11).text_color(t[STATUS[f.status] ?? "ansi3"]).child(f.status))
          .child(h_flex().flex_1().min_w(0).child(div().text_color(t.dim).truncate().child(parts.length ? parts.join("/") + "/" : "")).child(div().max_w(260).min_w(0).truncate().child(name)))
          .when(f.dirty, (e) => e.child(div().size(6).flex_none().rounded_full().bg(t.ansi3)))
          .when(this.open === f.path && f.status !== "D", (e) => e.child(div().id("open-file").size(20).flex_none().flex().items_center().justify_center().rounded(5).hover((s) => s.bg(t.hover)).tooltip("Open the whole file in a pane (double-click)")
            .child(svg(ICON("external-link")).size(12).text_color(t.muted)).on_click((_e, cx) => { cx.stop_propagation(); this.openFile(f.path); })))
          .when(f.add > 0, (e) => e.child(div().text_size(11).text_color(t.ansi2).child(`+${f.add}`))).when(f.del > 0, (e) => e.child(div().text_size(11).text_color(t.ansi1).child(`−${f.del}`)));
      })).when(!this.files.length, (e) => e.child(div().p(8).text_color(t.dim).child(empty))))
      .when(this.limited, (el) => el.child(div().px(12).py(4).text_size(11).text_color(t.dim).child(`Showing the first ${MAX_FILES.toLocaleString()} changed files`)))
      .child(div().flex_1().min_h(0).relative().font_family(settings().font_family ?? "JetBrains Mono").text_size(11)
        .child(div().id("pr-changes-diff-x").size_full().overflow_x_scrollbar()
          .child(div().w_full().min_w(this.diffWidth).h_full().child(v_virtual_list("pr-changes-diff", this.rows.length, 20, (i) => String(i),
            (range) => this.rows.slice(range.start, range.end).map((row) => this.diffRow(row, t))).size_full())))
        .child(Scrollbar.vertical("pr-changes-diff").viewport_from_layout().absolute().inset_0())
        .when(!this.open && this.files.length > 0, (e) => e.child(div().absolute().top(6).px(12).text_color(t.dim).child("Select a file to view its changes"))))
      .when(Boolean(this.note), (e) => e.child(div().px(10).pb(8).text_size(11).text_color(t.ansi1).child(this.note)))
      .when(dirty, (e) => e.child(h_flex().flex_none().p(10).gap(8).border_t(1).border_color(t.border)
        .child(div().id("commit-message").flex_1().min_w(0).h(32).px(10).flex().items_center().rounded(8).border_1().border_color(this.typing ? t.accent : t.border).cursor_text().on_mouse_down("left", (_e, cx) => cx.stop_propagation()).child(Input.new(this.input).h_full().text_size(12).text_color(t.foreground)))
        .child(div().id("commit").h(32).px(14).flex().items_center().rounded(8).bg(enabled ? t.solid : t.raised).text_color(enabled ? t.solid_foreground : t.dim).text_size(12).when(enabled, (e) => e.cursor_pointer()).on_click((_e, cx) => this.commit(cx)).child(this.busy ? "Committing…" : "Commit"))));
  }
}
