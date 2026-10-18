#!/usr/bin/env python3
"""Read a BB orchestration run into numbers (adapter).

This script is BB's **telemetry adapter**: the facts come from `bb thread
log --json` events, normalised into one **lane** per thread, plus the run's
`orchestration.json` ledger. `orchestrate-core/scripts/ledger_read.py` owns the
record — the figures, the role vocabulary and the output schema, which is the
same one Herdr's adapter emits. A run that outlived one manager's context holds
one ledger and more than one manager thread: the ledger's `executors` names
them, oldest first, and every manager in it plus every child of each is part of
the run. Read-only against the run: nothing is written except the pricing cache
and, when `--output-dir` is given, the record.

    run-metrics.py <manager-thread-id> [--json] [--no-pricing] [--ledger PATH]
    run-metrics.py <manager-thread-id> --output-dir DIR   # also writes run.json
    run-metrics.py --self-test

`lane_of` is the adapter's own: one analysed thread -> one lane, pure and
covered by `--self-test`. `analyse_thread` is pure too; prices are applied on
the lane.

Timing caveat: in a shared-worktree run the phases overlap on purpose, so
per-role totals sum to more than the run's wall-clock span. Both are reported.

Token caveat: pi emits one `thread/tokenUsage/updated` per turn and it is that
request's usage, not the turn's or the thread's. `toolItems` counts tool items
per thread as a floor on the requests-per-turn denominator; it is deliberately
not turned into a dollar figure, because the multiplier is not measurable.

Retro caveat: the retro thread a run spawns at its end is the run's recorder,
not the run. It keeps its own lane and its cost, and it never stretches the
span or makes a terminal run read as partial.
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

TASK_KEY_RE = re.compile(r"^[A-Z][A-Z0-9]*-\d+$")
WAIT_CMD_RE = re.compile(r"(?:^|[;&|]\s*)bb\s+thread\s+wait\s+(thr_\w+)")

ACTIVE_STATUSES = {"active", "starting", "running", "settling"}

# The record is not this adapter's: orchestrate-core owns one reader, one role
# vocabulary and one schema, and both runtimes' adapters feed it lanes.
sys.path.insert(
    0,
    os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
                 "orchestrate-core", "scripts"),
)
from ledger_read import fmt_seconds, normalise_items, parse_ts, read_run  # noqa: E402


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
    if t.startswith("RETRO"):
        return "retro"
    return "worker"


def manager_ids(manager_id, chain=()):
    """The run's managers, identity first, without duplicates or blanks."""
    return [manager_id] + [tid for tid in chain if tid and tid != manager_id]


def iso(ms):
    if ms is None:
        return None
    return datetime.datetime.fromtimestamp(ms / 1000, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


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


def _human_only_ms(managers, rows):
    """Human wait that overlaps no thread's active turn. That is the part a
    two-day \"yes\" adds to the span, and the part orchestrator time drops.

    Read from every manager in the run's chain, not only the thread that started
    it: a successor that asked the operator a question waited just as humanly.
    """
    human = _merge([wait["at"] - wait["ms"], wait["at"]]
                   for manager in managers
                   for wait in manager["humanWaits"]
                   if wait.get("counted") and wait.get("ms") and wait.get("at"))
    work = _merge(iv for row in rows for iv in (row.get("_intervals") or []))
    return sum(end - start for start, end in _subtract(human, work))


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


def analyse_thread(thread, events):
    """One thread's events -> timings, tokens and the raw facts cost is built on.

    Pure: no filesystem, no network. Prices are applied in `record_of`.
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
        "tokens": None, "tokenEventSeen": False, "tokenEpochs": 0, "costReported": None,
        "toolItems": 0, "tokensSource": None, "retroInFlight": False,
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
    token_totals = []
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
                # An approval that arrives as a plain message, including after
                # the question widget timed out. The whole gap is waiting on
                # the human — a two-day "yes" is not orchestrator time.
                gap = ts - last_completed
                row["humanMs"] += gap
                row["humanWaits"].append({"kind": "message", "ms": gap, "counted": True,
                                          "text": _message_text(data), "at": ts,
                                          "reason": "after timeout" if timeout_since_completion else None})
                timeout_since_completion = False
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
            if total:
                token_totals.append(total)
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
                    # The widget died; the wait does not. Counted when the
                    # reply arrives, or to the log end if it never does.
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
            # A tool result is one model request to consume it, so tool items are
            # a floor on how many requests a turn made — the denominator a
            # snapshot-based token figure is short by (see the module docstring).
            if (item.get("type") or "") not in ("reasoning", "agentMessage"):
                row["toolItems"] += 1
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
            if row["role"] == "retro":
                # The retro is spawned after `finishedAt` and nobody waits for
                # it, so an in-flight retro is normal, not an open turn of the
                # run. Flagged on the row, kept out of the findings (F5).
                row["retroInFlight"] = True
            else:
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
    elif timeout_since_completion and last_completed is not None and not turn_open:
        # Timed out and never answered. The tail to the log end is still the human.
        duration = events[-1]["createdAt"] - last_completed
        if duration > 0:
            row["humanMs"] += duration
            row["humanWaits"].append({"kind": "question", "ms": duration, "counted": True,
                                      "reason": "unanswered", "at": events[-1]["createdAt"]})
    # A thread that compacts resets its cumulative counter: a total that drops
    # below the running one starts a new epoch. Sum the epochs so compaction
    # does not shrink the thread's tokens (and cost) to the surviving epoch.
    token_epochs = []
    current = None
    for total in token_totals:
        if current is not None and (total.get("totalTokens") or 0) < (current.get("totalTokens") or 0):
            token_epochs.append(current)
        current = total
    if current is not None:
        token_epochs.append(current)
    row["tokenEpochs"] = len(token_epochs)
    if token_epochs:
        summed = collections.Counter()
        for epoch in token_epochs:
            for key, value in epoch.items():
                if isinstance(value, (int, float)) and not isinstance(value, bool) and key != "cost":
                    summed[key] += value
        row["tokens"] = dict(summed) or None
    if row["tokens"]:
        row["tokensSource"] = "snapshot"
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


def _task_link(ledger, identity):
    """taskKey/taskId plus how they resolved. Explicit and `unresolved` when the
    ledger carries no task reference, never a guess from git history."""
    key = identity.get("taskKey")
    task_id = identity.get("taskId")
    resolution = identity.get("taskResolution")
    if key is None and isinstance(ledger, dict):
        task = ledger.get("task")
        if isinstance(task, dict) and task.get("key"):
            key = task["key"]
            task_id = task_id if task_id is not None else task.get("id")
            resolution = "ledger-key"
        elif isinstance(task, str) and TASK_KEY_RE.match(task):
            key = task
            resolution = "run-name"
    if resolution is None:
        resolution = "resolved" if key else "unresolved"
    return key, task_id, resolution


def lane_of(row, pricing):
    """One analysed thread -> one lane, in the shared shape. Times in seconds."""
    price = price_for(row.get("pricingModel"), pricing) if row.get("pricingModel") else None
    cost = cost_state(row, price)
    intervals = row.get("_intervals") or []
    clipped = _overlap_ms(_merge(row.get("_wait_intervals") or []), _merge(intervals))
    work_ms = max(0, row["activeMs"] - clipped) if row["role"] == "manager" else row["activeMs"]
    usd = cost["reported"] if cost["reported"] is not None else cost["estimated"]
    return {
        "name": row["threadId"], "title": row.get("title"), "role": row["role"],
        "provider": row.get("provider"), "status": row.get("status"),
        "firstTs": iso(row.get("start")), "lastTs": iso(row.get("end")),
        "spanSec": row["wallMs"] / 1000, "activeSec": row["activeMs"] / 1000,
        "workSec": work_ms / 1000,
        "intervals": [[iso(s), iso(e)] for s, e in intervals],
        "waitSec": row["waitMs"] / 1000,
        "waitOutOfTurnSec": max(0, row["waitMs"] - clipped) / 1000,
        "humanSec": row["humanMs"] / 1000, "humanWaits": row.get("humanWaits") or [],
        "questionTimeoutSec": row["questionTimeoutMs"] / 1000,
        "models": row.get("models") or [], "model": row.get("model"),
        "tokens": row.get("tokens"), "turns": row.get("turns", 0),
        "turnsFailed": row.get("turnsFailed", 0), "errors": row.get("errors") or [],
        "openTurn": row.get("openTurn", False), "retroInFlight": row.get("retroInFlight", False),
        "infra": [[iso(s), iso(e)] for s, e in (row.get("infra") or [])],
        "infraReasons": row.get("infraReasons") or [],
        "toolItems": row.get("toolItems", 0), "tokensSource": row.get("tokensSource"),
        "waitedOn": row.get("waitedOn") or [], "pendingGate": row.get("pendingGate", False),
        "costUsd": usd if usd is not None else 0.0,
        "cost": {"basis": cost["basis"], "reported": cost["reported"],
                 "estimated": cost["estimated"]},
    }


def record_of(threads, ledger, identity, pricing=None, pricing_meta=None):
    """events + ledger + run identity -> the shared run record.

    `threads` is a list of `{"meta": <bb thread>, "events": [...]}`. Pure: no
    filesystem or network access; `pricing` is the model->price table. What the
    shared schema does not carry — BB's event-derived human time, its work
    window, the pricing provenance — sits in `record["extras"]`.
    """
    pricing = pricing or {}
    ledger = ledger if isinstance(ledger, dict) else {}
    rows = []
    for thread in threads:
        row = analyse_thread(thread["meta"], thread["events"])
        row["pricingModel"] = next((m for m in row["models"] if price_for(m, pricing)), None)
        rows.append(row)
    lanes = [lane_of(row, pricing) for row in rows]

    manager_id = identity.get("managerThreadId")
    manager = next((r for r in rows if r["threadId"] == manager_id), rows[0] if rows else None)
    record = read_run(ledger, lanes, "bb",
                      feature=identity.get("name") or (ledger or {}).get("feature"),
                      project=identity.get("project"))

    work_rows = [r for r in rows if r["role"] != "retro"]
    starts = [r["start"] for r in work_rows if r["start"]]
    child_ends = [r["end"] for r in work_rows if r is not manager and r["end"]]
    run_start = min(starts) if starts else None
    if child_ends and run_start is not None:
        # M1: the work window ends at the last child settle, not the run's span,
        # so a long idle tail does not read as work.
        settle = max(child_ends)
        containing = [end for start, end in (manager.get("_intervals") or [])
                      if start <= settle <= end]
        work_window_ms = max(0, (containing[-1] if containing else settle) - run_start)
    else:
        work_window_ms = (record["run"]["spanSec"] or 0) * 1000

    human_only_ms = _human_only_ms([r for r in rows if r["role"] == "manager"], rows)
    task_key, task_id, task_resolution = _task_link(ledger, identity)
    repos = set(identity.get("repos") or [])
    for item in normalise_items(ledger):
        if isinstance(item.get("repo"), str) and item["repo"]:
            repos.add(item["repo"])
    if identity.get("project"):
        repos.add(identity["project"])
    span_sec = record["run"]["spanSec"] or 0.0
    record["extras"] = {
        "managerThreadId": manager_id,
        "pricing": pricing_meta,
        "humanExcludedSec": human_only_ms / 1000,
        "orchestratorSec": max(0.0, span_sec - human_only_ms / 1000),
        "workWindowSec": work_window_ms / 1000,
        "managerWaitSec": (manager["waitMs"] / 1000) if manager else 0.0,
        "questionTimeoutSec": (manager["questionTimeoutMs"] / 1000) if manager else 0.0,
        "taskKey": task_key, "taskId": task_id, "taskResolution": task_resolution,
        "repos": sorted(repos),
    }
    for row in rows:
        row.pop("_intervals", None)
        row.pop("_wait_intervals", None)
        row.pop("costReported", None)
    return record

def self_test():
    """Assert the adapter: pricing, event parsing, lanes, and the shared schema.

    The record's own figures are asserted where they live — ledger_read.py's
    self-test; this one proves the adapter fills lanes correctly and that the
    record it produces carries the shared shape plus BB's `extras`.
    """
    assert manager_ids("m1") == ["m1"]
    assert manager_ids("m1", ["m2", "m1", "", None]) == ["m1", "m2"]
    price = {"prompt": 1e-6, "completion": 1e-5, "input_cache_read": 1e-7}
    tokens = {"inputTokens": 1000, "cacheReadInputTokens": 2000,
              "cacheWriteInputTokens": 0, "outputTokens": 100}
    got = cost_of(tokens, price)
    assert abs(got - (1000e-6 + 2000e-7 + 100e-5)) < 1e-12
    assert cost_of(None, price) is None and cost_of(tokens, None) is None
    table = {"anthropic/claude-sonnet-5": price}
    assert price_for("openrouter/anthropic/claude-sonnet-5", table) == price
    assert price_for("opencode/deepseek-v4-flash", table) is None
    assert format_cost({"reported": None, "estimated": None, "basis": "unpriced"}) == "unpriced"
    assert format_cost({"reported": None, "estimated": None, "basis": "unmeasured"}) == "unmeasured"
    assert format_cost({"reported": 1.5, "estimated": None, "basis": "reported"}) == "$1.50"
    assert "$0.00" not in format_cost({"reported": None, "estimated": None, "basis": "unpriced"})

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
    item = {"id": "01", "status": "done", "reviews": [{"pass": 1, "verdict": "CLEAN"}], "blockedBy": []}
    ledger_dict = {"feature": "DOT-11", "task": "DOT-11", "flow": "A", "items": {"01": dict(item)}}
    ledger_no_task = {"feature": "DOT-11", "items": {"01": dict(item)}}
    identity = {"managerThreadId": "thr_mgr", "project": "bb-plugins"}
    pricing = {"anthropic/claude-sonnet-5": price}

    # a compacted thread resets its counter; epochs are summed, not last-wins
    compacted = thread("thr_cc", "07 · worker", "idle", [
        ev("client/turn/requested", 0, dict(sonnet)),
        ev("turn/started", 0),
        ev("thread/tokenUsage/updated", 50_000, {"tokenUsage": {"total": {
            "inputTokens": 2000, "cachedInputTokens": 4000, "cacheReadInputTokens": 4000,
            "cacheWriteInputTokens": 0, "outputTokens": 200, "totalTokens": 6200}}}),
        ev("turn/completed", 60_000, {"status": "completed"}),
        ev("turn/started", 60_000),
        ev("thread/tokenUsage/updated", 90_000, {"tokenUsage": {"total": {
            "inputTokens": 10, "cachedInputTokens": 3000, "cacheReadInputTokens": 3000,
            "cacheWriteInputTokens": 0, "outputTokens": 50, "totalTokens": 3060}}}),
        ev("turn/completed", 100_000, {"status": "completed"}),
    ])
    cc = analyse_thread(compacted["meta"], compacted["events"])
    assert cc["tokenEpochs"] == 2 and cc["tokens"]["totalTokens"] == 9260, cc["tokens"]
    assert cc["tokens"]["inputTokens"] == 2010, cc["tokens"]

    # F1: the tool-item count is the floor on the requests-per-turn denominator
    heavy = thread("thr_hv", "01 · worker", "idle", [
        ev("client/turn/requested", 0, dict(sonnet)),
        ev("turn/started", 0),
        ev("item/started", 1_000, {"item": {"id": "r1", "type": "reasoning"}}),
        ev("item/started", 1_100, {"item": {"id": "c1", "type": "commandExecution", "command": "ls"}}),
        ev("item/completed", 1_200, {"item": {"id": "c1", "type": "commandExecution", "command": "ls"}}),
        ev("item/started", 1_300, {"item": {"id": "c2", "type": "commandExecution", "command": "ls"}}),
        ev("item/started", 1_400, {"item": {"id": "m1", "type": "agentMessage"}}),
        ev("thread/tokenUsage/updated", 2_000, {"tokenUsage": {"total": {
            "inputTokens": 100, "cachedInputTokens": 70_000, "cacheReadInputTokens": 70_000,
            "cacheWriteInputTokens": 0, "outputTokens": 50, "totalTokens": 70_150}}}),
        ev("turn/completed", 3_000, {"status": "completed"}),
    ])
    hrow = analyse_thread(heavy["meta"], heavy["events"])
    assert hrow["toolItems"] == 2 and hrow["tokensSource"] == "snapshot", hrow

    rec = record_of(threads, ledger_dict, identity, pricing)
    assert rec["schemaVersion"] == 2 and rec["runtime"] == "bb"
    assert rec["run"]["spanSec"] == 1500, rec["run"]["spanSec"]
    assert rec["run"]["lanes"] == 5 and rec["run"]["turns"] == 7
    # M1: span, work window and the manager's wait are three quantities
    assert rec["extras"]["workWindowSec"] == 1000, rec["extras"]["workWindowSec"]
    assert rec["extras"]["workWindowSec"] < rec["run"]["spanSec"]
    assert rec["extras"]["managerWaitSec"] == 120, rec["extras"]["managerWaitSec"]
    # M2: message-borne approval and the post-timeout wait are human time
    assert rec["extras"]["humanExcludedSec"] == 800, rec["extras"]["humanExcludedSec"]
    assert rec["extras"]["questionTimeoutSec"] == 390, rec["extras"]["questionTimeoutSec"]
    assert rec["extras"]["orchestratorSec"] == 700, rec["extras"]["orchestratorSec"]
    # pricing provenance is carried verbatim into extras
    meta = {"source": "cache", "fetchedAt": iso(1_700_000_000_000)}
    assert record_of(threads, ledger_dict, identity, pricing, meta)["extras"]["pricing"] == meta

    # a tell-shaped follow-up is human wait on the manager, never on a child
    ct = next(lane for lane in rec["lanes"] if lane["name"] == "thr_ct")
    assert ct["humanSec"] == 0 and ct["humanWaits"] == [], ct

    # M5: the manager's wait is waiting, not manager work
    mgr = next(lane for lane in rec["lanes"] if lane["name"] == "thr_mgr")
    assert mgr["activeSec"] == 220 and mgr["waitSec"] == 120 and mgr["workSec"] == 100, mgr

    # M6: a wait that outlives its turn is not turn work; a host restart is
    # downtime, not a thread waiting on a sibling
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
    infra_rec = record_of(
        [thread("thr_ot", "DOT-11 run", "idle", out_of_turn, is_manager=True),
         thread("thr_rs", "REVIEW 09 · thing", "idle", restarted)],
        ledger_dict, {"managerThreadId": "thr_ot", "project": "bb-plugins"}, pricing)
    ot = next(lane for lane in infra_rec["lanes"] if lane["name"] == "thr_ot")
    assert ot["waitSec"] == 250 and ot["waitOutOfTurnSec"] == 200 and ot["workSec"] == 50, ot
    rs = next(lane for lane in infra_rec["lanes"] if lane["name"] == "thr_rs")
    assert [list(pair) for pair in rs["infra"]] == [[iso(T0 + 100_000), iso(T0 + 800_000)]], rs["infra"]
    assert rs["infraReasons"] == ["host-daemon-restarted"]
    assert any("host-restart downtime" in f and "thr_rs" in f for f in infra_rec["findings"]), \
        infra_rec["findings"]
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
    rrow = analyse_thread(thread("thr_rr", "REVIEW 09 · thing", "idle", resumed)["meta"], resumed)
    assert rrow["turns"] == 1 and rrow["turnsFailed"] == 1, rrow
    assert rrow["activeMs"] == 500_000 and rrow["idleMs"] == 0, rrow

    # cost provenance: reported is null, estimated populated, basis says estimated
    c1 = next(lane for lane in rec["lanes"] if lane["name"] == "thr_c1")
    assert c1["cost"]["reported"] is None
    assert abs(c1["cost"]["estimated"] - 0.0022) < 1e-12, c1["cost"]
    assert c1["cost"]["basis"] == "estimated"
    # M4: unmeasured != unpriced, and neither is 0.00
    cw = next(lane for lane in rec["lanes"] if lane["name"] == "thr_cw")
    cr = next(lane for lane in rec["lanes"] if lane["name"] == "thr_cr")
    assert cw["cost"]["basis"] == "unmeasured" and cr["cost"]["basis"] == "unpriced"
    assert cw["cost"]["basis"] != cr["cost"]["basis"]
    assert any("unmeasured" in f for f in rec["findings"])
    assert any("unpriced" in f for f in rec["findings"])
    assert rec["run"]["cost"]["basis"] == "estimated"

    # M3: an idle finding names what the lane was waiting on, or does not fire
    assert any("waiting on code-review thr_cr" in f for f in rec["findings"]), rec["findings"]
    assert not any(f.startswith("coordinator ") and "idle" in f for f in rec["findings"])
    assert all("waitingOn" in lane for lane in rec["lanes"])
    assert cw["waitingOn"] == "thr_cr" and mgr["waitingOn"] is None, (cw, mgr)

    # reserved slot, task link and repos live in extras
    none_task = record_of(threads, ledger_no_task, identity, pricing)
    assert none_task["extras"]["taskKey"] is None and none_task["extras"]["taskResolution"] == "unresolved"
    assert rec["extras"]["taskKey"] == "DOT-11" and rec["extras"]["taskResolution"] == "run-name"
    assert rec["extras"]["repos"] == ["bb-plugins"]

    # a ledger that is not an object at all cannot make the write fail
    assert record_of(threads, [], identity, pricing)["items"] == {}
    assert record_of(threads, "garbage", identity, pricing)["items"] == {}

    # a manager-only ORCHESTRATE run is a finding; a dispatched run never fires it
    solo = thread("thr_solo", "ORCHESTRATE thing", "idle", [
        ev("client/turn/requested", 0, dict(sonnet, initiator="user", target={"kind": "thread-start"})),
        ev("turn/started", 0),
        ev("turn/completed", 60_000, {"status": "completed"}),
    ], is_manager=True)
    solo_rec = record_of([solo], {}, {"managerThreadId": "thr_solo", "project": "x"}, pricing)
    assert any("manager-only run" in f for f in solo_rec["findings"]), solo_rec["findings"]
    assert not any("manager-only run" in f for f in rec["findings"]), rec["findings"]

    # a settled run is not partial; a live lane makes it partial
    assert rec["run"]["partial"] is False
    live = record_of(threads + [thread("thr_live", "02 · worker", "active", worker_priced)],
                     ledger_dict, identity, pricing)
    assert live["run"]["partial"] is True

    # F5: a RETRO child is the recorder — it must not make a terminal run partial
    # or stretch its span
    retro = thread("thr_retro", "RETRO · thr_mgr", "active", [
        ev("client/turn/requested", 1_800_000, dict(sonnet)),
        ev("turn/started", 1_800_000),
        ev("item/started", 1_810_000, {"item": {"id": "c9", "type": "commandExecution", "command": "ls"}}),
    ])
    retro_rec = record_of(threads + [retro], ledger_dict, identity, pricing)
    assert retro_rec["run"]["partial"] is False, retro_rec["run"]["partial"]
    assert retro_rec["run"]["spanSec"] == rec["run"]["spanSec"]
    assert [lane["role"] for lane in retro_rec["retro"]] == ["retro"]
    assert all(lane["name"] != "thr_retro" for lane in retro_rec["lanes"])
    assert retro_rec["retro"][0]["toolItems"] == 1 and retro_rec["retro"][0]["retroInFlight"] is True
    assert not any(("turn/open" in f) or ("unmeasured" in f and "thr_retro" in f)
                   for f in retro_rec["findings"]), retro_rec["findings"]

    # the corpus name is the browsable key, stable across invocations
    assert re.fullmatch(r"\d{4}-\d{2}-\d{2}-bb-[a-z0-9-]+", rec["record_dirname"]), rec["record_dirname"]
    assert rec["record_dirname"] == record_of(threads, ledger_dict, identity, pricing)["record_dirname"]
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


def fetch_run(manager_id, chain=()):
    """The run's managers and every child of each, as `record_of` wants them.

    `manager_id` is the run's identity. `chain` is the ledger's
    `executors`: the managers that held this run, oldest first. Every one of
    them is the manager role, and the children of all of them are the run's
    children — a successor's workers hang off the successor, not off the thread
    that started the run.
    """
    ids = manager_ids(manager_id, chain)
    managers = []
    for tid in ids:
        meta = bb("thread", "show", tid, "--json")["thread"]
        meta["isManager"] = True
        managers.append(meta)
    metas = list(managers)
    known = {m["id"] for m in metas}
    for tid in ids:
        for child in children_of(tid):
            if child["id"] not in known:
                known.add(child["id"])
                metas.append(child)
    return [{"meta": t, "events": thread_events(t["id"])} for t in metas]


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
    """(model id -> per-token USD prices, provenance); prices empty when unavailable."""
    if not enabled:
        return {}, {"source": "disabled", "fetchedAt": None}
    if cache_path and os.path.exists(cache_path) and time.time() - os.path.getmtime(cache_path) < PRICING_TTL:
        try:
            return (json.load(open(cache_path)),
                    {"source": "cache", "fetchedAt": iso(int(os.path.getmtime(cache_path) * 1000))})
        except json.JSONDecodeError:
            pass
    try:
        with urllib.request.urlopen(PRICING_URL, timeout=15) as r:
            payload = json.load(r)["data"]
    except Exception as exc:  # offline, or the endpoint moved
        print(f"# pricing unavailable ({exc}); reporting tokens only", file=sys.stderr)
        return {}, {"source": "unavailable", "fetchedAt": None}
    table = {
        m["id"]: {k: float(v) for k, v in (m.get("pricing") or {}).items()
                  if isinstance(v, str) and v.replace(".", "", 1).isdigit()}
        for m in payload
    }
    if cache_path:
        os.makedirs(os.path.dirname(cache_path), exist_ok=True)
        json.dump(table, open(cache_path, "w"))
    return table, {"source": "openrouter", "fetchedAt": iso(int(time.time() * 1000))}


def _order(lane):
    value = parse_ts(lane.get("firstTs"))
    return value.timestamp() if value else 0.0


def print_table(record, no_pricing):
    run = record["run"]
    cost = run["cost"]
    extras = record.get("extras") or {}
    print(f"RUN {extras.get('managerThreadId')}  name={run['name'] or '-'}  flow={run['flow'] or '-'}  "
          f"project={run['project'] or '-'}  partial={str(run['partial']).lower()}")
    print(f"    orchestrator={fmt_seconds(extras.get('orchestratorSec'))}  span={fmt_seconds(run['spanSec'])}  "
          f"human={fmt_seconds(extras.get('humanExcludedSec'))} excluded  "
          f"work-window={fmt_seconds(extras.get('workWindowSec'))}  "
          f"manager-wait={fmt_seconds(extras.get('managerWaitSec'))}  "
          f"lanes={run['lanes']}  turns={run['turns']}")
    if no_pricing:
        print("    cost: pricing disabled (--no-pricing)")
    elif cost["basis"] == "unmeasured":
        print("    cost: unavailable (no token usage recorded)")
    elif cost["basis"] == "unpriced":
        print("    cost: unavailable (tokens present, no matching price)")
    else:
        print(f"    cost ${cost['estimated'] if cost['basis'] == 'estimated' else cost['reported']:.2f} "
              f"{cost['basis']} ({cost['lanesPriced']}/{run['lanes']} priced; "
              f"{cost['lanesUnpriced']} unpriced; {cost['lanesUnmeasured']} unmeasured)")
    print("\nPHASES (work time summed for the coordinator, waits excluded; phases overlap)")
    for role, phase in sorted(record["roles"].items(), key=lambda kv: -kv[1]["workSec"]):
        print(f"    {role:<12} {fmt_seconds(phase['workSec']):>8}  "
              f"over {phase['agents']:>2} lane(s), {phase['turns']:>2} turn(s)")
    print("\nLANES  (at = dispatch offset from the run's first activity)")
    ordered = sorted(record["lanes"], key=_order)
    run_start = parse_ts(ordered[0]["firstTs"]) if ordered and ordered[0].get("firstTs") else None
    print(f"    {'lane':<16}{'role':<12}{'model':<40}{'turns':>6}{'tools':>6}{'at':>8}{'span':>8}"
          f"{'active':>8}{'wait':>7}{'idle':>8}{'cost':>10}  errors")
    for lane in ordered:
        first = parse_ts(lane.get("firstTs"))
        at = ("+" + fmt_seconds((first - run_start).total_seconds())
              if first and run_start else "-")
        print(f"    {lane['name']:<16}{lane['role']:<12}{(lane.get('model') or '-'):<40}"
              f"{lane.get('turns', 0):>6}{lane.get('toolItems', 0):>6}"
              f"{at:>8}{fmt_seconds(lane.get('spanSec')):>8}{fmt_seconds(lane.get('activeSec')):>8}"
              f"{fmt_seconds(lane.get('waitSec')):>7}{fmt_seconds(lane.get('idleSec')):>8}"
              f"{format_cost(lane.get('cost') or {'basis': 'unmeasured'}):>10}  "
              f"{','.join(lane.get('errors') or []) or ''}")
    if any(lane.get("tokensSource") == "snapshot" for lane in record["lanes"]):
        print("    tokens: pi's token event is one request per turn, not a turn total —"
              " the cost above is a floor (see the tools column)")
    print("\nFINDINGS")
    print("\n".join(f"    - {f}" for f in record["findings"]) or "    (none)")
    print(f"\ncorpus dirname: runs/{record['record_dirname']}")


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

    executors = [e.get("id") for e in ((ledger or {}).get("executors") or []) if e.get("id")]
    threads = fetch_run(args.manager, executors)
    manager_meta = threads[0]["meta"]
    pricing, pricing_meta = openrouter_pricing(os.path.join(data_dir, "cache", "openrouter-models.json"),
                                               not args.no_pricing)
    record = record_of(threads, ledger,
                       {"managerThreadId": args.manager,
                        "project": project_name(manager_meta.get("projectId"))},
                       pricing, pricing_meta)

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
