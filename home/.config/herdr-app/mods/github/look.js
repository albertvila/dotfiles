// How the GitHub mod draws a pull request: its colours, its icons and the
// pieces of its card, in the app's theme. The same look as Recap's: colour is
// spent only on state, surfaces stay neutral.

import { div, svg } from "gpui-kit";
import { h_flex } from "gpui-base";

// The mod's own icons, from the app's home folder, tinted with the text colour.
const ICONS = "mods/github/icons";

// The faces: the app's own for words, mono for what you'd type (branches,
// machines, keys). JetBrains Mono ships with Herdr.
export const MONO = "JetBrains Mono";

// A colour at an alpha: the theme's colours are #rrggbb.
export const tint = (color, alpha) => (/^#[0-9a-f]{6}$/i.test(color ?? "") ? color + Math.round(alpha * 255).toString(16).padStart(2, "0") : color);

// Colour roles, from the theme's own names for them, so every theme reads:
// ready (green), waiting (yellow), a draft, merged, something broken, and the
// accent for links, focus and what's asked of you.
export function tones(t) {
  return {
    review: t.ansi2,
    work: t.working ?? t.ansi3,
    draft: t.ansi8 ?? t.dim,
    merged: t.ansi5,
    fix: t.ansi1,
    need: t.blocked ?? t.ansi1,
    accent: t.accent ?? t.ansi4,
    fg: t.foreground,
    muted: t.muted,
    dim: t.dim,
    surface: t.popover,
    raised: t.raised ?? t.hover,
    sunk: t.input ?? t.background,
    line: t.border,
  };
}

// Where a pull request has got to, which every list is grouped by (as
// herdr-github's groups): whose move it is, yours first.
export const GROUPS = [
  { id: "review", label: "To review", tone: "accent", icon: "need" },
  { id: "fixing", label: "Needs fixing", tone: "fix", icon: "fix" },
  { id: "ready", label: "Ready to merge", tone: "review", icon: "done" },
  { id: "waiting", label: "Waiting", tone: "work", icon: "idle" },
  { id: "drafts", label: "Drafts", tone: "draft", icon: "draft" },
  { id: "done", label: "Done", tone: "merged", icon: "merged" },
];
export const groupOf = (id) => GROUPS.find((g) => g.id === id) ?? GROUPS[3];

// A readiness line's tone (herdr-github's): ok, warn, err, dim, merged, queue.
export const toneColor = (o, tone) => ({ ok: o.review, warn: o.work, err: o.fix, merged: o.merged, queue: o.accent })[tone] ?? o.dim;

// A PR's icon and colour: its state first, then its group.
export function prLook(o, pr) {
  if (pr.state === "MERGED") return { icon: "merged", color: o.merged };
  if (pr.state === "CLOSED") return { icon: "closed", color: o.fix };
  if (pr.draft) return { icon: "draft", color: o.draft };
  const g = groupOf(pr.group);
  return { icon: g.id === "fixing" ? "fix" : g.id === "review" ? "need" : "pr", color: o[g.tone] };
}

// A check's glyph and colour.
export function checkLook(o, outcome) {
  if (outcome === "pass") return { icon: "check", color: o.review, word: "passing" };
  if (outcome === "fail") return { icon: "cross", color: o.fix, word: "failing" };
  if (outcome === "pending") return { icon: "idle", color: o.work, word: "running" };
  return { icon: "idle", color: o.dim, word: "skipped" };
}

// How long ago, in a word or two.
export function ago(ms, now = Date.now()) {
  if (!ms) return "";
  const m = Math.floor((now - ms) / 60000);
  if (m < 1) return "just now";
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ago`;
  const d = Math.floor(h / 24);
  return d < 30 ? `${d}d ago` : new Date(ms).toLocaleDateString();
}

// One icon, `size` px square, in `color`.
export function icon(name, color, size = 16) {
  return svg(`${ICONS}/${name}.svg`).flex_none().w(size).h(size).text_color(color);
}

export function duration(ms) {
  const m = Math.floor(ms / 60000);
  if (m < 1) return "<1m";
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  return h < 24 ? `${h}h` : `${Math.floor(h / 24)}d`;
}

// A chip: a small rounded label, neutral unless it carries a state's colour
// (then tinted with it). `parts` are elements or strings; `click` makes it a
// link.
export function chip(o, id, parts, { color = null, mono = false, click = null } = {}) {
  return h_flex()
    .id(id)
    .flex_none()
    .h(22)
    .px(8)
    .gap(5)
    .items_center()
    .rounded(6)
    .bg(color ? tint(color, 0.12) : o.sunk)
    .text_size(mono ? 11 : 11.5)
    .text_color(color ?? o.muted)
    .when(!mono, (el) => el.font_medium())
    .when(mono, (el) => el.font_family(MONO))
    .when(Boolean(click), (el) =>
      el.cursor_pointer()
        .hover((s) => s.bg(color ? tint(color, 0.22) : o.raised))
        .on_click((_e, cx) => {
          cx.stop_propagation();
          click(cx);
        }))
    .children(parts.filter((p) => p !== null && p !== undefined && p !== "").map((p) => (typeof p === "string" ? div().child(p) : p)));
}

// Words in a row, each in its colour: [text, color, onClick?], joined by
// dim dots between groups.
export function words(o, groups, idBase) {
  const out = [];
  groups.filter((g) => g.length).forEach((g, i) => {
    if (i > 0) out.push(div().text_color(o.dim).child("·"));
    g.forEach(([text, color, click, under], j) => {
      const w = div().text_color(color).child(text);
      if (!click) return out.push(w);
      out.push(
        div()
          .id(`${idBase}-${i}-${j}`)
          .text_color(color)
          .font_medium()
          .when(Boolean(under), (el) => el.underline())
          .cursor_pointer()
          .hover((s) => s.underline())
          .on_click((_e, cx) => {
            cx.stop_propagation();
            click(cx);
          })
          .child(text),
      );
    });
  });
  return h_flex().gap(8).items_center().flex_wrap().children(out);
}

// What's drawn on a keycap: the keys with a symbol of their own as icons
// (enter as an arrow down and left, ⌃, ⌘, tab, the arrows), letters
// capitalised as on the key; "^g" or "ctrl-g" is ⌃G, "cmd-g" ⌘G.
const KEY_ICONS = {
  enter: "key-enter", "⏎": "key-enter", "↵": "key-enter",
  tab: "key-tab", "⇥": "key-tab",
  "↑": "key-up", up: "key-up", "↓": "key-down", down: "key-down",
  "←": "key-left", left: "key-left", "→": "key-right", right: "key-right",
  ctrl: "key-ctrl", "^": "key-ctrl", "⌃": "key-ctrl",
  cmd: "key-cmd", "⌘": "key-cmd",
};
function keyParts(k) {
  const m = /^(\^|ctrl[-+]|cmd[-+])(.+)$/i.exec(k);
  if (m) return [m[1][0] === "^" ? "ctrl" : m[1].slice(0, -1).toLowerCase(), ...keyParts(m[2])];
  return [KEY_ICONS[k.toLowerCase()] ? k.toLowerCase() : k.length === 1 ? k.toUpperCase() : k];
}

// One keycap.
export function cap(o, k) {
  return h_flex()
    .flex_none()
    .min_w(20)
    .h(20)
    .px(5)
    .gap(1)
    .items_center()
    .justify_center()
    .rounded(5)
    .border_1()
    .border_b_2()
    .border_color(o.line)
    .bg(o.surface)
    .font_family(MONO)
    .text_size(11)
    .text_color(o.muted)
    .children(keyParts(k).map((p) => (KEY_ICONS[p] ? icon(KEY_ICONS[p], o.muted, 11) : div().child(p))));
}

// A key in the footer: its keycaps and what it does. Clickable.
export function key(o, keys, label, click, id) {
  return h_flex()
    .id(id)
    .flex_none()
    .gap(6)
    .items_center()
    .cursor_pointer()
    .text_size(12)
    .text_color(o.dim)
    .hover((s) => s.text_color(o.fg))
    .on_click((_e, cx) => click(cx))
    .children(keys.map((k) => cap(o, k)))
    .child(div().child(label));
}

// A tab's count, in a pill wide enough for it from the start: "–" until
// it's known, so the tabs don't move when it comes.
export function countPill(o, n, on) {
  return div()
    .flex_none()
    .min_w(24)
    .h(18)
    .px(6)
    .flex()
    .items_center()
    .justify_center()
    .rounded(9)
    .bg(on ? o.sunk : tint(o.line, 0.6))
    .font_family(MONO)
    .text_size(11)
    .font_medium()
    .text_color(on ? o.fg : o.dim)
    .child(n == null || n === "" ? "–" : String(n));
}
