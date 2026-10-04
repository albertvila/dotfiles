#!/usr/bin/env python3
"""Read a Herdr orchestration run's records into numbers.

Source of truth: the run ledger (`$RUNDIR/orchestration.json`) plus the pi
session transcripts it names. A pi session transcript is JSONL; every
`message` event carries a timestamp, and every assistant message carries the
model and `usage` (tokens plus pi's own computed cost). Herdr keeps no turn
telemetry of its own, so this script reads nothing from it.

Read-only, stdlib-only, safe to re-run.

Usage:
  run-metrics.py <rundir> [--json] [--output-dir DIR] [--self-test]
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone

DEFAULT_RUNDIR = "."

# A session whose messages pause longer than this is not working: it is waiting on
# another agent, or the machine was suspended under it.
QUIET_GAP_SEC = 600
# How far a ledger interval may differ from the agent's own session window before
# the retro calls it drift rather than rounding.
DRIFT_TOLERANCE_SEC = 120


def parse_ts(text):
    """Parse an ISO-8601 timestamp into an aware datetime, or None."""
    if not text or not isinstance(text, str):
        return None
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None


def slug(text):
    return re.sub(r"-+", "-", re.sub(r"[^a-z0-9_-]+", "-", text.lower())).strip("-")


def interval_union(intervals):
    """Seconds covered by the union of closed [start, end] aware datetimes."""
    spans = sorted((a, b) for a, b in intervals if a and b and b >= a)
    covered, cur_start, cur_end = 0.0, None, None
    for start, end in spans:
        if cur_start is None:
            cur_start, cur_end = start, end
        elif start <= cur_end:
            cur_end = max(cur_end, end)
        else:
            covered += (cur_end - cur_start).total_seconds()
            cur_start, cur_end = start, end
    if cur_start is not None:
        covered += (cur_end - cur_start).total_seconds()
    return covered


def quiet_seconds(times, gap=QUIET_GAP_SEC):
    """Seconds of a session's span that hold no message for longer than `gap`.

    A session's span is first→last message. For a worker re-prompted for a fix
    round, or a session that outlived a host suspend, that span contains hours
    that are not work; this is the honest denominator for "how long was this
    agent on".
    """
    ordered = sorted(t for t in times if t)
    return sum((b - a).total_seconds() for a, b in zip(ordered, ordered[1:])
               if (b - a).total_seconds() > gap)


def unique_by_session(sessions):
    """One row per transcript: a fix round re-prompts the worker's own session.

    The ledger records that fix as its own entry (role `fix`), so the same
    transcript appears twice and would otherwise be priced, timed and covered
    twice.
    """
    seen, unique = set(), []
    for metrics in sessions:
        path = metrics.get("session")
        if path and path in seen:
            continue
        seen.add(path)
        unique.append(metrics)
    return unique


def ledger_drift(sessions):
    """Ledger intervals its own transcripts contradict.

    The retro is the only reader that holds both sides — the ledger's written
    interval and the session's real messages — so the assertion lives here.
    """
    drift = []
    for metrics in sessions:
        if not metrics.get("exists"):
            continue
        start, end = parse_ts(metrics.get("startedAt")), parse_ts(metrics.get("endedAt"))
        first, last = parse_ts(metrics["firstTs"]), parse_ts(metrics["lastTs"])
        where = "%s (%s)" % (metrics["name"], metrics["role"])
        if start and end and end < start:
            drift.append({"agent": metrics["name"], "role": metrics["role"],
                          "kind": "backwards",
                          "detail": "%s: ledger has endedAt %s before startedAt %s"
                                    % (where, metrics["endedAt"], metrics["startedAt"])})
        if start and first and (first - start).total_seconds() > DRIFT_TOLERANCE_SEC:
            drift.append({"agent": metrics["name"], "role": metrics["role"],
                          "kind": "before-session",
                          "detail": "%s: ledger startedAt %s is %s before its own session's "
                                    "first message %s"
                                    % (where, metrics["startedAt"],
                                       fmt_seconds((first - start).total_seconds()),
                                       metrics["firstTs"])})
        if end and last and (end - last).total_seconds() > DRIFT_TOLERANCE_SEC:
            drift.append({"agent": metrics["name"], "role": metrics["role"],
                          "kind": "after-session",
                          "detail": "%s: ledger endedAt %s is %s after its own session's "
                                    "last message %s"
                                    % (where, metrics["endedAt"],
                                       fmt_seconds((end - last).total_seconds()),
                                       metrics["lastTs"])})
    return drift


def session_metrics(path):
    """Timeline, tokens, cost and models for one pi session transcript."""
    result = {
        "session": path, "exists": bool(path and os.path.exists(path)),
        "firstTs": None, "lastTs": None, "spanSec": None, "messages": 0,
        "activeSec": None, "quietSec": None, "runSec": None,
        "outsideRunSec": None, "duplicateOf": None,
        "startedAt": None, "endedAt": None,
        "tokens": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0,
                   "reasoning": 0, "totalTokens": 0},
        "costUsd": 0.0, "models": [],
    }
    if not result["exists"]:
        return result
    first = last = None
    stamps = []
    models = []
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            try:
                event = json.loads(line)
            except ValueError:
                continue
            ts = parse_ts(event.get("timestamp"))
            if ts:
                first = ts if first is None or ts < first else first
                last = ts if last is None or ts > last else last
                stamps.append(ts)
            if event.get("type") == "model_change":
                models.append("%s/%s" % (event.get("provider", "?"),
                                         event.get("modelId", "?")))
            if event.get("type") != "message":
                continue
            message = event.get("message") or {}
            if message.get("role") != "assistant":
                continue
            result["messages"] += 1
            if message.get("provider") and message.get("model"):
                models.append("%s/%s" % (message["provider"], message["model"]))
            usage = message.get("usage") or {}
            for key in result["tokens"]:
                result["tokens"][key] += usage.get(key) or 0
            result["costUsd"] += (usage.get("cost") or {}).get("total") or 0.0
    result["firstTs"] = first.isoformat() if first else None
    result["lastTs"] = last.isoformat() if last else None
    result["spanSec"] = (last - first).total_seconds() if first and last else None
    if result["spanSec"] is not None:
        result["quietSec"] = quiet_seconds(stamps)
        result["activeSec"] = result["spanSec"] - result["quietSec"]
    seen, ordered = set(), []
    for model in models:
        if model not in seen:
            seen.add(model)
            ordered.append(model)
    result["models"] = ordered
    return result


def ponytail_passes(ledger):
    """The ponytail passes in order; a pre-list ledger holds one mapping."""
    passes = ledger.get("ponytail") or []
    if isinstance(passes, dict):
        passes = [passes]
    return [entry for entry in passes if entry.get("agent")]


def agents_from_ledger(ledger):
    """Every dispatched agent in the run, with its role and item."""
    agents = []
    coordinator = ledger.get("coordinator") or {}
    if coordinator:
        agents.append({"name": "coordinator", "role": "coordinator",
                       "item": None, "session": coordinator.get("session"),
                       "startedAt": coordinator.get("startedAt"),
                       "endedAt": coordinator.get("endedAt")})
    for item_id, item in sorted((ledger.get("items") or {}).items()):
        worker = item.get("worker") or {}
        if worker.get("agent"):
            agents.append({"name": worker["agent"], "role": "worker",
                           "item": item_id, "session": worker.get("session"),
                           "startedAt": item.get("startedAt"),
                           "endedAt": worker.get("endedAt")})
        for review in item.get("reviews") or []:
            agents.append({"name": review.get("agent", "review-%s" % item_id),
                           "role": "code-review", "item": item_id,
                           "session": review.get("session"),
                           "startedAt": review.get("startedAt"),
                           "endedAt": review.get("endedAt")})
        for fix in item.get("fixes") or []:
            agents.append({"name": fix.get("agent", "fix-%s" % item_id),
                           "role": "fix", "item": item_id,
                           "session": fix.get("session"),
                           "startedAt": fix.get("startedAt"),
                           "endedAt": fix.get("endedAt")})
    for pass_ in ponytail_passes(ledger):
        agents.append({"name": pass_["agent"], "role": "ponytail",
                       "item": None, "session": pass_.get("session"),
                       "startedAt": pass_.get("startedAt"),
                       "endedAt": pass_.get("endedAt")})
    return agents


def human_wait(gate):
    """Seconds between a gate's request and its approval, or None."""
    if not gate:
        return None
    start = parse_ts(gate.get("requestedAt"))
    end = parse_ts(gate.get("approvedAt"))
    if not start or not end:
        return None
    return (end - start).total_seconds()


def record_dirname(ledger):
    """The corpus directory name for this run: stable for the same ledger."""
    started = parse_ts(ledger.get("startedAt")) or datetime.now(timezone.utc)
    rundir = str(ledger.get("rundir") or "")
    root = rundir.split("/.herdr-runs/")[0]
    project = os.path.basename(root.rstrip("/")) or "project"
    feature = slug(str(ledger.get("feature") or "run"))
    project = slug(project) or "project"
    return "%s-%s-%s" % (started.strftime("%Y-%m-%d"), project, feature)


def build_record(rundir):
    ledger_path = os.path.join(rundir, "orchestration.json")
    if not os.path.exists(ledger_path):
        raise SystemExit("no ledger at %s" % ledger_path)
    with open(ledger_path, encoding="utf-8") as handle:
        ledger = json.load(handle)

    sessions = []
    for agent in agents_from_ledger(ledger):
        metrics = session_metrics(agent.get("session"))
        metrics.update({"name": agent["name"], "role": agent["role"],
                        "item": agent["item"], "startedAt": agent.get("startedAt"),
                        "endedAt": agent.get("endedAt")})
        sessions.append(metrics)

    # One transcript can serve several ledger rows (a fix round re-prompts the
    # worker's own session), so every sum below counts it once.
    seen_paths = {}
    for metrics in sessions:
        path = metrics.get("session")
        metrics["duplicateOf"] = seen_paths.get(path) if path else None
        seen_paths.setdefault(path, metrics["name"])
    unique = unique_by_session(sessions)
    coordinator = ledger.get("coordinator") or {}

    def window(metrics):
        """A session's interval as *this run* owns it.

        The coordinator's pi session outlives the run — it may already have been
        open on an earlier run, and its last turns are the run's wind-down — so
        the ledger's own two ends bound it here, and the part outside is
        reported instead of absorbed into `covered`.
        """
        start, end = parse_ts(metrics["firstTs"]), parse_ts(metrics["lastTs"])
        if metrics["role"] != "coordinator" or not (start and end):
            return (start, end)
        begun = parse_ts(coordinator.get("startedAt")) or start
        done = parse_ts(coordinator.get("endedAt")) or end
        clipped = (max(start, min(begun, end)), min(end, max(done, start)))
        metrics["runSec"] = (clipped[1] - clipped[0]).total_seconds()
        metrics["outsideRunSec"] = (metrics["spanSec"] or 0.0) - metrics["runSec"]
        return clipped

    intervals = [i for i in (window(m) for m in unique) if i[0] and i[1]]

    started = parse_ts(ledger.get("startedAt"))
    finished = parse_ts(ledger.get("finishedAt"))
    run_span = ((finished - started).total_seconds()
                if started and finished else None)
    active_sum = sum(m["spanSec"] or 0.0 for m in unique)
    work_sum = sum(m["activeSec"] or 0.0 for m in unique)
    covered = interval_union(intervals)
    rows_per_role = {}
    for metrics in sessions:
        rows_per_role[metrics["role"]] = rows_per_role.get(metrics["role"], 0) + 1
    roles = {}
    models = {}
    for metrics in unique:
        entry = roles.setdefault(metrics["role"], {"agents": rows_per_role.get(metrics["role"], 0),
                                                    "sessions": 0, "spanSec": 0.0,
                                                    "workSec": 0.0, "costUsd": 0.0})
        entry["sessions"] += 1
        entry["spanSec"] += metrics["spanSec"] or 0.0
        entry["workSec"] += metrics["activeSec"] or 0.0
        entry["costUsd"] += metrics["costUsd"]
        for model in metrics["models"]:
            entry = models.setdefault(model, {"agents": 0, "costUsd": 0.0,
                                              "totalTokens": 0})
            entry["agents"] += 1
            entry["costUsd"] += metrics["costUsd"]
            entry["totalTokens"] += metrics["tokens"]["totalTokens"]

    gates = ledger.get("gates") or {}
    return {
        "feature": ledger.get("feature"),
        "flow": ledger.get("flow"),
        "tracker": ledger.get("tracker"),
        "rundir": rundir,
        "ledger": ledger_path,
        "record_dirname": record_dirname(ledger),
        "startedAt": ledger.get("startedAt"),
        "finishedAt": ledger.get("finishedAt"),
        "spanSec": run_span,
        "activeSumSec": active_sum,
        "workSumSec": work_sum,
        "quietSumSec": active_sum - work_sum,
        "coveredSec": covered,
        "overlapSec": active_sum - covered,
        "sessionsCounted": len(unique),
        "ledgerRows": len(sessions),
        "ledgerDrift": ledger_drift(sessions),
        "models": ledger.get("models") or {},
        "gates": {
            "plan": {"requestedAt": (gates.get("plan") or {}).get("requestedAt"),
                     "approvedAt": (gates.get("plan") or {}).get("approvedAt"),
                     "waitSec": human_wait(gates.get("plan"))},
            "commit": {"requestedAt": (gates.get("commit") or {}).get("requestedAt"),
                       "approvedAt": (gates.get("commit") or {}).get("approvedAt"),
                       "waitSec": human_wait(gates.get("commit"))},
        },
        "items": {item_id: {"status": item.get("status"),
                            "reviewCount": item.get("reviewCount"),
                            "prUrl": item.get("prUrl")}
                  for item_id, item in (ledger.get("items") or {}).items()},
        "roles": roles,
        "costByModel": models,
        "sessions": sessions,
    }


def fmt_seconds(value):
    if value is None:
        return "unmeasured"
    return "%dh%02dm%02ds" % (int(value) // 3600, (int(value) % 3600) // 60,
                              int(value) % 60)


def print_human(record):
    print("Run: %s  flow %s  %s" % (record["feature"], record["flow"],
                                    record["tracker"]))
    print("  span          %s  (%s → %s)" % (fmt_seconds(record["spanSec"]),
                                             record["startedAt"],
                                             record["finishedAt"]))
    print("  active (sum)  %s   covered %s   overlap %s"
          % (fmt_seconds(record["activeSumSec"]),
             fmt_seconds(record["coveredSec"]),
             fmt_seconds(record["overlapSec"])))
    print("  work (sum)    %s   quiet %s   (%d sessions, %d ledger rows)"
          % (fmt_seconds(record["workSumSec"]), fmt_seconds(record["quietSumSec"]),
             record["sessionsCounted"], record["ledgerRows"]))
    for metrics in record["sessions"]:
        if metrics.get("outsideRunSec") is not None:
            print("  coordinator   %s of its %s span predates `startedAt` or follows "
                  "`finishedAt`" % (fmt_seconds(metrics["outsideRunSec"]),
                                     fmt_seconds(metrics["spanSec"])))
    print("  gate waits    plan %s   commit %s"
          % (fmt_seconds((record["gates"]["plan"] or {}).get("waitSec")),
             fmt_seconds((record["gates"]["commit"] or {}).get("waitSec"))))
    print("\nSessions:")
    for metrics in record["sessions"]:
        if not metrics["exists"]:
            print("  %-18s %-13s no transcript" % (metrics["name"], metrics["role"]))
            continue
        note = ("   same session as %s" % metrics["duplicateOf"]) if metrics.get("duplicateOf") else ""
        print("  %-18s %-13s %-9s %6d msgs  %10d tok  $%.6f  %s%s"
              % (metrics["name"], metrics["role"],
                 fmt_seconds(metrics["spanSec"]), metrics["messages"],
                 metrics["tokens"]["totalTokens"], metrics["costUsd"],
                 ",".join(metrics["models"]) or "no model recorded", note))
    print("\nBy model:")
    for model, entry in sorted(record["costByModel"].items()):
        print("  %-46s %2d agents  %10d tok  $%.6f"
              % (model, entry["agents"], entry["totalTokens"], entry["costUsd"]))
    print("\nItems:")
    for item_id, item in record["items"].items():
        print("  %-4s %-8s reviews=%s  %s"
              % (item_id, item.get("status"), item.get("reviewCount"),
                 item.get("prUrl") or ""))
    if record["ledgerDrift"]:
        print("\nLedger drift (ledger interval vs its own transcript):")
        for drift in record["ledgerDrift"]:
            print("  [%s] %s" % (drift["kind"], drift["detail"]))
    print("\ncorpus dirname: runs/%s" % record["record_dirname"])


def self_test():
    start = datetime(2026, 1, 1, 12, 0, 0, tzinfo=timezone.utc)
    end = datetime(2026, 1, 1, 12, 10, 0, tzinfo=timezone.utc)
    assert interval_union([(start, end)]) == 600
    assert interval_union([(start, end), (start, end)]) == 600  # overlap counts once
    second = datetime(2026, 1, 1, 12, 5, 0, tzinfo=timezone.utc)
    third = datetime(2026, 1, 1, 12, 20, 0, tzinfo=timezone.utc)
    assert interval_union([(start, end), (second, third)]) == 1200
    assert human_wait({"requestedAt": start.isoformat(),
                       "approvedAt": second.isoformat()}) == 300
    assert human_wait({"requestedAt": None, "approvedAt": second.isoformat()}) is None
    assert slug("#42: Fix Cache!") == "42-fix-cache"
    assert ponytail_passes({"ponytail": []}) == []
    assert ponytail_passes({}) == []
    assert [p["agent"] for p in ponytail_passes(
        {"ponytail": [{"agent": "ponytail-1"}, {"agent": "ponytail-2"}]})] == \
        ["ponytail-1", "ponytail-2"]
    assert [p["agent"] for p in ponytail_passes(
        {"ponytail": {"agent": "ponytail"}})] == ["ponytail"]
    # A span is not work: a session re-prompted across a suspended host keeps its
    # quiet hours out of `workSec`.
    stamps = [start, datetime(2026, 1, 1, 12, 2, 0, tzinfo=timezone.utc),
              datetime(2026, 1, 1, 22, 0, 0, tzinfo=timezone.utc),
              datetime(2026, 1, 1, 22, 5, 0, tzinfo=timezone.utc)]
    assert quiet_seconds(stamps, gap=600) == 35880  # 12:02 → 22:00 only
    assert quiet_seconds([start, second], gap=600) == 0
    rows = [{"name": "item-01", "session": "/tmp/a.jsonl", "role": "worker"},
            {"name": "item-01", "session": "/tmp/a.jsonl", "role": "fix"},
            {"name": "review-01-r1", "session": "/tmp/b.jsonl", "role": "code-review"}]
    assert [r["name"] for r in unique_by_session(rows)] == ["item-01", "review-01-r1"]
    drift = ledger_drift([{"name": "review-15-r1", "role": "code-review", "exists": True,
                           "startedAt": second.isoformat(), "endedAt": start.isoformat(),
                           "firstTs": third.isoformat(), "lastTs": third.isoformat()}])
    assert {d["kind"] for d in drift} == {"backwards", "before-session"}, drift
    assert ledger_drift([{"name": "x", "role": "worker", "exists": True,
                          "startedAt": start.isoformat(), "endedAt": end.isoformat(),
                          "firstTs": datetime(2026, 1, 1, 12, 0, 30,
                                              tzinfo=timezone.utc).isoformat(),
                          "lastTs": end.isoformat()}]) == []
    assert record_dirname({"startedAt": start.isoformat(),
                           "rundir": "/tmp/repo/.herdr-runs/My Feature",
                           "feature": "My Feature"}) == "2026-01-01-repo-my-feature"
    print("record_dirname:", record_dirname(
        {"startedAt": start.isoformat(), "rundir": "/tmp/repo/.herdr-runs/x",
         "feature": "x"}))
    print("self-test: ok")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rundir", nargs="?", default=DEFAULT_RUNDIR)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--output-dir", default=None)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)
    if args.self_test:
        self_test()
        return 0
    record = build_record(args.rundir)
    if args.output_dir:
        os.makedirs(args.output_dir, exist_ok=True)
        with open(os.path.join(args.output_dir, "run.json"), "w",
                  encoding="utf-8") as handle:
            json.dump(record, handle, indent=2)
    if args.json:
        json.dump(record, sys.stdout, indent=2)
        print()
    else:
        print_human(record)
    return 0


if __name__ == "__main__":
    sys.exit(main())
