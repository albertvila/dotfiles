// A whole file, read-only, in a pane: opened from the PR changes panel.
// Props: { root, on, path } (repo root, machine, path in the repo). A newer
// shared("ship-it.file") for the same repo moves it to that file.

import { View, div } from "gpui-kit";
import { v_flex, h_flex, EditorState, Editor } from "gpui-base";
import { theme, settings, props, shared, readTextFile, watchFolder, spaces, panes } from "herdr";

const LANG = { ts: "js", tsx: "js", mts: "js", cts: "js", jsx: "js", mjs: "js", toml: "yaml", jsonc: "json", svelte: "html", vue: "html", yml: "yaml", py: "python", rs: "rust", sh: "bash", md: "markdown" };

export default class FileView extends View {
  init(_p, cx) {
    const p = props() ?? _p ?? {};
    this.root = p.root; this.on = p.on ?? null; this.path = p.path;
    this.seen = shared("ship-it.file")?.at ?? 0;
    this.load(cx);
    // Local files follow edits; remote ones reload on a timer.
    if (this.root && !this.on) cx.spawn(async (cx) => {
      try { for (;;) { await watchFolder(this.root); await cx.sleep(1500); this.load(cx); } } catch {}
    });
    else cx.timer.every(15000, (cx) => this.load(cx));
  }

  // A file pane in the tab on screen (a mod pane doesn't know its own id).
  shown() {
    const tab = spaces().find((s) => s.active)?.tabs?.find((t) => t.active)?.id;
    return panes().some((p) => p.mod === "ship-it-file" && p.tab === tab);
  }

  // Hidden, a change only marks it stale; showing it reloads.
  load(cx) {
    if (this.text != null && !this.shown()) { this.stale = true; return; }
    if (!this.root || !this.path || this.busy) return;
    this.stale = false;
    this.busy = true;
    cx.spawn(async (cx) => {
      try {
        const text = await readTextFile(`${this.root}/${this.path}`, { on: this.on });
        if (text === null) { this.error = "This file is not there now (deleted on this branch?)"; return; }
        if (text.includes("\0")) { this.error = "Binary file · no text preview"; return; }
        if (text === this.text) return;
        this.text = text; this.error = null;
        const value = text.length > 400000 ? text.slice(0, 400000) + "\n… (file truncated)" : text;
        if (this.code) { this.code.set_value(value); return; }
        const t = theme(), ext = this.path.includes(".") ? this.path.split(".").pop() : "txt";
        this.code = EditorState.new({ language: LANG[ext] ?? ext, readonly: true, value,
          font_family: settings().font_family, font_size: 12,
          syntax: { keyword: t.ansi5, string: t.ansi2, comment: t.dim, function: t.ansi4, type: t.ansi3, number: t.ansi1, constant: t.ansi6 } });
      } catch { this.error = "Cannot open this file (binary, too large, or unreadable)"; }
      finally { this.busy = false; cx.notify(); }
    });
  }

  render(cx) {
    const target = shared("ship-it.file");
    if (target?.at > this.seen && target.root === this.root && (target.on ?? null) === this.on) {
      this.seen = target.at;
      if (target.path !== this.path) { this.path = target.path; this.text = null; this.error = null; this.code?.release(); this.code = null; this.load(cx); }
    }
    const p = props();
    if (!this.path && p?.path) { this.root = p.root; this.on = p.on ?? null; this.path = p.path; this.load(cx); }
    if (this.stale && this.shown()) this.load(cx);
    const t = theme(), parts = (this.path ?? "").split("/"), name = parts.pop();
    return v_flex().id("ship-it-file").size_full().min_h(0).bg(t.background).text_color(t.foreground).text_size(13)
      .child(h_flex().h(36).flex_none().px(12).gap(2).items_center().border_b(1).border_color(t.border).text_size(12)
        .child(div().min_w(0).truncate().text_color(t.dim).child(parts.length ? parts.join("/") + "/" : ""))
        .child(div().flex_none().font_semibold().child(name || "No file")))
      .child(this.code && !this.error ? Editor.new(this.code).flex_1().min_h(0)
        : div().p(12).text_color(t.dim).child(this.error || (this.path ? "Loading file…" : "No file")));
  }
}
