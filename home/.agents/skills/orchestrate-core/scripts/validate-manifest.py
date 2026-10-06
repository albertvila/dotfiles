#!/usr/bin/env python3
"""Check a run manifest against the manifest contract.

Both plan skills run this after writing the manifest and before dispatching
anything; both threads skills dispatch the manifest it approved. The contract is
../manifest-contract.md. It reads one file, never a run, and exits non-zero on
any error.

    python3 validate-manifest.py <manifest>
    python3 validate-manifest.py --self-test
"""

import datetime
import re
import sys

SEP = "\u00b7"
FLOWS = ("A", "B", "cross-repo", "A+cross-repo")
MODES = ("gated", "land", "unattended")
FIELDS = ("id", "title", "ticket", "scope", "blockedBy", "acceptance", "out-of-scope")
NO_BLOCKERS = ("-", "none")
CROSS_FLOWS = ("cross-repo", "A+cross-repo")
NO_MERGE_MODES = ("land", "unattended")
STAMP = "%Y-%m-%dT%H:%M:%SZ"
TRACKER = re.compile(r"^(scratch\s+\S+|github\s+\S+#[0-9]+)$")
KEY = re.compile(r"^([A-Za-z][A-Za-z0-9_-]*):\s*(.*)$")
PLAN_GATE = re.compile(r"^requested=(\S+)\s+approved=(\S+)$")
ITEM_PREFIX = "item:"
WAVE_PREFIX = "wave:"


def item_line(*fields):
    """The contract's item line, for fixtures."""
    return "item: " + (" %s " % SEP).join(fields)


def parse(text):
    """-> (items, waves, header, errors). items is {line_number: item}."""
    items, waves, header, errors = {}, [], {}, []
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith(ITEM_PREFIX):
            item, error = _item(line[len(ITEM_PREFIX):].strip(), number)
            errors += ([error] if error else [])
            if item:
                items[number] = item
        elif line.startswith(WAVE_PREFIX):
            ids = [i for i in re.split(r"[,\s]+", line[len(WAVE_PREFIX):].strip()) if i]
            waves.append((number, ids))
        else:
            match = KEY.match(line)
            if match:
                header.setdefault(match.group(1).lower(), (number, match.group(2).strip()))
    return items, waves, header, errors


def _item(body, number):
    parts = [p.strip() for p in body.split(SEP)]
    if len(parts) != len(FIELDS):
        return None, (
            "%d: item line has %d fields, 7 need exactly %d `%s` separators (a `%s` "
            "inside the title, scope, acceptance or out-of-scope text is the usual cause)"
            % (number, len(parts), len(FIELDS) - 1, SEP, SEP))
    item = dict(zip(FIELDS, parts))
    for name in FIELDS:
        if name != "blockedBy" and not item[name]:
            return None, "%d: item %s has an empty %s" % (number, item["id"] or "?", name)
    item["blockedBy"] = ([] if item["blockedBy"].lower() in NO_BLOCKERS else
                         [b.strip() for b in item["blockedBy"].split(",") if b.strip()])
    return item, None


def check(items, waves, header):
    errors = []
    by_id, first_line = {}, {}
    for number, item in items.items():
        if item["id"] in by_id:
            errors.append("%d: item id %s is already on line %d"
                          % (number, item["id"], first_line[item["id"]]))
            continue
        by_id[item["id"]] = item
        first_line[item["id"]] = number
    if not items:
        errors.append("no `item:` lines — a manifest with no items dispatches nothing")

    errors += _cycles(by_id)

    if not waves:
        errors.append("no `wave:` lines — every item is dispatched by exactly one wave")
    wave_of = {}
    for index, (number, ids) in enumerate(waves):
        if not ids:
            errors.append("%d: empty `wave:` line" % number)
        for id_ in ids:
            if id_ not in by_id:
                errors.append("%d: wave names %s, which is not an item" % (number, id_))
            elif id_ in wave_of:
                errors.append("%d: item %s is in wave %d and again here — every item is "
                              "dispatched exactly once" % (number, id_, wave_of[id_] + 1))
            else:
                wave_of[id_] = index
    for number, item in items.items():
        if item["id"] in by_id and item["id"] not in wave_of:
            errors.append("%d: item %s is in no wave" % (number, item["id"]))
    for number, item in items.items():
        if item["id"] not in by_id:
            continue
        for blocker in item["blockedBy"]:
            if blocker not in by_id:
                errors.append("%d: item %s is blocked by %s, which is not an item"
                              % (number, item["id"], blocker))
            elif blocker in wave_of and wave_of[blocker] >= wave_of.get(item["id"], -1):
                errors.append("%d: item %s is blocked by %s but they dispatch in the same "
                              "wave or a later one" % (number, item["id"], blocker))

    return errors + _headers(header, items)


def _cycles(by_id):
    state, errors = {}, []

    def visit(id_, stack):
        if state.get(id_) == "done":
            return
        if state.get(id_) == "open":
            errors.append("blockedBy is cyclic: %s" % " -> ".join(stack + [id_]))
            return
        state[id_] = "open"
        for blocker in by_id[id_]["blockedBy"]:
            if blocker in by_id:
                visit(blocker, stack + [id_])
        state[id_] = "done"

    for id_ in sorted(by_id):
        visit(id_, [])
    return errors


def _headers(header, items):
    errors = []
    tracker = header.get("tracker")
    if not tracker:
        errors.append("no `tracker:` line — `scratch <feature>` or `github <owner>/<repo>#<n>`")
    elif not TRACKER.match(tracker[1]):
        errors.append("%d: tracker %r is neither `scratch <feature>` nor "
                      "`github <owner>/<repo>#<n>`" % (tracker[0], tracker[1]))

    flow = header.get("flow")
    if not flow:
        errors.append("no `flow:` line — %s" % ", ".join(FLOWS))
    elif flow[1] not in FLOWS:
        errors.append("%d: flow %r is not one of %s" % (flow[0], flow[1], ", ".join(FLOWS)))

    mode = header.get("mode")
    if not mode:
        errors.append("no `mode:` line — never omitted; the executor reads a missing line as gated")
    elif mode[1] not in MODES:
        errors.append("%d: mode %r is not one of %s" % (mode[0], mode[1], ", ".join(MODES)))

    if "base" in header and not header["base"][1]:
        errors.append("%d: empty `base:` line" % header["base"][0])

    if flow and mode and flow[1] in CROSS_FLOWS and mode[1] in NO_MERGE_MODES:
        errors.append("%d: mode %s is refused on flow %s — it has a human gate"
                      % (mode[0], mode[1], flow[1]))

    if header.get("plan-gate"):
        errors += _plan_gate(*header["plan-gate"])

    if mode and mode[1] == "unattended":
        tickets = {item["ticket"] for item in items.values()}
        if len(items) != len(tickets):
            errors.append("mode unattended does not reduce tickets: %d item(s) for %d ticket(s)"
                          % (len(items), len(tickets)))
    return errors


def _plan_gate(number, value):
    match = PLAN_GATE.match(value)
    if not match:
        return ["%d: plan-gate is `requested=<ISO-8601 UTC> approved=<ISO-8601 UTC>`, got %r"
                % (number, value)]
    errors, stamps = [], []
    for word, raw in zip(("requested", "approved"), match.groups()):
        try:
            stamps.append(datetime.datetime.strptime(raw, STAMP))
        except ValueError:
            errors.append("%d: plan-gate %s=%s is not ISO-8601 UTC (YYYY-MM-DDTHH:MM:SSZ)"
                          % (number, word, raw))
            stamps.append(None)
    if all(stamps) and stamps[1] < stamps[0]:
        errors.append("%d: plan-gate approved=%s precedes requested=%s"
                      % (number, match.group(2), match.group(1)))
    return errors


def validate(text):
    items, waves, header, errors = parse(text)
    return items, waves, errors + check(items, waves, header)


HEAD = [
    "feature: login-hardening  rundir: /tmp/run",
    "tracker: github owner/repo#42",
    "flow: B",
    "mode: gated",
    "base: main",
    "plan-gate: requested=2026-01-01T00:00:00Z approved=2026-01-01T00:05:00Z",
]
GOOD = "\n".join(HEAD + [
    item_line("01", "Session store", "#43", "src/auth/session.ts", "-",
              "a reset token is single use", "token rotation is out of scope"),
    item_line("02", "Login form", "#44", "src/auth/form.tsx", "01",
              "the form rejects an empty password", "styling is out of scope"),
    "wave: 01",
    "wave: 02",
    "note: serialised on an overlapping region",
])


def self_test():
    def without(prefix):
        return [line for line in HEAD if not line.startswith(prefix)]

    _, _, errors = validate(GOOD)
    assert not errors, errors

    # Comma-separated blockers, and a wave with two members.
    three = "\n".join(HEAD + [
        item_line("01", "A", "#43", "src/x.ts", "-", "a", "b"),
        item_line("02", "B", "#44", "src/y.ts", "01", "c", "d"),
        item_line("03", "C", "#45", "src/z.ts", "01, 02", "e", "f"),
        "wave: 01",
        "wave: 02",
        "wave: 03",
    ])
    _, waves, errors = validate(three)
    assert not errors, errors
    assert len(waves) == 3, waves

    items = [line for line in GOOD.splitlines() if line.startswith("item:")]
    wave_1, wave_2 = "wave: 01", "wave: 02"

    def rejects(name, text, needle):
        _, _, errors = validate(text)
        assert any(needle in error for error in errors), (name, errors)

    rejects("extra separator",
            "\n".join(HEAD + [items[0] + " %s loose end" % SEP] + items[1:] + [wave_1, wave_2]),
            "has 8 fields")
    rejects("empty acceptance",
            "\n".join(HEAD + [item_line("01", "A", "#43", "src/x.ts", "-", "", "b")] +
                      items[1:] + [wave_1, wave_2]),
            "empty acceptance")
    rejects("duplicate id", "\n".join(HEAD + items + [items[0], wave_1, wave_2]),
            "already on line")
    rejects("unknown blocker",
            "\n".join(HEAD + [item_line("01", "A", "#43", "src/x.ts", "99", "a", "b")] +
                      [items[1], wave_1, wave_2]),
            "not an item")
    rejects("cycle",
            "\n".join(HEAD + [item_line("01", "A", "#43", "src/x.ts", "02", "a", "b")] +
                      [items[1], wave_1, wave_2]),
            "cyclic")
    rejects("item in no wave", "\n".join(HEAD + items + [wave_1]), "in no wave")
    rejects("blocker in the same wave", "\n".join(HEAD + items + ["wave: 01 02"]),
            "same wave or a later")
    rejects("missing mode", "\n".join(without("mode:") + items + [wave_1, wave_2]),
            "no `mode:` line")
    rejects("bad flow",
            "\n".join([line.replace("flow: B", "flow: Z") for line in HEAD] + items +
                      [wave_1, wave_2]),
            "is not one of A, B")
    rejects("land on cross-repo",
            "\n".join([line.replace("flow: B", "flow: cross-repo").replace("mode: gated", "mode: land")
                       for line in HEAD] + items + [wave_1, wave_2]),
            "has a human gate")
    rejects("unattended with a reduction",
            "\n".join([line.replace("mode: gated", "mode: unattended") for line in HEAD] +
                      [item_line("01", "A", "#43", "src/x.ts", "-", "a", "b"),
                       item_line("02", "B", "#43", "src/y.ts", "01", "c", "d"),
                       wave_1, wave_2]),
            "does not reduce")
    rejects("empty base",
            "\n".join([line.replace("base: main", "base:") for line in HEAD] + items +
                      [wave_1, wave_2]),
            "empty `base:` line")
    rejects("gate approved before requested",
            "\n".join(without("plan-gate:") +
                      ["plan-gate: requested=2026-01-01T00:10:00Z approved=2026-01-01T00:00:00Z"] +
                      items + [wave_1, wave_2]),
            "precedes requested")

    print("self-test OK")
    return 0


def main(argv):
    if "--self-test" in argv[1:]:
        return self_test()
    if len(argv) != 2:
        print("usage: validate-manifest.py <manifest> | --self-test", file=sys.stderr)
        return 2
    try:
        with open(argv[1], encoding="utf-8") as handle:
            text = handle.read()
    except OSError as exc:
        print("FAIL: %s" % exc)
        return 1
    items, waves, errors = validate(text)
    if errors:
        print("FAIL: %d error(s)" % len(errors))
        for error in errors:
            print("  " + error)
        return 1
    print("OK: %d item(s), %d wave(s)" % (len(items), len(waves)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
