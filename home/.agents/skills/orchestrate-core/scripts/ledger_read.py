#!/usr/bin/env python3
"""One ledger reader: ledger + lanes -> the run record, for both runtimes.

Before this module each retros script read the same ledger its own way and
emitted its own record shape — different units, different role names, a
different definition of work. This module owns the record: what a run's
figures mean, the role vocabulary, and every field both retro skills print or
archive. A runtime script is now an **adapter**: it fetches its own telemetry
(BB's thread-log events, Herdr's pi session transcripts) and normalises it into
**lanes**; this module sums, rolls up and reports them.

A **lane** is one dispatched agent or session, in the shape below, times in
seconds and timestamps in ISO-8601 UTC. Every key is optional except `name` and
`role`; an absent figure is absent, never zero:

    name role item session status provider
    startedAt endedAt firstTs lastTs          # ledger bounds, telemetry bounds
    intervals                    # [[iso, iso], ...] active intervals
    activeSec spanSec quietSec workSec        # telemetry time
    waitSec waitIntervals humanSec humanWaits questionTimeoutSec
    models model tokens costUsd cost{basis,reported,estimated}
    turns turnsFailed errors openTurn duplicateOf retroInFlight
    infra infraReasons toolItems messages exists

`read_run` is pure: it reads nothing but its arguments. `record_dirname` is the
one corpus-name function; `agents_from_ledger` is the one ledger-row reader;
`ledger_drift` is the one ledger-versus-transcript assertion. The cause
vocabulary and the ledger's own write checker stay in `orchestrate_common.py`.

    python3 ledger_read.py --self-test
"""

import datetime
import os
import sys

sys.path.insert(
    0, os.path.dirname(os.path.abspath(__file__)),
)
from orchestrate_common import (  # noqa: E402
    CAP, CAUSE_CODES, corpus_dirname,
)

SCHEMA_VERSION = 2

# The one role vocabulary. `manager`/`review` were BB's spellings; the ledger
# and both records now use these.
RUN_ROLES = ("coordinator", "worker", "code-review", "fix", "ponytail", "retro")
# The roles `models`/`served` are keyed by (ledger.md#models): the coordinator is
# not a model-bearing role.
REQUEST_ROLES = ("worker", "code-review", "ponytail")
ROLE_ALIASES = {
    "manager": "coordinator", "coordinator": "coordinator",
    "review": "code-review", "code-review": "code-review", "reviewer": "code-review",
    "worker": "worker", "fix": "fix", "ponytail": "ponytail", "retro": "retro",
}

IDLE_FINDING_SEC = 600
INFRA_FINDING_SEC = 60
DRIFT_TOLERANCE_SEC = 120
ACTIVE_STATUSES = {"active", "starting", "running", "settling"}
RUNNING_ITEM_STATUSES = {"running", "in_progress", "in-progress"}


# --------------------------------------------------------------------------
# time
# --------------------------------------------------------------------------

def parse_ts(text):
    """Parse an ISO-8601 timestamp into an aware datetime, or None."""
    if not isinstance(text, str) or not text:
        return None
    try:
        return datetime.datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None


def iso(value=None):
    """A datetime -> ISO-8601 UTC, or an epoch-ms int -> the same."""
    if isinstance(value, (int, float)):
        value = datetime.datetime.fromtimestamp(value / 1000.0, datetime.timezone.utc)
    if not isinstance(value, datetime.datetime):
        return None
    return value.astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _epoch(value):
    """ISO string / datetime / epoch-seconds -> epoch seconds, or None."""
    if isinstance(value, datetime.datetime):
        return value.timestamp()
    parsed = parse_ts(value)
    return parsed.timestamp() if parsed else None


def fmt_seconds(value):
    """A duration a reader can scan: `1h05m`, `5m02s`, `42s`, or `unmeasured`."""
    if value is None:
        return "unmeasured"
    total = int(value)
    hours, rest = divmod(total, 3600)
    minutes, seconds = divmod(rest, 60)
    if hours:
        return "%dh%02dm" % (hours, minutes)
    if minutes:
        return "%dm%02ds" % (minutes, seconds)
    return "%ds" % seconds


def _spans(intervals):
    """[[iso|dt, iso|dt], ...] -> sorted epoch-second spans, invalid dropped."""
    out = []
    for pair in intervals or []:
        if not isinstance(pair, (list, tuple)) or len(pair) != 2:
            continue
        start, end = _epoch(pair[0]), _epoch(pair[1])
        if start is not None and end is not None and end >= start:
            out.append((start, end))
    return sorted(out)


def _merge(spans):
    merged = []
    for start, end in sorted(spans):
        if merged and start <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], end)
        else:
            merged.append([start, end])
    return merged


def interval_union(intervals):
    """Seconds covered by the union of `intervals` (overlap counts once)."""
    return sum(end - start for start, end in _merge(_spans(intervals)))


def overlap_seconds(a, b):
    """Seconds covered by both interval lists (`a`, `b` merged first)."""
    left, right = _merge(_spans(a)), _merge(_spans(b))
    total = 0.0
    for start, end in left:
        for other_start, other_end in right:
            low, high = max(start, other_start), min(end, other_end)
            if high > low:
                total += high - low
    return total


def subtract_seconds(a, b):
    """Seconds in `a` covered by neither `b` nor another `a` interval."""
    return max(0.0, interval_union(a) - overlap_seconds(a, b))


# --------------------------------------------------------------------------
# the ledger
# --------------------------------------------------------------------------

def normalise_role(role):
    """A runtime's role name -> the one vocabulary."""
    return ROLE_ALIASES.get(str(role or "").lower(), str(role or ""))


def items_by_id(ledger):
    """The ledger's `items`, keyed by id. A pre-shape list is reported by the
    checker and read as empty here, because every reader keys it by name."""
    items = (ledger or {}).get("items") or {}
    if not isinstance(items, dict):
        return {}
    return {item_id: dict(value or {}, id=item_id) for item_id, value in items.items()}


def normalise_items(ledger):
    """The same items as a list, oldest key order — kept for the findings walk."""
    return list(items_by_id(ledger).values())


def cause_rollup(ledger):
    """Blocks by code, plus every stopped item the ledger left untyped."""
    codes, untyped = {}, []
    for item_id, item in sorted(items_by_id(ledger).items()):
        if item.get("status") not in ("blocked", "failed"):
            continue
        code = (item.get("cause") or {}).get("code")
        if code in CAUSE_CODES:
            codes.setdefault(code, []).append(item_id)
        else:
            untyped.append(item_id)
    return {"codes": codes, "untyped": untyped}


def human_wait(gate):
    """Seconds between a gate's request and its approval, or None."""
    if not isinstance(gate, dict):
        return None
    start, end = parse_ts(gate.get("requestedAt")), parse_ts(gate.get("approvedAt"))
    if not start or not end:
        return None
    return (end - start).total_seconds()


def gates_from_ledger(ledger):
    """The two run gates, each with its human wait in seconds."""
    gates = (ledger or {}).get("gates") or {}
    out = {}
    for name in ("plan", "commit"):
        gate = gates.get(name) or {}
        out[name] = {"requestedAt": gate.get("requestedAt"),
                     "approvedAt": gate.get("approvedAt"),
                     "waitSec": human_wait(gate)}
    return out


def agents_from_ledger(ledger):
    """Every dispatched agent the ledger names, with its role and item.

    The one reader of the ledger's lane rows: executors, retro, workers,
    reviews, fixes, and a ponytail pass's own fix round and its fresh-eyes
    review. A lane the ledger does not name is a lane no retro can price.
    """
    agents = []
    for executor in (ledger or {}).get("executors") or []:
        agents.append({"name": executor.get("id", "coordinator"), "role": "coordinator",
                       "item": None, "session": executor.get("session"),
                       "startedAt": executor.get("startedAt"),
                       "endedAt": executor.get("endedAt")})
    retro = (ledger or {}).get("retro") or {}
    if retro.get("id") or retro.get("session"):
        agents.append({"name": retro.get("id") or "retro", "role": "retro",
                       "item": None, "session": retro.get("session"),
                       "startedAt": retro.get("startedAt"),
                       "endedAt": retro.get("endedAt")})
    for item_id, item in sorted(items_by_id(ledger).items()):
        worker = item.get("worker") or {}
        if worker.get("id"):
            agents.append({"name": worker["id"], "role": "worker", "item": item_id,
                           "session": worker.get("session"),
                           "startedAt": item.get("startedAt"),
                           "endedAt": worker.get("endedAt")})
        for review in item.get("reviews") or []:
            agents.append({"name": review.get("agent") or review.get("id") or "review-%s" % item_id,
                           "role": "code-review", "item": item_id,
                           "session": review.get("session"),
                           "startedAt": review.get("startedAt"),
                           "endedAt": review.get("endedAt")})
        for fix in item.get("fixes") or []:
            agents.append({"name": fix.get("agent") or fix.get("id") or "fix-%s" % item_id,
                           "role": "fix", "item": item_id,
                           "session": fix.get("session"),
                           "startedAt": fix.get("startedAt"),
                           "endedAt": fix.get("endedAt")})
        # A ponytail fix carries the fresh-eyes review of its delta.
    from orchestrate_common import ponytail_passes
    for pass_ in ponytail_passes(ledger):
        agents.append({"name": pass_["id"], "role": "ponytail", "item": None,
                       "session": pass_.get("session"),
                       "startedAt": pass_.get("startedAt"),
                       "endedAt": pass_.get("endedAt")})
        fix = pass_.get("fix") or {}
        if fix.get("id") or fix.get("session"):
            agents.append({"name": fix.get("id") or "fix-ponytail", "role": "fix",
                           "item": None, "session": fix.get("session"),
                           "startedAt": fix.get("startedAt"),
                           "endedAt": fix.get("endedAt")})
        review = fix.get("review") or {}
        if review.get("id") or review.get("session"):
            agents.append({"name": review.get("id") or "review-ponytail", "role": "code-review",
                           "item": None, "session": review.get("session"),
                           "startedAt": review.get("startedAt"),
                           "endedAt": review.get("endedAt")})
    return agents


def record_dirname(runtime, project, feature, started_at, fallback_date=None):
    """The corpus directory name: `<date>-<runtime>-<project>-<feature>`.

    The one place the name is derived, so the retro's find step, its archive
    step and a re-run all agree.
    """
    date = (started_at or "")[:10] or (fallback_date or "")
    return corpus_dirname(date, runtime, project, feature or "run")


def ledger_drift(lanes):
    """Ledger intervals its own telemetry contradicts.

    The retro is the only reader holding both sides — the ledger's written
    interval and the agent's real activity — so the assertion lives here. A
    coordinator row with no `endedAt` is reported before the transcript check:
    the finding is about the ledger's bound, not the transcript.
    """
    drift = []
    for lane in lanes:
        where = "%s (%s)" % (lane.get("name"), lane.get("role"))
        if lane.get("role") == "coordinator" and not lane.get("endedAt"):
            drift.append({"agent": lane.get("name"), "role": lane.get("role"),
                          "kind": "no-upper-bound",
                          "detail": "%s: no endedAt — the coordinator's window has no upper "
                                    "bound, so its wind-down reads as run work" % where})
        if not lane.get("exists"):
            continue
        start, end = parse_ts(lane.get("startedAt")), parse_ts(lane.get("endedAt"))
        first, last = parse_ts(lane.get("firstTs")), parse_ts(lane.get("lastTs"))
        if start and end and end < start:
            drift.append({"agent": lane.get("name"), "role": lane.get("role"),
                          "kind": "backwards",
                          "detail": "%s: ledger has endedAt %s before startedAt %s"
                                    % (where, lane.get("endedAt"), lane.get("startedAt"))})
        if start and first and (first - start).total_seconds() > DRIFT_TOLERANCE_SEC:
            drift.append({"agent": lane.get("name"), "role": lane.get("role"),
                          "kind": "before-session",
                          "detail": "%s: ledger startedAt %s is %s before its own session's "
                                    "first activity %s"
                                    % (where, lane.get("startedAt"),
                                       fmt_seconds((first - start).total_seconds()),
                                       lane.get("firstTs"))})
        if end and last and (end - last).total_seconds() > DRIFT_TOLERANCE_SEC:
            drift.append({"agent": lane.get("name"), "role": lane.get("role"),
                          "kind": "after-session",
                          "detail": "%s: ledger endedAt %s is %s after its own session's "
                                    "last activity %s"
                                    % (where, lane.get("endedAt"),
                                       fmt_seconds((end - last).total_seconds()),
                                       lane.get("lastTs"))})
    return drift


# --------------------------------------------------------------------------
# the record
# --------------------------------------------------------------------------

def _sec(lane, key, fallback=None):
    value = lane.get(key)
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(value)
    return fallback


def read_run(ledger, lanes, runtime, feature=None, project=None, extras=None,
             fallback_date=None):
    """ledger + normalised lanes -> the one run record.

    Pure: reads nothing but its arguments. `runtime` is `bb` or `herdr`; it
    names the record and the corpus directory, and nothing else branches on it.
    """
    ledger = ledger if isinstance(ledger, dict) else {}
    lanes = [dict(lane) for lane in lanes]
    for lane in lanes:
        lane["role"] = normalise_role(lane.get("role"))
        # A lane that never waited waited zero seconds; a runtime whose telemetry
        # has no such concept (Herdr) simply omits the key.
        for key in ("waitSec", "waitOutOfTurnSec", "humanSec", "questionTimeoutSec"):
            lane.setdefault(key, 0.0)
    feature = feature or ledger.get("feature") or "run"

    work = [lane for lane in lanes if lane.get("role") != "retro"]
    retro = [lane for lane in lanes if lane.get("role") == "retro"]
    coordinator = next((lane for lane in work if lane.get("role") == "coordinator"), None)

    # Ledger bounds win; a run still in flight falls back to its own telemetry.
    starts = [parse_ts(lane.get("firstTs")) for lane in work]
    ends = [parse_ts(lane.get("lastTs")) for lane in work]
    starts = [value for value in starts if value]
    ends = [value for value in ends if value]
    started_dt = parse_ts(ledger.get("startedAt")) or (min(starts) if starts else None)
    ended_dt = parse_ts(ledger.get("finishedAt")) or (max(ends) if ends else None)
    span_sec = ((ended_dt - started_dt).total_seconds()
                if started_dt and ended_dt else None)

    active_sum = sum(_sec(lane, "activeSec", 0.0) for lane in work)
    work_sum = sum(_sec(lane, "workSec", _sec(lane, "activeSec", 0.0)) for lane in work)
    quiet_sum = sum(_sec(lane, "quietSec", 0.0) for lane in work)
    intervals = [pair for lane in work for pair in (lane.get("intervals") or [])]
    covered = interval_union(intervals)
    overlap = max(0.0, active_sum - covered)

    for lane in work:
        lane["idleSec"] = max(0.0, _sec(lane, "spanSec", 0.0) - _sec(lane, "activeSec", 0.0))

    gates = gates_from_ledger(ledger)
    gate_wait = sum((gate.get("waitSec") or 0.0) for gate in gates.values())
    orchestrator = (max(0.0, span_sec - gate_wait) if span_sec is not None else None)

    # cost: the basis is the best any lane achieved, and each lane is counted
    # by the basis it carried (an unpriced lane is not a $0.00 lane).
    basis_rank = {"unmeasured": 0, "unpriced": 1, "estimated": 2, "reported": 3}
    cost = {"reported": None, "estimated": None, "basis": "unmeasured",
            "lanesPriced": 0, "lanesUnpriced": 0, "lanesUnmeasured": 0}
    reported, estimated = [], []
    for lane in work:
        basis = ((lane.get("cost") or {}).get("basis")
                 or lane.get("costBasis") or "unmeasured")
        value = (lane.get("cost") or {}).get("reported", lane.get("costUsd"))
        if basis == "reported" and value is not None:
            reported.append(value)
        elif basis == "estimated" and value is not None:
            estimated.append(value)
        elif basis == "unpriced":
            cost["lanesUnpriced"] += 1
        else:
            cost["lanesUnmeasured"] += 1
        if basis_rank.get(basis, 0) > basis_rank.get(cost["basis"], 0):
            cost["basis"] = basis
    if reported:
        cost["reported"] = sum(reported)
        cost["basis"] = "reported"
    elif estimated:
        cost["estimated"] = sum(estimated)
        cost["basis"] = "estimated"
    cost["lanesPriced"] = len(reported) + len(estimated)

    roles = {}
    for lane in work:
        entry = roles.setdefault(lane["role"], {"role": lane["role"], "agents": 0, "sessions": 0,
                                                "spanSec": 0.0, "workSec": 0.0, "costUsd": 0.0,
                                                "turns": 0})
        entry["agents"] += 1
        entry["sessions"] += 1
        entry["spanSec"] += _sec(lane, "spanSec", 0.0)
        entry["workSec"] += _sec(lane, "workSec", _sec(lane, "activeSec", 0.0))
        entry["costUsd"] += _sec(lane, "costUsd", 0.0)
        entry["turns"] += int(_sec(lane, "turns", 0))

    cost_by_model = {}
    for lane in work:
        for model in lane.get("models") or []:
            entry = cost_by_model.setdefault(model, {"agents": 0, "costUsd": 0.0, "totalTokens": 0})
            entry["agents"] += 1
            entry["costUsd"] += _sec(lane, "costUsd", 0.0)
            entry["totalTokens"] += int((lane.get("tokens") or {}).get("totalTokens") or 0)

    items = {}
    for item_id, item in sorted(items_by_id(ledger).items()):
        items[item_id] = {
            "title": item.get("title"), "slug": item.get("slug"),
            "ticket": item.get("ticket"), "status": item.get("status"),
            "risk": item.get("risk"), "prUrl": item.get("prUrl"),
            "blockedBy": item.get("blockedBy") or [],
            "reviewCount": len(item.get("reviews") or []),
            "fixRounds": len(item.get("fixes") or []),
            # Flow B's per-item gate: a request with no approval is human wait,
            # and the field is read here so the retro's claim about it is true.
            "commitGateWaitSec": human_wait(item.get("commitGate")),
            "cause": item.get("cause"),
        }

    partial = (any(lane.get("status") in ACTIVE_STATUSES or lane.get("openTurn") for lane in work)
               or any(item.get("status") in RUNNING_ITEM_STATUSES for item in items.values()))

    run = {
        "runtime": runtime,
        "feature": feature,
        "name": ledger.get("feature") or feature,
        "project": project,
        "tracker": ledger.get("tracker"),
        "flow": ledger.get("flow"),
        "mode": ledger.get("mode"),
        "startedAt": iso(started_dt),
        "finishedAt": ledger.get("finishedAt"),
        "endedAt": iso(ended_dt),
        "spanSec": span_sec,
        "activeSumSec": active_sum,
        "workSumSec": work_sum,
        "coveredSec": covered,
        "overlapSec": overlap,
        "quietSumSec": quiet_sum,
        "humanWaitSec": gate_wait,
        "orchestratorSec": orchestrator,
        "models": ledger.get("models") or {},
        "served": ledger.get("served") or {},
        "lanes": len(work),
        "turns": sum(int(_sec(lane, "turns", 0)) for lane in work),
        "cost": cost,
        "partial": partial,
    }

    drift = ledger_drift(lanes)
    record = {
        "schemaVersion": SCHEMA_VERSION,
        "runtime": runtime,
        "run": run,
        "roles": roles,
        "costByModel": cost_by_model,
        "lanes": work,
        "retro": retro,
        "items": items,
        "causes": cause_rollup(ledger),
        "gates": gates,
        "drift": drift,
        "record_dirname": record_dirname(runtime, project, feature, run["startedAt"],
                                          fallback_date),
        "extras": extras or {},
    }
    for lane in record["lanes"]:
        # The machine-readable half of an idle finding: present on every lane so a
        # reader need not infer absence from a missing key.
        lane.setdefault("waitingOn", None)
    record["findings"] = build_findings(record, ledger, coordinator, extras or {})
    return record


def build_findings(record, ledger, coordinator, extras):
    """Every finding a metrics table cannot state by itself, one line each."""
    out = []
    for lane in record["lanes"]:
        where = "%s %s (%s)" % (lane.get("role"), lane.get("name"), lane.get("title"))
        if _sec(lane, "turnsFailed", 0):
            out.append("%s: %d failed turn(s) — %s"
                       % (where, int(_sec(lane, "turnsFailed", 0)), ", ".join(lane.get("errors") or [])))
        elif lane.get("errors"):
            out.append("%s: %s" % (where, ", ".join(lane["errors"])))
        if lane.get("status") == "error" and lane.get("role") != "retro":
            out.append("%s: thread ended in error" % where)
        models = lane.get("models") or []
        if len(models) > 1:
            out.append("%s: ran %d models (%s)" % (where, len(models), ", ".join(models)))
        basis = (lane.get("cost") or {}).get("basis") or lane.get("costBasis")
        if basis == "unpriced":
            out.append("%s: unpriced — tokens present but no price recorded" % where)
        elif basis == "unmeasured" and lane.get("role") != "retro":
            out.append("%s: unmeasured — no token usage recorded" % where)
    for lane in record["lanes"]:
        infra = _merge(_spans(lane.get("infra") or []))
        total = sum(end - start for start, end in infra)
        if total >= INFRA_FINDING_SEC:
            where = "%s %s (%s)" % (lane.get("role"), lane.get("name"), lane.get("title"))
            reasons = ", ".join(lane.get("infraReasons") or []) or "host-connection-lost"
            out.append("%s: %s of its %s span is host-restart downtime (%s) — not waiting on a "
                       "sibling" % (where, fmt_seconds(total), fmt_seconds(lane.get("spanSec")), reasons))
    for lane in record["lanes"]:
        if lane.get("role") in ("coordinator", "retro") or _sec(lane, "idleSec", 0) <= IDLE_FINDING_SEC:
            continue
        cause = _best_wait_cause(record["lanes"], lane)
        if not cause:
            continue
        other, overlap = cause
        lane["waitingOn"] = other.get("name")
        out.append("%s %s (%s): idle %s of %s span — waiting on %s %s (%s active)"
                   % (lane.get("role"), lane.get("name"), lane.get("title"),
                      fmt_seconds(lane.get("idleSec")), fmt_seconds(lane.get("spanSec")),
                      other.get("role"), other.get("name"), fmt_seconds(overlap)))
    if coordinator:
        where = "%s %s" % (coordinator.get("role"), coordinator.get("name"))
        if _sec(coordinator, "waitSec", 0):
            extra = ("; %s of it ran outside any recorded turn, so it is not counted as work "
                     "either" % fmt_seconds(coordinator.get("waitOutOfTurnSec"))
                     ) if _sec(coordinator, "waitOutOfTurnSec", 0) else ""
            out.append("%s: blocked on its waits for %d child(ren) — %s%s"
                       % (where, len(coordinator.get("waitedOn") or []),
                          fmt_seconds(coordinator.get("waitSec")), extra))
        if _sec(coordinator, "questionTimeoutSec", 0):
            out.append("%s: a question timed out after %s; the wait until the reply is human time"
                       % (where, fmt_seconds(coordinator.get("questionTimeoutSec"))))
    items = normalise_items(ledger)
    if coordinator and len(record["lanes"]) == 1 and not ledger and \
            (coordinator.get("title") or "").startswith("ORCHESTRATE"):
        out.append("%s (%s): manager-only run — 0 children and no ledger; dispatch never happened"
                   % (coordinator.get("name"), coordinator.get("title")))
    for item in items:
        if len(item.get("fixes") or []) >= CAP:
            out.append("item %s: review hit the cap (%d)" % (item.get("id"), len(item["fixes"])))
        if item.get("status") in ("blocked", "failed"):
            cause = item.get("cause") or {}
            code = cause.get("code")
            if code in CAUSE_CODES:
                out.append("item %s: %s — %s: %s"
                           % (item.get("id"), item.get("status"), code,
                              cause.get("detail") or "no detail"))
            else:
                out.append("item %s: %s with no cause (%s) — cause-contract.md"
                           % (item.get("id"), item.get("status"), code or "none"))
    for drift in record["drift"]:
        out.append("ledger drift [%s] %s" % (drift["kind"], drift["detail"]))
    blocks = record["causes"]
    if blocks.get("untyped"):
        out.append("items stopped without a cause: %s — cause-contract.md"
                   % ", ".join(blocks["untyped"]))
    return out


def _best_wait_cause(lanes, lane):
    """Name the lane a parked lane was waiting on, or None, from idle overlap."""
    idle = lane.get("intervals") or []
    if not idle:
        return None
    # A lane's own idle is its span minus its active intervals.
    idle_intervals = _idle(lane)

    def longest(candidates):
        best = None
        for other in candidates:
            overlap = overlap_seconds(idle_intervals, other.get("intervals") or [])
            if overlap and (best is None or overlap > best[1]):
                best = (other, overlap)
        return best

    return (longest([other for other in lanes if other is not lane
                     and other.get("role") != "coordinator"])
            or longest([other for other in lanes if other is not lane
                        and other.get("role") == "coordinator"]))


def _idle(lane):
    """A lane's span with its active intervals and its host downtime removed.

    Downtime is not idleness a sibling caused, so it is treated as busy: a lane
    dead through a host restart must not be blamed for waiting on a review.
    """
    span = _spans([[lane.get("firstTs"), lane.get("lastTs")]])
    if not span:
        return []
    busy = _merge(_spans(lane.get("intervals") or []) + _spans(lane.get("infra") or []))
    out, cursor = [], span[0][0]
    for start, end in busy:
        if start > cursor:
            out.append([cursor, start])
        cursor = max(cursor, end)
    if cursor < span[0][1]:
        out.append([cursor, span[0][1]])
    return [(datetime.datetime.fromtimestamp(start, datetime.timezone.utc),
             datetime.datetime.fromtimestamp(end, datetime.timezone.utc)) for start, end in out]


# --------------------------------------------------------------------------
# self-test
# --------------------------------------------------------------------------

def _fixture_ledger(runtime):
    return {
        "runtime": runtime, "feature": "demo", "project": "repo", "tracker": "scratch demo",
        "flow": "A", "mode": "gated",
        "startedAt": "2026-01-01T12:00:00Z", "finishedAt": "2026-01-01T12:30:00Z",
        "models": {"worker": "vendor/worker", "code-review": "vendor/review"},
        "served": {"worker": "vendor/worker"},
        "gates": {"plan": {"requestedAt": "2026-01-01T11:58:00Z",
                           "approvedAt": "2026-01-01T12:00:00Z"},
                  "commit": {"requestedAt": "2026-01-01T12:30:00Z", "approvedAt": None}},
        "items": {"01": {"status": "done", "reviews": [{"pass": 1, "verdict": "CLEAN"}]},
                  "02": {"status": "blocked", "cause": {"code": "cap_exhausted", "detail": "x"}}},
    }


def self_test():
    """Assert the one record: roles, time, cost, items, gates, drift."""
    # time helpers
    assert parse_ts("2026-01-01T12:00:00Z") and parse_ts("nope") is None
    assert iso(parse_ts("2026-01-01T12:00:00Z")) == "2026-01-01T12:00:00Z"
    assert fmt_seconds(3900) == "1h05m" and fmt_seconds(62) == "1m02s" and fmt_seconds(9) == "9s"
    assert fmt_seconds(None) == "unmeasured"
    start, end = "2026-01-01T12:00:00Z", "2026-01-01T12:10:00Z"
    second, third = "2026-01-01T12:05:00Z", "2026-01-01T12:20:00Z"
    assert interval_union([[start, end]]) == 600
    assert interval_union([[start, end], [start, end]]) == 600
    assert interval_union([[start, end], [second, third]]) == 1200
    assert overlap_seconds([[start, end]], [[second, third]]) == 300
    assert subtract_seconds([[start, end]], [[second, end]]) == 300

    # ledger readers
    assert normalise_role("manager") == "coordinator"
    assert normalise_role("review") == "code-review"
    assert normalise_items({"items": {"01": {"status": "done"}}}) == [{"status": "done", "id": "01"}]
    assert normalise_items({"items": []}) == [] and normalise_items({}) == []
    assert human_wait({"requestedAt": start, "approvedAt": second}) == 300
    assert human_wait({"requestedAt": None, "approvedAt": second}) is None
    assert cause_rollup({"items": {"01": {"status": "blocked", "cause": {"code": "cap_exhausted"}},
                                   "02": {"status": "failed", "cause": {"code": "dispatch_failed"}},
                                   "03": {"status": "blocked"},
                                   "04": {"status": "done"},
                                   "05": {"status": "blocked", "cause": {"code": "made_up"}}}}) == \
        {"codes": {"cap_exhausted": ["01"], "dispatch_failed": ["02"]}, "untyped": ["03", "05"]}
    assert [a["name"] for a in agents_from_ledger(
        {"executors": [{"id": "coordinator", "session": "/tmp/c.jsonl"}],
         "retro": {"id": "retro-x", "session": "/tmp/r.jsonl"},
         "items": {"01": {"reviews": [{"id": "review-01-r1", "session": "/tmp/b.jsonl"}]}},
         "ponytail": [{"id": "ponytail", "session": "/tmp/p.jsonl"}]})] == \
        ["coordinator", "retro-x", "review-01-r1", "ponytail"]
    assert [(a["name"], a["role"]) for a in agents_from_ledger(
        {"ponytail": [{"id": "ponytail", "session": "/tmp/p.jsonl",
                       "fix": {"id": "fix-p", "session": "/tmp/f.jsonl",
                               "review": {"id": "review-p", "session": "/tmp/v.jsonl"}}}]})] == \
        [("ponytail", "ponytail"), ("fix-p", "fix"), ("review-p", "code-review")]
    assert record_dirname("herdr", "repo", "My Feature", start) == "2026-01-01-herdr-repo-my-feature"
    assert record_dirname("bb", None, None, None, fallback_date="2026-02-02") == "2026-02-02-bb-run"
    drift = ledger_drift([{"name": "review-15-r1", "role": "code-review", "exists": True,
                           "startedAt": second, "endedAt": start,
                           "firstTs": third, "lastTs": third}])
    assert {d["kind"] for d in drift} == {"backwards", "before-session"}, drift
    assert [d["kind"] for d in ledger_drift(
        [{"name": "coordinator", "role": "coordinator", "exists": False,
          "startedAt": start, "endedAt": None, "firstTs": None, "lastTs": None}])] == ["no-upper-bound"]

    # a two-lane run: one worker priced, one review unpriced
    lanes = [
        {"name": "coordinator", "role": "manager", "status": "idle",
         "firstTs": start, "lastTs": third, "spanSec": 1200, "activeSec": 600,
         "workSec": 600, "intervals": [[start, second]],
         "turns": 2, "models": ["vendor/worker"], "cost": {"basis": "unmeasured"}},
        {"name": "item-01", "role": "worker", "status": "idle", "item": "01",
         "firstTs": second, "lastTs": third, "spanSec": 900, "activeSec": 900,
         "workSec": 900, "intervals": [[second, third]],
         "turns": 3, "models": ["vendor/worker"],
         "cost": {"basis": "reported", "reported": 0.5}, "costUsd": 0.5,
         "tokens": {"totalTokens": 100}},
        {"name": "review-01-r1", "role": "review", "status": "idle", "item": "01",
         "firstTs": third, "lastTs": third, "spanSec": 0, "activeSec": 0,
         "intervals": [], "turns": 1, "models": ["vendor/review"],
         "cost": {"basis": "unpriced"}, "tokens": {"totalTokens": 10}},
        {"name": "retro-x", "role": "retro", "status": "idle",
         "firstTs": third, "lastTs": third, "spanSec": 0, "activeSec": 0,
         "intervals": [], "models": []},
    ]
    record = read_run(_fixture_ledger("bb"), lanes, "bb", project="repo")
    run = record["run"]
    assert record["schemaVersion"] == 2 and record["runtime"] == "bb"
    assert run["spanSec"] == 1800, run["spanSec"]          # ledger bounds win
    assert run["activeSumSec"] == 1500 and run["workSumSec"] == 1500
    assert run["coveredSec"] == 1200 and run["overlapSec"] == 300
    assert run["humanWaitSec"] == 120 and run["orchestratorSec"] == 1680
    assert run["cost"]["basis"] == "reported" and run["cost"]["reported"] == 0.5
    assert run["cost"]["lanesUnpriced"] == 1 and run["cost"]["lanesUnmeasured"] == 1
    assert set(record["roles"]) == {"coordinator", "worker", "code-review"}, record["roles"]
    assert record["costByModel"]["vendor/worker"]["agents"] == 2
    assert record["items"]["01"]["status"] == "done" and record["items"]["02"]["reviewCount"] == 0
    assert set(record["causes"]["codes"]) == {"cap_exhausted"}
    assert record["gates"]["plan"]["waitSec"] == 120
    assert record["record_dirname"] == "2026-01-01-bb-repo-demo"
    assert record["run"]["partial"] is False
    assert any("unpriced" in f for f in record["findings"]), record["findings"]
    assert any("review hit the cap" not in f for f in record["findings"])
    # the retro is never a lane of the run
    assert [lane["name"] for lane in record["retro"]] == ["retro-x"]
    assert all(lane["name"] != "retro-x" for lane in record["lanes"])
    # one run, one schema: herdr's record has the same keys
    herdr = read_run(dict(_fixture_ledger("herdr"), tracker="github o/r#1"),
                     lanes, "herdr", project="repo")
    assert set(herdr.keys()) == set(record.keys())
    assert set(herdr["run"].keys()) == set(run.keys())
    assert herdr["runtime"] == "herdr" and herdr["record_dirname"].startswith("2026-01-01-herdr-")
    print("ledger_read self-test: ok")


if __name__ == "__main__":
    self_test()
