#!/usr/bin/env python3
"""Read a Herdr orchestration run's records into numbers (adapter).

This script is Herdr's **telemetry adapter**: Herdr keeps no turn telemetry of
its own, so the facts come from the run ledger (`$RUNDIR/orchestration.json`)
plus the pi session transcripts it names. Each ledger agent's transcript is
read into one **lane**, and `orchestrate-core/scripts/ledger_read.py` owns the
record — the figures, the role vocabulary and the output schema, which is the
same one BB's adapter emits.

A pi session transcript is JSONL; every event carries a timestamp, and every
assistant message carries the model and `usage` (tokens plus pi's own computed
cost).

Read-only, stdlib-only, safe to re-run.

The retro's own session is named by the ledger's `retro` row and reported
separately, never in the run's totals: the retro is the run's recorder, not a
lane of it.

Usage:
  run-metrics.py <rundir> [--json] [--output-dir DIR] [--self-test]
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone

DEFAULT_RUNDIR = "."
QUIET_GAP_SEC = 600

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))), "orchestrate-core", "scripts"))
from ledger_read import (  # noqa: E402
    agents_from_ledger, corpus_dirname, fmt_seconds, parse_ts, read_run,
)


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
    """Seconds of a session's span that hold no message for longer than `gap`."""
    ordered = sorted(t for t in times if t)
    return sum((b - a).total_seconds() for a, b in zip(ordered, ordered[1:])
               if (b - a).total_seconds() > gap)


def unique_by_session(lanes):
    """One lane per transcript: a fix round re-prompts the worker's own session."""
    seen, unique = set(), []
    for lane in lanes:
        path = lane.get("session")
        if path and path in seen:
            continue
        seen.add(path)
        unique.append(lane)
    return unique


def session_metrics(path):
    """Timeline, tokens, cost and models for one pi session transcript."""
    result = {
        "session": path, "exists": bool(path and os.path.exists(path)),
        "firstTs": None, "lastTs": None, "spanSec": None, "messages": 0,
        "activeSec": None, "quietSec": None,
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


def cost_of(metrics):
    """(`basis`, usd) for one lane. pi records its own cost; a $0.00 with tokens
    is unpriced, not free, and no usage at all is unmeasured."""
    if metrics.get("costUsd"):
        return "reported", metrics["costUsd"]
    if (metrics.get("tokens") or {}).get("totalTokens"):
        return "unpriced", None
    return "unmeasured", None


def lane_of(agent, executor):
    """One ledger agent + its transcript -> one lane, in the shared shape."""
    metrics = session_metrics(agent.get("session"))
    basis, usd = cost_of(metrics)
    start, end = parse_ts(metrics["firstTs"]), parse_ts(metrics["lastTs"])
    lane = {
        "name": agent["name"], "role": agent["role"], "item": agent.get("item"),
        "session": agent.get("session"), "exists": metrics["exists"],
        "startedAt": agent.get("startedAt"), "endedAt": agent.get("endedAt"),
        "firstTs": metrics["firstTs"], "lastTs": metrics["lastTs"],
        "spanSec": metrics["spanSec"], "activeSec": metrics["activeSec"],
        "quietSec": metrics["quietSec"], "workSec": metrics["activeSec"],
        "turns": metrics["messages"], "messages": metrics["messages"],
        "models": metrics["models"], "tokens": metrics["tokens"],
        "costUsd": metrics["costUsd"],
        "cost": {"basis": basis, "reported": usd, "estimated": None},
        "intervals": [],
    }
    # The coordinator's pi session outlives the run: the ledger's own two ends
    # bound it, and the part outside is reported rather than absorbed.
    if lane["role"] == "coordinator" and start and end:
        begun = parse_ts(executor.get("startedAt")) or start
        done = parse_ts(executor.get("endedAt")) or end
        start, end = max(start, min(begun, end)), min(end, max(done, start))
        lane["runSec"] = (end - start).total_seconds()
        lane["outsideRunSec"] = (lane["spanSec"] or 0.0) - lane["runSec"]
    if start and end:
        lane["intervals"] = [[start.isoformat(), end.isoformat()]]
    return lane


def project_of(rundir, ledger):
    root = str(ledger.get("rundir") or rundir or "").split("/.herdr-runs/")[0]
    return os.path.basename(root.rstrip("/")) or "project"


def build_record(rundir):
    ledger_path = os.path.join(rundir, "orchestration.json")
    if not os.path.exists(ledger_path):
        raise SystemExit("no ledger at %s" % ledger_path)
    with open(ledger_path, encoding="utf-8") as handle:
        ledger = json.load(handle)
    executor = (ledger.get("executors") or [{}])[0]
    lanes = unique_by_session([lane_of(agent, executor)
                               for agent in agents_from_ledger(ledger)])
    run_lanes = [lane for lane in lanes if lane["role"] != "retro"]
    retro = [lane for lane in lanes if lane["role"] == "retro"]
    # Everything ledger-derived and every rollup is the shared reader's; the
    # adapter only supplies lanes and the runtime's project/feature identity.
    record = read_run(ledger, run_lanes + retro, "herdr",
                      feature=ledger.get("feature"),
                      project=project_of(rundir, ledger),
                      fallback_date=datetime.now(timezone.utc).strftime("%Y-%m-%d"))
    record["run"]["sessionsCounted"] = len(run_lanes)
    record["run"]["ledgerRows"] = len(agents_from_ledger(ledger))
    return record


def print_human(record):
    run = record["run"]
    print("Run: %s  flow %s  %s" % (run["feature"], run["flow"], run["tracker"]))
    print("  span          %s  (%s → %s)" % (fmt_seconds(run["spanSec"]),
                                             run["startedAt"], run["endedAt"]))
    print("  active (sum)  %s   covered %s   overlap %s"
          % (fmt_seconds(run["activeSumSec"]), fmt_seconds(run["coveredSec"]),
             fmt_seconds(run["overlapSec"])))
    print("  work (sum)    %s   quiet %s   (%d sessions, %d ledger rows%s)"
          % (fmt_seconds(run["workSumSec"]), fmt_seconds(run["quietSumSec"]),
             run.get("sessionsCounted", len(record["lanes"])), run.get("ledgerRows", 0),
             " + retro" if record["retro"] else ""))
    for lane in record["lanes"]:
        if lane.get("outsideRunSec") is not None:
            print("  coordinator   %s of its %s span predates `startedAt` or follows "
                  "`finishedAt`" % (fmt_seconds(lane["outsideRunSec"]),
                                    fmt_seconds(lane["spanSec"])))
    print("  gate waits    plan %s   commit %s"
          % (fmt_seconds((record["gates"]["plan"] or {}).get("waitSec")),
             fmt_seconds((record["gates"]["commit"] or {}).get("waitSec"))))

    def row(lane):
        if not lane.get("exists"):
            print("  %-18s %-13s no transcript" % (lane["name"], lane["role"]))
            return
        note = ("   same session as %s" % lane["duplicateOf"]) if lane.get("duplicateOf") else ""
        print("  %-18s %-13s %-9s %6d msgs  %10d tok  %s  %s%s"
              % (lane["name"], lane["role"], fmt_seconds(lane["spanSec"]),
                 lane.get("messages") or 0, (lane.get("tokens") or {}).get("totalTokens") or 0,
                 "$%.6f" % lane["costUsd"] if lane["costUsd"] else (lane.get("cost") or {}).get("basis"),
                 ",".join(lane["models"]) or "no model recorded", note))

    print("\nSessions:")
    for lane in record["lanes"]:
        row(lane)
    if record["retro"]:
        print("\nRetro (the run's recorder — outside the totals above):")
        for lane in record["retro"]:
            row(lane)
    print("\nBy model:")
    for model, entry in sorted(record["costByModel"].items()):
        print("  %-46s %2d agents  %10d tok  $%.6f"
              % (model, entry["agents"], entry["totalTokens"], entry["costUsd"]))
    print("\nItems:")
    for item_id, item in record["items"].items():
        print("  %-4s %-8s reviews=%s  %-18s %s"
              % (item_id, item.get("status"), item.get("reviewCount"),
                 (item.get("cause") or {}).get("code") or "", item.get("prUrl") or ""))
    blocks = record["causes"]
    if blocks.get("codes") or blocks.get("untyped"):
        print("\nBlocks by cause:")
        for code, ids in sorted(blocks["codes"].items()):
            print("  %-18s %s" % (code, ", ".join(ids)))
        if blocks.get("untyped"):
            print("  %-18s %s   <- a finding: cause-contract.md"
                  % ("no cause", ", ".join(blocks["untyped"])))
    if record["drift"]:
        print("\nLedger drift (ledger interval vs its own transcript):")
        for drift in record["drift"]:
            print("  [%s] %s" % (drift["kind"], drift["detail"]))
    print("\nFINDINGS")
    print("\n".join("    - %s" % f for f in record["findings"]) or "    (none)")
    print("\ncorpus dirname: runs/%s" % record["record_dirname"])


def self_test(tmp=None):
    """Assert the adapter: transcript reading, cost basis, window, one schema."""
    import tempfile
    start = datetime(2026, 1, 1, 12, 0, 0, tzinfo=timezone.utc)
    end = datetime(2026, 1, 1, 12, 10, 0, tzinfo=timezone.utc)
    second = datetime(2026, 1, 1, 12, 5, 0, tzinfo=timezone.utc)
    third = datetime(2026, 1, 1, 12, 20, 0, tzinfo=timezone.utc)
    assert interval_union([(start, end)]) == 600
    assert interval_union([(start, end), (second, third)]) == 1200
    stamps = [start, datetime(2026, 1, 1, 12, 2, 0, tzinfo=timezone.utc),
              datetime(2026, 1, 1, 22, 0, 0, tzinfo=timezone.utc),
              datetime(2026, 1, 1, 22, 5, 0, tzinfo=timezone.utc)]
    assert quiet_seconds(stamps, gap=600) == 35880
    rows = [{"name": "item-01", "session": "/tmp/a.jsonl"},
            {"name": "item-01", "session": "/tmp/a.jsonl"},
            {"name": "review-01-r1", "session": "/tmp/b.jsonl"}]
    assert [r["name"] for r in unique_by_session(rows)] == ["item-01", "review-01-r1"]
    assert cost_of({}) == ("unmeasured", None)
    assert cost_of({"tokens": {"totalTokens": 5}}) == ("unpriced", None)
    assert cost_of({"costUsd": 0.25, "tokens": {"totalTokens": 5}}) == ("reported", 0.25)

    with tempfile.TemporaryDirectory() as rundir:
        session = os.path.join(rundir, "item-01.jsonl")
        with open(session, "w") as handle:
            for stamp, text in [("2026-01-01T12:05:00Z", "a"), ("2026-01-01T12:15:00Z", "b")]:
                handle.write(json.dumps({"type": "message", "timestamp": stamp,
                                         "message": {"role": "assistant", "provider": "vendor",
                                                     "model": "worker", "usage": {
                                                         "totalTokens": 10,
                                                         "cost": {"total": 0.25}}}}) + "\n")
        ledger = {
            "runtime": "herdr", "feature": "demo", "tracker": "scratch demo", "flow": "A",
            "mode": "gated", "rundir": rundir + "/.herdr-runs/demo",
            "startedAt": "2026-01-01T12:00:00Z", "finishedAt": "2026-01-01T12:30:00Z",
            "gates": {"plan": {"requestedAt": "2026-01-01T11:58:00Z",
                               "approvedAt": "2026-01-01T12:00:00Z"}},
            "executors": [{"id": "coordinator", "session": None}],
            "items": {"01": {"status": "done", "worker": {"id": "item-01", "session": session}}},
        }
        with open(os.path.join(rundir, "orchestration.json"), "w") as handle:
            json.dump(ledger, handle)
        record = build_record(rundir)
        assert record["schemaVersion"] == 2 and record["runtime"] == "herdr"
        assert record["run"]["spanSec"] == 1800
        assert record["run"]["humanWaitSec"] == 120
        assert record["record_dirname"] == corpus_dirname(
            "2026-01-01", "herdr", os.path.basename(rundir), "demo")
        assert record["costByModel"]["vendor/worker"]["totalTokens"] == 20
        assert any(lane["role"] == "worker" for lane in record["lanes"])
        assert [lane["role"] for lane in record["retro"]] == []
    print("run-metrics (herdr) self-test: ok")


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
