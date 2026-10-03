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


def session_metrics(path):
    """Timeline, tokens, cost and models for one pi session transcript."""
    result = {
        "session": path, "exists": bool(path and os.path.exists(path)),
        "firstTs": None, "lastTs": None, "spanSec": None, "messages": 0,
        "tokens": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0,
                   "reasoning": 0, "totalTokens": 0},
        "costUsd": 0.0, "models": [],
    }
    if not result["exists"]:
        return result
    first = last = None
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
                       "item": None, "session": coordinator.get("session")})
    for item_id, item in sorted((ledger.get("items") or {}).items()):
        worker = item.get("worker") or {}
        if worker.get("agent"):
            agents.append({"name": worker["agent"], "role": "worker",
                           "item": item_id, "session": worker.get("session")})
        for review in item.get("reviews") or []:
            agents.append({"name": review.get("agent", "review-%s" % item_id),
                           "role": "code-review", "item": item_id,
                           "session": review.get("session")})
        for fix in item.get("fixes") or []:
            agents.append({"name": fix.get("agent", "fix-%s" % item_id),
                           "role": "fix", "item": item_id,
                           "session": fix.get("session")})
    for pass_ in ponytail_passes(ledger):
        agents.append({"name": pass_["agent"], "role": "ponytail",
                       "item": None, "session": pass_.get("session")})
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
                        "item": agent["item"]})
        sessions.append(metrics)

    intervals = []
    for metrics in sessions:
        start = parse_ts(metrics["firstTs"])
        end = parse_ts(metrics["lastTs"])
        if start and end:
            intervals.append((start, end))

    started = parse_ts(ledger.get("startedAt"))
    finished = parse_ts(ledger.get("finishedAt"))
    run_span = ((finished - started).total_seconds()
                if started and finished else None)
    active_sum = sum(m["spanSec"] or 0.0 for m in sessions)
    roles = {}
    models = {}
    for metrics in sessions:
        roles.setdefault(metrics["role"], {"agents": 0, "spanSec": 0.0,
                                           "costUsd": 0.0})
        roles[metrics["role"]]["agents"] += 1
        roles[metrics["role"]]["spanSec"] += metrics["spanSec"] or 0.0
        roles[metrics["role"]]["costUsd"] += metrics["costUsd"]
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
        "coveredSec": interval_union(intervals),
        "overlapSec": active_sum - interval_union(intervals),
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
    print("  gate waits    plan %s   commit %s"
          % (fmt_seconds((record["gates"]["plan"] or {}).get("waitSec")),
             fmt_seconds((record["gates"]["commit"] or {}).get("waitSec"))))
    print("\nSessions:")
    for metrics in record["sessions"]:
        if not metrics["exists"]:
            print("  %-18s %-13s no transcript" % (metrics["name"], metrics["role"]))
            continue
        print("  %-18s %-13s %-9s %6d msgs  %10d tok  $%.6f  %s"
              % (metrics["name"], metrics["role"],
                 fmt_seconds(metrics["spanSec"]), metrics["messages"],
                 metrics["tokens"]["totalTokens"], metrics["costUsd"],
                 ",".join(metrics["models"]) or "no model recorded"))
    print("\nBy model:")
    for model, entry in sorted(record["costByModel"].items()):
        print("  %-46s %2d agents  %10d tok  $%.6f"
              % (model, entry["agents"], entry["totalTokens"], entry["costUsd"]))
    print("\nItems:")
    for item_id, item in record["items"].items():
        print("  %-4s %-8s reviews=%s  %s"
              % (item_id, item.get("status"), item.get("reviewCount"),
                 item.get("prUrl") or ""))
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
