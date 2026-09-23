#!/usr/bin/env python3
"""Aggregate timing, tokens, cost and anomalies for one BB run.

A run is a manager thread plus its children (workers, review, ponytail). All
numbers come from `bb thread log --json` events and, when present, the run's
`orchestration.json` ledger. Read-only against the run: nothing is written
except the pricing cache and, when `--output-dir` is given, the record.

    run-metrics.py <manager-thread-id> [--json] [--no-pricing] [--ledger PATH]
    run-metrics.py <manager-thread-id> --output-dir DIR   # also writes run.json
    run-metrics.py --self-test

The record is assembled by `assemble_record`, a pure function of the events,
the ledger and the run's identity; `--self-test` asserts against it.

Timing caveat: in a shared-worktree run the phases overlap on purpose, so
per-role totals sum to more than the run's wall-clock span. Both are reported.
"""

import argparse
import collections
import datetime
import json
import os
import re
import subprocess
import sys
import time
import urllib.request

PRICING_URL = "https://openrouter.ai/api/v1/models"
PRICING_TTL = 24 * 3600
SCHEMA_VERSION = 1

TASK_KEY_RE = re.compile(r"^[A-Z][A-Z0-9]*-\d+$")
WAIT_CMD_RE = re.compile(r"(?:^|[;&|]\s*)bb\s+thread\s+wait\s+(thr_\w+)")

IDLE_FINDING_MS = 10 * 60_000
# A host-daemon restart is not a thread waiting on anybody; below this it is noise.
INFRA_FINDING_MS = 60_000
ACTIVE_STATUSES = {"active", "starting", "running", "settling"}
RUNNING_ITEM_STATUSES = {"running", "in_progress", "in-progress"}


def sh(*args):
    p = subprocess.run(args, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(f"{' '.join(args)}: {p.stderr.strip()[:200]}")
    return p.stdout


def bb(*args):
    return json.loads(sh("bb", *args))


def role_of(title, is_manager=False):
    if is_manager:
        return "manager"
    t = (title or "").upper()
    if t.startswith("REVIEW"):
        return "review"
    if t.startswith("PONYTAIL"):
        return "ponytail"
    return "worker"


def iso(ms):
    if ms is None:
        return None
    return datetime.datetime.fromtimestamp(ms / 1000, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def minutes(ms):
    return f"{ms / 60_000:.1f}m"


def normalise_items(ledger):
    """The ledger's `items` is a list in some runs and a dict keyed by item id in
    others. Return a list of dicts with `id` always set, and never raise on a
    shape the ledger actually shipped."""
    if not isinstance(ledger, dict):
        return []
    items = ledger.get("items") or []
    if isinstance(items, dict):
        pairs = list(items.items())
    elif isinstance(items, list):
        pairs = [(None, v) for v in items]
    else:
        return []
    out = []
    for key, value in pairs:
        if isinstance(value, dict):
            item = dict(value)
        elif isinstance(value, str):
            item = {"id": value}
        elif value is None:
            item = {}
        else:
            item = {"value": value}
        if item.get("id") is None:
            item["id"] = key
        out.append(item)
    return out


def cost_of(tokens, price):
    """USD for one thread's tokens. Openrouter prices are per token.

    reasoningOutputTokens is a billed subset of outputTokens where a provider
    reports it, so output is charged once.
    """
    if not tokens or not price:
        return None
    cached = tokens.get("cacheReadInputTokens", tokens.get("cachedInputTokens", 0)) or 0
    written = tokens.get("cacheWriteInputTokens", 0) or 0
    return (
        (tokens.get("inputTokens", 0) or 0) * price.get("prompt", 0)
        + cached * price.get("input_cache_read", price.get("prompt", 0))
        + written * price.get("input_cache_write", price.get("prompt", 0))
        + (tokens.get("outputTokens", 0) or 0) * price.get("completion", 0)
    )


def price_for(model, table):
    """`openrouter/vendor/model` -> vendor/model, else the id as given."""
    if not table or not model:
        return None
    return table.get(model) or table.get(model.split("/", 1)[1] if "/" in model else model)


def cost_state(row, price):
    """A thread's cost with provenance. An estimate is never `reported`, and an
    unavailable cost is `None`, never 0.0. Cost bases, never conflated:
    `unmeasured` is a thread with no token event at all, `unpriced` a thread
    whose tokens have no matching price (M4)."""
    if not row["tokenEventSeen"]:
        return {"reported": None, "estimated": None, "basis": "unmeasured"}
    reported = row.get("costReported")
    estimated = cost_of(row["tokens"], price)
    if reported is not None:
        return {"reported": reported, "estimated": estimated, "basis": "reported"}
    if estimated is None:
        return {"reported": None, "estimated": None, "basis": "unpriced"}
    return {"reported": None, "estimated": estimated, "basis": "estimated"}


def format_cost(cost):
    """How a cost cell renders: never `$0.00` for something unavailable."""
    if cost["basis"] == "estimated":
        return f"${cost['estimated']:.2f}"
    if cost["basis"] == "reported":
        return f"${cost['reported']:.2f}"
    return cost["basis"]


def _merge(intervals):
    out = []
    for start, end in sorted(intervals):
        if out and start <= out[-1][1]:
            out[-1][1] = max(out[-1][1], end)
        else:
            out.append([start, end])
    return out


def _overlap_ms(a, b):
    i = j = 0
    total = 0
    while i < len(a) and j < len(b):
        lo, hi = max(a[i][0], b[j][0]), min(a[i][1], b[j][1])
        if hi > lo:
            total += hi - lo
        if a[i][1] < b[j][1]:
            i += 1
        else:
            j += 1
    return total


def _subtract(a, b):
    """`a` minus `b`, both as interval lists. Used to take a thread's own
    downtime out of the idle it is about to be blamed for."""
    out = []
    for start, end in a:
        cur = start
        for bs, be in b:
            if be <= cur or bs >= end:
                continue
            if bs > cur:
                out.append([cur, bs])
            cur = max(cur, be)
            if cur >= end:
                break
        if cur < end:
            out.append([cur, end])
    return out


def _infra_intervals(row):
    """The windows a thread spent dead in a host-daemon restart, not waiting."""
    return _merge(row.get("infra") or [])


def _idle_intervals(row):
    """The gaps between a thread's turns, inside its own wall window."""
    if not row["start"] or not row["end"]:
        return []
    out, cur = [], row["start"]
    for start, end in _merge(row["_intervals"]):
        if start > cur:
            out.append([cur, start])
        cur = max(cur, end)
    if cur < row["end"]:
        out.append([cur, row["end"]])
    return out


def analyse_thread(thread, events):
    """One thread's events -> timings, tokens and the raw facts cost is built on.

    Pure: no filesystem, no network. Prices are applied in `assemble_record`.
    """
    row = {
        "threadId": thread["id"],
        "title": thread.get("title"),
        "role": role_of(thread.get("title"), thread.get("isManager", False)),
        "provider": thread.get("providerId"),
        "status": thread.get("status"),
        "events": len(events),
        "turns": 0, "turnsFailed": 0,
        "models": [], "model": None,
        "tokens": None, "tokenEventSeen": False, "costReported": None,
        "start": None, "end": None,
        "wallMs": 0, "activeMs": 0, "workMs": 0, "idleMs": 0,
        "humanMs": 0, "waitMs": 0, "waitedOn": [], "waitingOn": None,
        "questionTimeoutMs": 0, "humanWaits": [], "pendingGate": False,
        "infra": [], "infraReasons": [],
        "errors": [], "openTurn": False,
        "_intervals": [], "_wait_intervals": [],
    }
    if not events:
        return row
    events = sorted(events, key=lambda e: e.get("createdAt") or 0)
    models = set()
    errors = collections.Counter()
    infra = []
    infra_reasons = set()
    intervals = []
    open_turn = None
    turn_open = False
    last_completed = None
    last_status = None
    timeout_since_completion = False
    pending = None
    pending_title = None

    for e in events:
        kind = e.get("type")
        data = e.get("data") or {}
        ts = e.get("createdAt")
        if ts is None:
            continue
        # A host restart closes on the thread's next event: everything between is
        # downtime, and blaming it on a sibling thread names the wrong cause (F3).
        if row.get("_infra_open") is not None and ts > row["_infra_open"]:
            infra.append([row["_infra_open"], ts])
            row["_infra_open"] = None
        if kind == "client/turn/requested":
            model = (data.get("execution") or {}).get("model")
            if model:
                models.add(model)
            target = (data.get("target") or {}).get("kind")
            # Message-borne waits are read only on the manager. On a child thread
            # the manager's own `bb thread tell` follow-up is byte-identical
            # (initiator "user", senderThreadId null), so a child would count
            # manager feedback as human time (M2).
            if (thread.get("isManager") and data.get("initiator") == "user"
                    and target in ("new-turn", "steer")
                    and not turn_open and last_completed is not None and ts > last_completed):
                # An approval (or any human message) that arrived as a plain
                # message rather than a pending lifecycle interaction (M2).
                # A gate that timed out inside the gap closes itself: no human
                # wait is counted for it, and the idle tail after it is idle.
                if timeout_since_completion:
                    row["humanWaits"].append({"kind": "message", "ms": 0, "counted": False,
                                              "reason": "gate timed out", "at": ts})
                else:
                    gap = ts - last_completed
                    row["humanMs"] += gap
                    row["humanWaits"].append({"kind": "message", "ms": gap, "counted": True,
                                              "text": _message_text(data), "at": ts})
                last_completed = None
        elif kind == "turn/started":
            turn_open = True
            open_turn = ts
        elif kind == "turn/completed":
            if open_turn is not None:
                row["turns"] += 1
                row["activeMs"] += ts - open_turn
                intervals.append([open_turn, ts])
                open_turn = None
            elif intervals and last_status not in (None, "completed"):
                # A turn interrupted by a lost host resumes without a second
                # turn/started; its resumed work belongs to the same turn. Ignore
                # it and everything after the interruption reads as idle (F4).
                row["activeMs"] += ts - intervals[-1][1]
                intervals[-1][1] = ts
            turn_open = False
            last_completed = ts
            last_status = data.get("status")
            timeout_since_completion = False
            if data.get("status") not in (None, "completed"):
                row["turnsFailed"] += 1
                errors[f"turn/{data.get('status')}"] += 1
        elif kind == "thread/tokenUsage/updated":
            usage = data.get("tokenUsage") or {}
            total = usage.get("total") or {}
            row["tokenEventSeen"] = True
            row["tokens"] = total or None
            row["costReported"] = total.get("cost", usage.get("cost"))
        elif kind == "system/interaction/lifecycle":
            interaction = data.get("interaction") or {}
            status = interaction.get("status")
            if status == "pending" and pending is None:
                pending = ts
                pending_title = ((interaction.get("payload") or {}).get("title")
                                 or interaction.get("id"))
            elif status != "pending" and pending is not None:
                duration = ts - pending
                if status == "resolved":
                    row["humanMs"] += duration
                    row["humanWaits"].append({"kind": "question", "ms": duration, "counted": True,
                                              "text": pending_title, "at": ts})
                else:
                    # A gate that timed out is not time waiting on the human (M2).
                    row["questionTimeoutMs"] += duration
                    timeout_since_completion = True
                    row["humanWaits"].append({"kind": "question", "ms": duration, "counted": False,
                                              "reason": interaction.get("statusReason") or status,
                                              "text": pending_title, "at": ts})
                pending = None
        elif kind == "system/error":
            code = (data.get("error") or {}).get("code") or data.get("code") or "error"
            errors[code] += 1
        elif kind == "system/thread/interrupted":
            infra_reasons.add(str(data.get("reason") or "host-connection-lost"))
            row["_infra_open"] = ts
        elif kind == "item/started":
            item = data.get("item") or {}
            match = WAIT_CMD_RE.search(str(item.get("command") or ""))
            if match:
                row["_wait_open"] = row.get("_wait_open") or {}
                row["_wait_open"][item.get("id")] = (ts, match.group(1))
        elif kind == "item/completed":
            item = data.get("item") or {}
            open_waits = row.get("_wait_open") or {}
            if item.get("id") in open_waits:
                start, child = open_waits.pop(item.get("id"))
                row["waitMs"] += ts - start
                row["_wait_intervals"].append([start, ts])
                if child not in row["waitedOn"]:
                    row["waitedOn"].append(child)

    if open_turn is not None:
        row["openTurn"] = True
        if thread.get("status") in ACTIVE_STATUSES:
            row["activeMs"] += events[-1]["createdAt"] - open_turn
            row["turns"] += 1
            intervals.append([open_turn, events[-1]["createdAt"]])
            errors["turn/open"] += 1
    if pending is not None:
        # A gate still pending when the log ends is real human wait so far, not
        # zero (a partial run captured mid-approval) (M2).
        duration = events[-1]["createdAt"] - pending
        row["humanMs"] += duration
        row["pendingGate"] = True
        row["humanWaits"].append({"kind": "question", "ms": duration, "counted": True,
                                  "text": pending_title, "at": events[-1]["createdAt"],
                                  "stillPending": True})
    row["_intervals"] = intervals
    if row.get("_infra_open") is not None:
        infra.append([row["_infra_open"], events[-1]["createdAt"]])
        row["_infra_open"] = None
    row["infra"] = infra
    row["infraReasons"] = sorted(infra_reasons)
    row.pop("_infra_open", None)
    row["models"] = sorted(models)
    row["model"] = row["models"][0] if len(row["models"]) == 1 else None
    row["errors"] = sorted(errors)
    row["start"] = events[0]["createdAt"]
    row["end"] = events[-1]["createdAt"]
    row["wallMs"] = row["end"] - row["start"]
    row.pop("_wait_open", None)
    return row


def _message_text(data):
    for part in data.get("input") or []:
        if isinstance(part, dict) and part.get("type") == "text" and part.get("text"):
            return part["text"][:120]
    return None


def best_wait_cause(rows, row):
    """Name the thread a parked thread was waiting on, or None. A thread parked
    while a review scans must say so rather than reading as unexplained idle (M3)."""
    idle = _subtract(_idle_intervals(row), _infra_intervals(row))
    if not idle:
        return None
    def longest(candidates):
        best = None
        for other in candidates:
            overlap = _overlap_ms(idle, _merge(other["_intervals"]))
            if overlap and (best is None or overlap > best[1]):
                best = (other, overlap)
        return best

    # Prefer a sibling: the manager's run-spanning turn is an artifact of M5 and
    # names the wrong cause. Fall back to the manager only if nothing else moved.
    return (longest([o for o in rows if o is not row and o["role"] != "manager"])
            or longest([o for o in rows if o is not row and o["role"] == "manager"]))


def build_findings(rows, ledger, manager):
    out = []
    for row in rows:
        where = f"{row['role']} {row['threadId']} ({row['title']})"
        if row["turnsFailed"]:
            out.append(f"{where}: {row['turnsFailed']} failed turn(s) — {row['errors']}")
        elif row["errors"]:
            out.append(f"{where}: {row['errors']}")
        if row["status"] == "error":
            out.append(f"{where}: thread ended in error")
        if len(row["models"]) > 1:
            out.append(f"{where}: ran {len(row['models'])} models ({', '.join(row['models'])}); "
                       f"its tokens are attributed to {row['pricingModel'] or row['models'][0]}")
        if row["cost"]["basis"] == "unpriced":
            model = row["pricingModel"] or (row["models"][0] if row["models"] else "unknown model")
            out.append(f"{where}: unpriced — tokens present but no price for {model}")
        elif row["cost"]["basis"] == "unmeasured":
            out.append(f"{where}: unmeasured — no token usage event recorded")
    for row in rows:
        infra = _infra_intervals(row)
        total = sum(end - start for start, end in infra)
        if total >= INFRA_FINDING_MS:
            where = f"{row['role']} {row['threadId']} ({row['title']})"
            reasons = ", ".join(row.get("infraReasons") or []) or "host-connection-lost"
            out.append(f"{where}: {minutes(total)} of its {minutes(row['wallMs'])} wall is host-restart "
                       f"downtime ({reasons}) — not waiting on another thread")
    for row in rows:
        if row["role"] == "manager" or row["idleMs"] <= IDLE_FINDING_MS:
            continue
        cause = best_wait_cause(rows, row)
        if not cause:
            continue
        other, overlap = cause
        row["waitingOn"] = other["threadId"]
        out.append(f"{row['role']} {row['threadId']} ({row['title']}): idle {minutes(row['idleMs'])} "
                   f"of {minutes(row['wallMs'])} wall — waiting on "
                   f"{other['role']} {other['threadId']} ({minutes(overlap)} active)")
    if manager:
        if manager["waitMs"]:
            extra = (f"; {minutes(manager['waitOutOfTurnMs'])} of it ran outside any recorded turn, "
                     f"so it is not counted as manager work either") if manager.get("waitOutOfTurnMs") else ""
            out.append(f"manager {manager['threadId']}: blocked on bb thread wait for "
                       f"{len(manager['waitedOn'])} child(ren) — {minutes(manager['waitMs'])}, "
                       f"reported as waiting, not manager work{extra}")
        if manager["questionTimeoutMs"]:
            out.append(f"manager {manager['threadId']}: a question timed out after "
                       f"{minutes(manager['questionTimeoutMs'])} and is not counted as human wait")
    for item in normalise_items(ledger):
        attempts = item.get("attempts") or []
        failed = [a for a in attempts
                  if (a.get("result", "") if isinstance(a, dict) else str(a)).startswith("failed")]
        if failed:
            why = "; ".join(a.get("result", "") if isinstance(a, dict) else str(a) for a in failed)
            out.append(f"item {item.get('id')}: {len(failed)} failed attempt(s) — {why}")
        if item.get("reviewCount", 0) >= 3:
            out.append(f"item {item.get('id')}: review hit the cap ({item['reviewCount']})")
        if item.get("status") == "blocked":
            out.append(f"item {item.get('id')}: blocked")
    return out


def _task_link(ledger, identity):
    """taskKey/taskId plus how they resolved. Explicit and `unresolved` when the
    ledger carries no task reference, never a guess from git history."""
    key = identity.get("taskKey")
    task_id = identity.get("taskId")
    resolution = identity.get("taskResolution")
    if key is None and isinstance(ledger, dict):
        ticket = ledger.get("ticket")
        if isinstance(ticket, dict) and ticket.get("key"):
            key = ticket["key"]
            task_id = task_id if task_id is not None else ticket.get("id")
            resolution = "ledger-key"
        elif isinstance(ledger.get("run"), str) and TASK_KEY_RE.match(ledger["run"]):
            key = ledger["run"]
            resolution = "run-name"
    if resolution is None:
        resolution = "resolved" if key else "unresolved"
    return key, task_id, resolution


def assemble_record(threads, ledger, identity, pricing=None):
    """events + ledger + run identity -> the run record.

    `threads` is a list of `{"meta": <bb thread>, "events": [...]}`. Pure: no
    filesystem or network access; `pricing` is the model->price table.
    """
    pricing = pricing or {}
    ledger = ledger if isinstance(ledger, dict) else {}
    rows = [analyse_thread(t["meta"], t["events"]) for t in threads]
    for row in rows:
        row["pricingModel"] = next((m for m in row["models"] if price_for(m, pricing)), None)
        price = price_for(row["pricingModel"], pricing) if row["pricingModel"] else None
        row["cost"] = cost_state(row, price)
        row["idleMs"] = max(0, row["wallMs"] - row["activeMs"])
        # A wait that ran past the end of its turn is not work done in a turn: clip
        # it, or `activeMs - waitMs` collapses real manager work to ~0 (F4).
        clipped = _overlap_ms(_merge(row.get("_wait_intervals") or []), _merge(row["_intervals"]))
        row["waitInTurnMs"] = clipped
        row["waitOutOfTurnMs"] = max(0, row["waitMs"] - clipped)
        row["workMs"] = (max(0, row["activeMs"] - clipped) if row["role"] == "manager"
                         else row["activeMs"])

    manager_id = identity.get("managerThreadId")
    manager = next((r for r in rows if r["threadId"] == manager_id), rows[0] if rows else None)
    children = [r for r in rows if r is not manager]

    starts = [r["start"] for r in rows if r["start"]]
    ends = [r["end"] for r in rows if r["end"]]
    run_start = min(starts) if starts else None
    run_end = max(ends) if ends else None
    span = (run_end - run_start) if starts and ends else 0
    child_ends = [r["end"] for r in children if r["end"]]
    # M1: the work window is the first event to the last child settle (the end
    # of the manager's turn during which that settle landed), not the run's span
    # — a long idle tail must not read as work.
    if child_ends and run_start is not None:
        settle = max(child_ends)
        containing = [end for start, end in (manager["_intervals"] if manager else [])
                      if start <= settle <= end]
        work_window = max(0, (containing[-1] if containing else settle) - run_start)
    else:
        work_window = span

    items = normalise_items(ledger)
    project = identity.get("project")
    repos = set(identity.get("repos") or [])
    for item in items:
        if isinstance(item.get("repo"), str) and item["repo"]:
            repos.add(item["repo"])
    if project:
        repos.add(project)

    by_role = collections.defaultdict(lambda: {"role": None, "activeMs": 0, "threads": 0, "turns": 0})
    for row in rows:
        phase = by_role[row["role"]]
        phase["role"] = row["role"]
        phase["activeMs"] += row["workMs"]
        phase["threads"] += 1
        phase["turns"] += row["turns"]

    reported = [r["cost"]["reported"] for r in rows if r["cost"]["reported"] is not None]
    estimated = [r["cost"]["estimated"] for r in rows if r["cost"]["estimated"] is not None]
    run_reported = sum(reported) if reported else None
    run_estimated = sum(estimated) if estimated else None
    if run_reported is not None:
        basis = "reported"
    elif run_estimated is not None:
        basis = "estimated"
    elif any(r["tokenEventSeen"] for r in rows):
        basis = "unpriced"
    else:
        basis = "unmeasured"
    cost = {
        "reported": run_reported,
        "estimated": run_estimated,
        "basis": basis,
        "threadsPriced": sum(1 for r in rows if r["cost"]["basis"] in ("reported", "estimated")),
        "threadsUnpriced": sum(1 for r in rows if r["cost"]["basis"] == "unpriced"),
        "threadsUnmeasured": sum(1 for r in rows if r["cost"]["basis"] == "unmeasured"),
    }

    task_key, task_id, task_resolution = _task_link(ledger, identity)
    partial = (any(r["status"] in ACTIVE_STATUSES or r["openTurn"] for r in rows)
               or any(item.get("status") in RUNNING_ITEM_STATUSES for item in items))

    run = {
        "managerThreadId": manager_id,
        "name": identity.get("name") or ledger.get("run"),
        "taskKey": task_key,
        "taskId": task_id,
        "taskResolution": task_resolution,
        "project": project,
        "repos": sorted(repos),
        "flow": identity.get("flow") or ledger.get("flow"),
        "startedAt": iso(run_start),
        "endedAt": iso(run_end),
        "spanMs": span,
        "workWindowMs": work_window,
        "managerWaitMs": manager["waitMs"] if manager else 0,
        "humanWaitMs": manager["humanMs"] if manager else 0,
        "questionTimeoutMs": manager["questionTimeoutMs"] if manager else 0,
        "humanWaits": manager["humanWaits"] if manager else [],
        "skillSha": None,
        "provenance": "unavailable",
        "models": sorted({m for r in rows for m in r["models"]}),
        "threads": len(rows),
        "turns": sum(r["turns"] for r in rows),
        "cost": cost,
    }
    record = {
        "schemaVersion": SCHEMA_VERSION,
        "run": run,
        "phases": [by_role[k] for k in sorted(by_role)],
        "threads": rows,
        "items": items,
        "findings": build_findings(rows, ledger, manager),
        "partial": partial,
    }
    for row in rows:
        row.pop("_intervals", None)
        row.pop("_wait_intervals", None)
        row.pop("costReported", None)
    return record


def slugify(value):
    return re.sub(r"[^a-z0-9]+", "-", str(value or "").lower()).strip("-")


def record_dirname(record):
    """`<date>-<project>-<slug>-<threadId>`: browsable, unique by thread id, and
    stable for the same run so a re-run rewrites the record in place."""
    run = record["run"]
    date = (run.get("startedAt") or "unknown-date")[:10]
    project = slugify(run.get("project")) or "unknown-project"
    slug = slugify(run.get("name")) or slugify(run.get("managerThreadId")) or "run"
    return f"{date}-{project}-{slug}-{run['managerThreadId']}"


def self_test():
    """Assert the pure logic: pricing, cost arithmetic, ledger shapes, M1-M5."""
    price = {"prompt": 1e-6, "completion": 1e-5, "input_cache_read": 1e-7}
    tokens = {"inputTokens": 1000, "cacheReadInputTokens": 2000,
              "cacheWriteInputTokens": 0, "outputTokens": 100}
    got = cost_of(tokens, price)
    want = 1000e-6 + 2000e-7 + 100e-5
    assert abs(got - want) < 1e-12, (got, want)
    assert cost_of(None, price) is None and cost_of(tokens, None) is None

    table = {"anthropic/claude-sonnet-5": price}
    assert price_for("openrouter/anthropic/claude-sonnet-5", table) == price
    assert price_for("opencode/deepseek-v4-flash", table) is None

    assert normalise_items({"items": {"01": {"status": "done"}}}) == [{"status": "done", "id": "01"}]
    assert normalise_items({"items": [{"id": "a"}]}) == [{"id": "a"}]
    assert normalise_items({}) == []
    assert normalise_items({"items": [None, "x", {"id": "y"}]}) == [{"id": None}, {"id": "x"}, {"id": "y"}]

    # unavailable cost never renders as $0.00
    assert format_cost({"reported": None, "estimated": None, "basis": "unpriced"}) == "unpriced"
    assert format_cost({"reported": None, "estimated": None, "basis": "unmeasured"}) == "unmeasured"
    assert "$0.00" not in format_cost({"reported": None, "estimated": None, "basis": "unpriced"})

    # --- a synthetic run exercising M1-M5 ---------------------------------
    T0 = 1_700_000_000_000

    def ev(kind, offset, data=None):
        return {"type": kind, "createdAt": T0 + offset, "data": data or {}}

    def thread(tid, title, status, events, is_manager=False, provider="pi"):
        return {"meta": {"id": tid, "title": title, "status": status,
                         "providerId": provider, "isManager": is_manager},
                "events": events}

    sonnet = {"execution": {"model": "openrouter/anthropic/claude-sonnet-5"}}
    unknown = {"execution": {"model": "openrouter/acme/unknown-model"}}
    manager_events = [
        ev("client/turn/requested", 0, dict(sonnet, initiator="user", target={"kind": "thread-start"})),
        ev("turn/started", 0),
        ev("turn/completed", 60_000, {"status": "completed"}),
        ev("client/turn/requested", 60_000, dict(sonnet, initiator="system", target={"kind": "new-turn"})),
        ev("turn/started", 60_000),
        ev("item/started", 70_000, {"item": {"id": "w1", "type": "commandExecution",
                                             "command": "bb thread wait thr_c1 --status idle --timeout 1800 --json"}}),
        ev("item/completed", 190_000, {"item": {"id": "w1", "type": "commandExecution",
                                                "command": "bb thread wait thr_c1 --status idle --timeout 1800 --json"}}),
        ev("turn/completed", 200_000, {"status": "completed"}),
        ev("client/turn/requested", 500_000, dict(sonnet, initiator="user", target={"kind": "new-turn"},
                                                  input=[{"type": "text", "text": "yes, approved"}])),
        ev("turn/started", 500_000),
        ev("system/interaction/lifecycle", 510_000, {"interaction": {"id": "q1", "status": "pending",
                                                                    "payload": {"kind": "plugin", "title": "Approve?"}}}),
        ev("turn/completed", 520_000, {"status": "completed"}),
        ev("system/interaction/lifecycle", 900_000, {"interaction": {"id": "q1", "status": "interrupted",
                                                                    "statusReason": "timeout",
                                                                    "payload": {"kind": "plugin", "title": "Approve?"}}}),
        ev("client/turn/requested", 1_500_000, dict(sonnet, initiator="user", target={"kind": "new-turn"})),
    ]
    worker_priced = [
        ev("client/turn/requested", 80_000, sonnet),
        ev("turn/started", 80_000),
        ev("thread/tokenUsage/updated", 180_000, {"tokenUsage": {"total": {
            "inputTokens": 1000, "cachedInputTokens": 2000, "cacheReadInputTokens": 2000,
            "cacheWriteInputTokens": 0, "outputTokens": 100, "reasoningOutputTokens": 0}}}),
        ev("turn/completed", 180_000, {"status": "completed"}),
    ]
    worker_unmeasured = [
        ev("client/turn/requested", 80_000, {"execution": {"model": "openrouter/deepseek/deepseek-v4-flash-0731"}}),
        ev("turn/started", 80_000),
        ev("turn/completed", 120_000, {"status": "completed"}),
        ev("agentMessage", 1_000_000, {}),
    ]
    review_unpriced = [
        ev("client/turn/requested", 300_000, unknown),
        ev("turn/started", 300_000),
        ev("thread/tokenUsage/updated", 800_000, {"tokenUsage": {"total": {
            "inputTokens": 10, "outputTokens": 5, "cacheReadInputTokens": 0, "cacheWriteInputTokens": 0}}}),
        ev("turn/completed", 800_000, {"status": "completed"}),
    ]
    # A manager `bb thread tell` follow-up to a worker is shaped exactly like a
    # human message (initiator "user"); on a child it must not count as human.
    worker_told = [
        ev("client/turn/requested", 80_000, sonnet),
        ev("turn/started", 80_000),
        ev("turn/completed", 120_000, {"status": "completed"}),
        ev("client/turn/requested", 300_000, dict(sonnet, initiator="user", source="tell",
                                                  target={"kind": "new-turn"},
                                                  input=[{"type": "text",
                                                          "text": "Code review found 3 findings"}])),
    ]
    threads = [
        thread("thr_mgr", "DOT-11 via orchestrate-bb-threads", "idle", manager_events, is_manager=True),
        thread("thr_c1", "01 · worker", "idle", worker_priced),
        thread("thr_cw", "06 · worker", "idle", worker_unmeasured),
        thread("thr_cr", "REVIEW 01 · thing", "idle", review_unpriced),
        thread("thr_ct", "02 · worker", "idle", worker_told),
    ]
    item = {"id": "01", "status": "done", "reviewCount": 1, "blockedBy": []}
    ledger_list = {"run": "DOT-11", "flow": "A", "items": [item]}
    ledger_dict = {"run": "DOT-11", "flow": "A", "items": {"01": dict(item)}}
    ledger_no_task = {"items": [dict(item)]}
    identity = {"managerThreadId": "thr_mgr", "project": "bb-plugins"}
    pricing = {"anthropic/claude-sonnet-5": price}

    rec = assemble_record(threads, ledger_list, identity, pricing)

    # ledger `items` list vs dict -> the same record, and never a failed write
    assert rec == assemble_record(threads, ledger_dict, identity, pricing)

    # M1: span, work window and the manager's wait are three quantities
    assert rec["run"]["spanMs"] == 1_500_000, rec["run"]["spanMs"]
    assert rec["run"]["workWindowMs"] == 1_000_000, rec["run"]["workWindowMs"]
    assert rec["run"]["spanMs"] > rec["run"]["workWindowMs"]
    assert rec["run"]["managerWaitMs"] == 120_000, rec["run"]["managerWaitMs"]

    # M2: a message-borne approval counts; a timed-out gate does not
    assert rec["run"]["humanWaitMs"] == 300_000, rec["run"]["humanWaitMs"]
    assert rec["run"]["questionTimeoutMs"] == 390_000, rec["run"]["questionTimeoutMs"]

    # a tell-shaped follow-up is human wait on the manager, never on a child
    ct = next(t for t in rec["threads"] if t["threadId"] == "thr_ct")
    assert ct["humanMs"] == 0, ct["humanMs"]
    assert ct["humanWaits"] == [], ct["humanWaits"]

    # a gate still pending when the log ends is real elapsed wait, not zero
    pending_gate_events = [
        ev("client/turn/requested", 0, dict(sonnet, initiator="user", target={"kind": "thread-start"})),
        ev("turn/started", 0),
        ev("system/interaction/lifecycle", 100_000, {"interaction": {"id": "q2", "status": "pending",
                                                                      "payload": {"kind": "plugin", "title": "Still open?"}}}),
        ev("agentMessage", 400_000, {}),
    ]
    pending_rec = assemble_record(
        [thread("thr_pg", "DOT-11 gate", "idle", pending_gate_events, is_manager=True)],
        ledger_list, identity, pricing)
    assert pending_rec["run"]["humanWaitMs"] == 300_000, pending_rec["run"]["humanWaitMs"]
    assert pending_rec["run"]["questionTimeoutMs"] == 0
    assert pending_rec["run"]["humanWaits"][-1]["stillPending"] is True
    assert pending_rec["threads"][0]["pendingGate"] is True

    # M5: the manager's wait is waiting, not manager work
    mgr = next(t for t in rec["threads"] if t["threadId"] == "thr_mgr")
    assert mgr["activeMs"] == 220_000 and mgr["waitMs"] == 120_000
    assert mgr["workMs"] == 100_000, mgr["workMs"]

    # M6: a wait that outlives its turn is not turn work, and a host restart is
    # downtime, not a thread waiting on a sibling (F3/F4 of the 2026-09-23 retro).
    out_of_turn = [
        ev("client/turn/requested", 0, dict(sonnet, initiator="user", target={"kind": "thread-start"})),
        ev("turn/started", 0),
        ev("item/started", 50_000, {"item": {"id": "w9", "type": "commandExecution",
                                             "command": "bb thread wait thr_rs --status idle"}}),
        ev("item/completed", 300_000, {"item": {"id": "w9", "type": "commandExecution",
                                                "command": "bb thread wait thr_rs --status idle"}}),
        ev("turn/completed", 100_000, {"status": "completed"}),
    ]
    restarted = [
        ev("client/turn/requested", 0, dict(sonnet, initiator="user", target={"kind": "thread-start"})),
        ev("turn/started", 0),
        ev("turn/completed", 100_000, {"status": "interrupted"}),
        ev("system/error", 100_000, {"code": "thread_command_failed"}),
        ev("system/thread/interrupted", 100_000, {"reason": "host-daemon-restarted"}),
        ev("agentMessage", 800_000, {}),
    ]
    infra_rec = assemble_record(
        [thread("thr_ot", "DOT-11 run", "idle", out_of_turn, is_manager=True),
         thread("thr_rs", "REVIEW 09 · thing", "idle", restarted)],
        ledger_list, {"managerThreadId": "thr_ot", "project": "bb-plugins"}, pricing)
    ot = next(t for t in infra_rec["threads"] if t["threadId"] == "thr_ot")
    assert ot["waitMs"] == 250_000 and ot["waitInTurnMs"] == 50_000, ot
    assert ot["waitOutOfTurnMs"] == 200_000, ot
    assert ot["workMs"] == 50_000, ot["workMs"]
    rs = next(t for t in infra_rec["threads"] if t["threadId"] == "thr_rs")
    assert rs["infra"] == [[T0 + 100_000, T0 + 800_000]], rs["infra"]
    assert rs["infraReasons"] == ["host-daemon-restarted"]
    assert any("host-restart downtime" in f and "thr_rs" in f for f in infra_rec["findings"]), \
        infra_rec["findings"]
    assert rs["waitingOn"] is None
    assert not any("idle" in f and "waiting on" in f and "thr_rs" in f for f in infra_rec["findings"]), \
        infra_rec["findings"]

    # M7: a resumed turn extends its interrupted interval instead of vanishing
    resumed = [
        ev("client/turn/requested", 0, dict(sonnet, initiator="user", target={"kind": "thread-start"})),
        ev("turn/started", 0),
        ev("turn/completed", 100_000, {"status": "interrupted"}),
        ev("system/error", 100_000, {"code": "thread_command_failed"}),
        ev("system/thread/interrupted", 100_000, {"reason": "host-daemon-restarted"}),
        ev("item/started", 200_000, {"item": {"id": "z1", "type": "reasoning"}}),
        ev("turn/completed", 500_000, {"status": "completed"}),
    ]
    resumed_rec = assemble_record(
        [thread("thr_rr", "REVIEW 09 · thing", "idle", resumed)],
        ledger_list, {"managerThreadId": "thr_rr", "project": "bb-plugins"}, pricing)
    rrow = resumed_rec["threads"][0]
    assert rrow["turns"] == 1 and rrow["turnsFailed"] == 1, rrow
    assert rrow["activeMs"] == 500_000, rrow["activeMs"]
    assert rrow["idleMs"] == 0, rrow["idleMs"]

    # cost provenance: reported is null, estimated populated, basis says estimated
    c1 = next(t for t in rec["threads"] if t["threadId"] == "thr_c1")
    assert c1["cost"]["reported"] is None
    assert abs(c1["cost"]["estimated"] - 0.0022) < 1e-12, c1["cost"]
    assert c1["cost"]["basis"] == "estimated"

    # M4: unmeasured != unpriced, and neither is 0.00
    cw = next(t for t in rec["threads"] if t["threadId"] == "thr_cw")
    cr = next(t for t in rec["threads"] if t["threadId"] == "thr_cr")
    assert cw["cost"]["basis"] == "unmeasured" and cw["cost"]["estimated"] is None
    assert cr["cost"]["basis"] == "unpriced" and cr["cost"]["estimated"] is None
    assert cw["cost"]["basis"] != cr["cost"]["basis"]
    assert any("unmeasured" in f for f in rec["findings"])
    assert any("unpriced" in f for f in rec["findings"])

    # M3: an idle finding names what the thread was waiting on, or does not fire
    assert any("waiting on review thr_cr" in f for f in rec["findings"]), rec["findings"]
    assert not any(f.startswith("manager ") and "idle" in f for f in rec["findings"])
    assert not any("span" in f for f in rec["findings"]), rec["findings"]
    # ...and the same cause is machine-readable on the thread, not only in prose
    assert all("waitingOn" in t for t in rec["threads"])
    assert cw["waitingOn"] == "thr_cr", cw["waitingOn"]
    assert mgr["waitingOn"] is None

    # reserved slot and task link
    assert rec["run"]["skillSha"] is None and rec["run"]["provenance"] == "unavailable"
    assert rec["run"]["name"] == "DOT-11"
    assert rec["run"]["taskKey"] == "DOT-11" and rec["run"]["taskResolution"] == "run-name"
    assert rec["run"]["repos"] == ["bb-plugins"]
    none_task = assemble_record(threads, ledger_no_task, identity, pricing)
    assert "taskKey" in none_task["run"] and "taskId" in none_task["run"]
    assert none_task["run"]["taskKey"] is None and none_task["run"]["taskId"] is None
    assert none_task["run"]["taskResolution"] == "unresolved"

    # a ledger that is not an object at all cannot make the write fail
    assert assemble_record(threads, [], identity, pricing)["items"] == []
    assert assemble_record(threads, "garbage", identity, pricing)["items"] == []

    # a settled run is not partial; a live thread makes it partial
    assert rec["partial"] is False
    live = assemble_record([threads[0], thread("thr_live", "02 · worker", "active", worker_priced)],
                           ledger_list, identity, pricing)
    assert live["partial"] is True

    # directory name is the browsable key, stable across invocations
    name = record_dirname(rec)
    assert name == record_dirname(assemble_record(threads, ledger_dict, identity, pricing)), name
    assert name == "2023-11-14-bb-plugins-dot-11-thr_mgr", name
    assert re.fullmatch(r"\d{4}-\d{2}-\d{2}-[a-z0-9-]+-thr_mgr", name)

    row = {"role": "worker", "threadId": "thr_x", "title": "01 · thing", "turnsFailed": 0,
           "errors": [], "status": "idle", "wallMs": 60_000, "activeMs": 60_000,
           "idleMs": 0, "models": ["m1", "m2"], "pricingModel": "m1", "_intervals": [[0, 60_000]],
           "cost": {"reported": None, "estimated": 1.0, "basis": "estimated"}}
    assert any("2 models" in f for f in build_findings([row], None, None)), build_findings([row], None, None)
    assert build_findings([dict(row, models=["m1"])], None, None) == []
    park = dict(row, models=["m1"], idleMs=20 * 60_000, start=T0, end=T0 + 1_200_000,
                _intervals=[[T0, T0 + 60_000]])
    assert not any("idle" in f for f in build_findings([park], None, None)), build_findings([park], None, None)
    print("self-test OK")


def thread_events(tid):
    try:
        raw = sh("bb", "thread", "log", tid, "--json", "--all")
        return json.loads(raw, strict=False) if raw.strip() else []
    except (RuntimeError, json.JSONDecodeError):
        return []


def children_of(manager_id):
    out = bb("thread", "list", "--parent-thread", manager_id, "--json")
    known = {t["id"] for t in out}
    for archived in bb("thread", "list", "--parent-thread", manager_id, "--archived", "--json"):
        if archived["id"] not in known:
            out.append(archived)
    return out


def fetch_run(manager_id):
    manager = bb("thread", "show", manager_id, "--json")["thread"]
    manager["isManager"] = True
    return [{"meta": t, "events": thread_events(t["id"])} for t in [manager] + children_of(manager_id)]


def project_name(project_id):
    if not project_id:
        return None
    try:
        for project in bb("project", "list", "--include-personal", "--json"):
            if project.get("id") == project_id:
                return project.get("name")
    except (RuntimeError, json.JSONDecodeError):
        return None
    return None


def openrouter_pricing(cache_path, enabled):
    """model id -> per-token USD prices, or {} when unavailable."""
    if not enabled:
        return {}
    if cache_path and os.path.exists(cache_path) and time.time() - os.path.getmtime(cache_path) < PRICING_TTL:
        try:
            return json.load(open(cache_path))
        except json.JSONDecodeError:
            pass
    try:
        with urllib.request.urlopen(PRICING_URL, timeout=15) as r:
            payload = json.load(r)["data"]
    except Exception as exc:  # offline, or the endpoint moved
        print(f"# pricing unavailable ({exc}); reporting tokens only", file=sys.stderr)
        return {}
    table = {
        m["id"]: {k: float(v) for k, v in (m.get("pricing") or {}).items()
                  if isinstance(v, str) and v.replace(".", "", 1).isdigit()}
        for m in payload
    }
    if cache_path:
        os.makedirs(os.path.dirname(cache_path), exist_ok=True)
        json.dump(table, open(cache_path, "w"))
    return table


def print_table(record, no_pricing):
    run = record["run"]
    cost = run["cost"]
    print(f"RUN {run['managerThreadId']}  name={run['name'] or '-'}  flow={run['flow'] or '-'}  "
          f"project={run['project'] or '-'}  partial={str(record['partial']).lower()}")
    print(f"    span={minutes(run['spanMs'])}  work-window={minutes(run['workWindowMs'])}  "
          f"manager-wait={minutes(run['managerWaitMs'])}  human={minutes(run['humanWaitMs'])}  "
          f"threads={run['threads']}  turns={run['turns']}")
    if no_pricing:
        print("    cost: pricing disabled (--no-pricing)")
    elif cost["basis"] == "unmeasured":
        print("    cost: unavailable (no token usage recorded)")
    elif cost["basis"] == "unpriced":
        print("    cost: unavailable (tokens present, no matching price)")
    else:
        print(f"    cost ${cost['estimated'] if cost['basis'] == 'estimated' else cost['reported']:.2f} "
              f"{cost['basis']} ({cost['threadsPriced']}/{run['threads']} priced; "
              f"{cost['threadsUnpriced']} unpriced; {cost['threadsUnmeasured']} unmeasured)")
    print("\nPHASES (work time summed for the manager, waits excluded; phases overlap)")
    for phase in sorted(record["phases"], key=lambda p: -p["activeMs"]):
        print(f"    {phase['role']:<10} {minutes(phase['activeMs']):>8}  "
              f"over {phase['threads']:>2} thread(s), {phase['turns']:>2} turn(s)")
    print("\nTHREADS  (at = dispatch offset from the run's first event)")
    starts = [t["start"] for t in record["threads"] if t["start"]]
    run_start = min(starts) if starts else 0
    print(f"    {'thread':<16}{'role':<10}{'model':<40}{'turns':>6}{'at':>8}{'wall':>8}"
          f"{'active':>8}{'wait':>7}{'idle':>8}{'cost':>10}  errors")
    for row in sorted(record["threads"], key=lambda r: r["start"] or 0):
        at = "+" + minutes((row["start"] or run_start) - run_start)
        print(f"    {row['threadId']:<16}{row['role']:<10}{(row['model'] or '-'):<40}{row['turns']:>6}"
              f"{at:>8}{minutes(row['wallMs']):>8}{minutes(row['activeMs']):>8}"
              f"{minutes(row['waitMs']):>7}{minutes(row['idleMs']):>8}{format_cost(row['cost']):>10}  "
              f"{','.join(row['errors']) or ''}")
    print("\nFINDINGS")
    print("\n".join(f"    - {f}" for f in record["findings"]) or "    (none)")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("manager", nargs="?", help="manager thread id of the run")
    ap.add_argument("--json", action="store_true", help="emit the run record as JSON")
    ap.add_argument("--no-pricing", action="store_true", help="skip cost, report tokens only")
    ap.add_argument("--ledger", help="ledger path (default: the manager's orchestration.json)")
    ap.add_argument("--output-dir", help="write run.json into this directory")
    ap.add_argument("--self-test", action="store_true", help="assert the pure logic and exit")
    args = ap.parse_args()

    if args.self_test:
        self_test()
        return
    if not args.manager:
        ap.error("a manager thread id is required")

    data_dir = bb("status", "--json")["dataDir"]
    storage = os.path.join(data_dir, "thread-storage", args.manager)
    ledger_path = args.ledger or os.path.join(storage, "orchestration.json")
    ledger = None
    if os.path.exists(ledger_path):
        try:
            ledger = json.load(open(ledger_path))
        except json.JSONDecodeError:
            ledger = None

    threads = fetch_run(args.manager)
    manager_meta = threads[0]["meta"]
    pricing = openrouter_pricing(os.path.join(data_dir, "cache", "openrouter-models.json"),
                                 not args.no_pricing)
    record = assemble_record(threads, ledger,
                             {"managerThreadId": args.manager,
                              "project": project_name(manager_meta.get("projectId"))},
                             pricing)

    if args.output_dir:
        os.makedirs(args.output_dir, exist_ok=True)
        out_path = os.path.join(args.output_dir, "run.json")
        with open(out_path, "w") as fh:
            json.dump(record, fh, indent=2)
        print(f"# wrote {out_path}", file=sys.stderr)

    if args.json:
        print(json.dumps(record, indent=2))
        return
    print_table(record, args.no_pricing)


if __name__ == "__main__":
    main()
