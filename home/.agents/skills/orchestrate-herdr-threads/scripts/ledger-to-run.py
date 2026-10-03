#!/usr/bin/env python3
"""Project a Herdr run ledger into a dagr run file (contract v3).

The ledger (`$RUNDIR/orchestration.json`) is the machine record: it holds what
resume and the retro need — session paths, worktrees, PR urls, tickets, the
model roster. `dagr-run.json` is a **derived view** for the dagr pane: neither
the coordinator nor any worker hand-edits it, so the contract's semantics live
here once, in reviewed code, instead of in every write the coordinator makes.

Named `dagr-run.json`, not `run.json`: the retro's metrics record is also
called `run.json`, and the pane resolves its file from `$DAGR_RUN` anyway.

Derived, therefore: re-run this after every ledger write. The pane watches the
file and reloads on mtime, so the run is live without a second source of truth.

Read-only against the ledger. Stdlib only. Deterministic: same ledger + same
`--now` gives byte-identical output.

Usage:
  ledger-to-run.py <rundir-or-ledger.json> [--out PATH] [--now ISO] [--check]
  ledger-to-run.py --self-test

Contract semantics this projection is responsible for (the traps):
  * A review that returns FINDINGS settles `done` — the REVIEW succeeded. It is
    the *reviewed* attempt that goes `rejected`. Encoding the review task as
    failed claims something false about history.
  * A fix round is a new attempt with `cause.sent_back` naming the review
    attempt that sent it back, never a mutated earlier attempt.
  * Every terminal outcome carries an evidence tier. Worker DONE/BLOCKED and
    review VERDICT lines are typed envelopes, so they are `reported` — never
    `verified`. Nothing here mechanically checks the work; claiming otherwise
    would be the exact blurring the contract exists to prevent.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone

ITEM_STATE = {
    "todo": "queued",
    "running": "working",
    "done": "done",
    "failed": "failed",
    "blocked": "blocked",
}
PLAN_GATE = "G-PLAN"
COMMIT_GATE = "G-COMMIT"
PONYTAIL = "PON"


def utcnow():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def stamp(value):
    """Normalize one ISO-8601 timestamp, or None when absent/unusable."""
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def run_id(feature, started_at):
    """Stable per-run id: feature + the run's start, so two runs cannot collide."""
    slug = "".join(c if c.isalnum() else "-" for c in str(feature or "run").lower())
    slug = "-".join(p for p in slug.split("-") if p) or "run"
    return "run-%s%s" % (slug, ("-" + started_at[:10]) if started_at else "")


def attempts_for_item(item_id, item):
    """The item's attempt history, one per round: initial, then one per fix."""
    task_id = "I" + item_id
    reviews = item.get("reviews") or []
    fixes = item.get("fixes") or []
    by_pass = {}
    for review in reviews:
        by_pass[review.get("pass")] = review

    attempts = []
    for round_n in range(1, len(fixes) + 2):
        review = by_pass.get(round_n)
        fix = fixes[round_n - 2] if round_n > 1 else None
        previous_review = by_pass.get(round_n - 1) if round_n > 1 else None
        started = stamp((fix or {}).get("startedAt") or (item.get("startedAt") if round_n == 1 else None))
        ended = stamp((fix or {}).get("endedAt") or (item.get("endedAt") if review else None))

        attempt = {
            "id": "%s\u00b7a%d" % (task_id, round_n),
            "n": round_n,
            "actor": (item.get("worker") or {}).get("agent"),
            "model": None,
        }
        locator = (item.get("worker") or {}).get("pane")
        if locator and round_n == len(fixes) + 1:
            attempt["locator"] = {"pane": locator, "agent": (item.get("worker") or {}).get("agent")}

        if round_n == 1:
            attempt["cause"] = {"type": "initial"}
        else:
            attempt["cause"] = {"type": "sent_back"}
            if previous_review is not None:
                attempt["cause"]["by"] = previous_review.get("agent")
                attempt["cause"]["ref"] = "R%s\u00b7a%s" % (item_id, previous_review.get("pass"))
                # Why it came back: the report is where the findings are.
                if previous_review.get("report"):
                    attempt["cause"]["reason"] = str(previous_review["report"])
            elif fix:
                attempt["cause"]["by"] = "coordinator"

        verdict = (review or {}).get("verdict")
        if verdict is None:
            # Round in flight: honest state from the ledger's item status.
            state = ITEM_STATE.get(item.get("status"), "queued")
            state = state if state in ("working", "queued") else "queued"
            attempt["state"] = state
        elif str(verdict).upper().startswith("CLEAN"):
            attempt["state"] = "done"
            attempt["outcome"] = {
                "result": "done",
                "evidence": "reported",
                "receipt": "worker DONE; review %s: VERDICT CLEAN" % (review.get("agent") or "review"),
            }
        else:
            attempt["state"] = "rejected"
            attempt["outcome"] = {
                "result": "rejected",
                "evidence": "reported",
                "receipt": "review %s: VERDICT FINDINGS" % (review.get("agent") or "review"),
            }
            if review.get("report"):
                attempt["outcome"]["reason"] = str(review["report"])

        if started:
            attempt["started_at"] = started
        if ended and attempt["state"] in ("done", "failed", "rejected", "settled_unverified"):
            attempt["ended_at"] = ended
        attempts.append({k: v for k, v in attempt.items() if v is not None})
    return attempts


def item_task(item_id, item, models, plan_gate_done):
    task = {
        "id": "I" + item_id,
        "title": item.get("title") or ("item " + item_id),
        "kind": "impl",
        "owner": (item.get("worker") or {}).get("agent"),
        "state": ITEM_STATE.get(item.get("status"), "queued"),
    }
    deps = ["I" + str(dep) for dep in item.get("blockedBy") or []]
    if not plan_gate_done:
        deps.append(PLAN_GATE)
    task["deps"] = deps
    if item.get("criteria"):
        task["criteria"] = item["criteria"]
    attempts = attempts_for_item(item_id, item)
    if attempts:
        task["attempts"] = attempts
    if task["state"] == "blocked":
        if deps:
            # Blocked *by a dependency* is not a human decision: dagr derives
            # `waits I01` from a queued task with an unmet dep. Claiming
            # `unblock: operator` here sends the operator to fix something
            # another worker owns.
            task["state"] = "queued"
        else:
            task["unblock"] = item.get("unblock") or "operator"
    return {k: v for k, v in task.items() if v is not None}


def review_task(item_id, item):
    """One task per item's review lane, one attempt per review pass."""
    reviews = item.get("reviews") or []
    if not reviews:
        return None
    attempts = []
    for review in reviews:
        attempt = {
            "id": "R%s\u00b7a%s" % (item_id, review.get("pass")),
            "n": review.get("pass"),
            "cause": {"type": "initial"} if review.get("pass") == 1 else {"type": "followup",
                                                                        "ref": "I%s\u00b7a%s" % (item_id, review.get("pass"))},
            "actor": review.get("agent"),
            "state": "done",
            "outcome": {
                "result": "done",
                "evidence": "reported",
                "receipt": "VERDICT %s" % (review.get("verdict") or "UNKNOWN"),
            },
        }
        started, ended = stamp(review.get("startedAt")), stamp(review.get("endedAt"))
        if started:
            attempt["started_at"] = started
        if ended:
            attempt["ended_at"] = ended
        if review.get("report"):
            attempt["outcome"]["reason"] = str(review["report"])
        attempts.append({k: v for k, v in attempt.items() if v is not None})
    return {
        "id": "R" + item_id,
        "title": "review: %s" % (item.get("title") or item_id),
        "kind": "review",
        "owner": reviews[-1].get("agent"),
        "state": "done",
        "deps": ["I" + item_id],
        "attempts": attempts,
    }


def operator_task(task_id, title, kind, requested, approved, detail, events, inputs=None, deps=None):
    """A human-decision task: plan question, or the commit fan-in gate."""
    requested, approved = stamp(requested), stamp(approved)
    if approved:
        state = "done"
    elif requested:
        state = "blocked"
    else:
        state = "queued"
    task = {
        "id": task_id,
        "title": title,
        "kind": kind,
        "owner": "operator",
        "state": state,
        "deps": deps or [],
    }
    if inputs:
        task["inputs"] = inputs
    if state == "blocked":
        task["unblock"] = "operator"
    if approved:
        attempt = {
            "id": "%s\u00b7a1" % task_id,
            "n": 1,
            "cause": {"type": "initial"},
            "actor": "operator",
            "state": "done",
            "outcome": {"result": "done", "evidence": "reported", "receipt": "operator: %s" % detail},
        }
        if requested:
            attempt["started_at"] = requested
        attempt["ended_at"] = approved
        task["attempts"] = [attempt]
        events.append({
            "at": approved,
            "type": "directive",
            "verb": "answer" if kind == "question" else "rule",
            "by": "operator",
            "task": task_id,
            "detail": detail,
        })
    return task


def project(ledger, now):
    feature = ledger.get("feature") or "run"
    started_at = stamp(ledger.get("startedAt"))
    run = {"id": run_id(feature, started_at), "title": str(feature)}
    if started_at:
        run["started_at"] = started_at
    coordinator = ledger.get("coordinator") or {}
    orchestrator = {k: coordinator[k] for k in ("pane", "agent") if coordinator.get(k)}
    if orchestrator:
        run["orchestrator"] = orchestrator

    events = []
    gates = ledger.get("gates") or {}
    plan = gates.get("plan") or {}
    commit = gates.get("commit") or {}
    plan_done = bool(stamp(plan.get("approvedAt")))
    items = ledger.get("items") or {}

    tasks = [
        operator_task(PLAN_GATE, "plan gate: operator approves the plan", "question",
                      plan.get("requestedAt"), plan.get("approvedAt"), "plan approved", events)
    ]

    models = ledger.get("models") or {}
    for item_id in sorted(items):
        item = items[item_id] or {}
        task = item_task(item_id, item, models, plan_done)
        worker_model = models.get("worker")
        if worker_model and worker_model != "pi-default":
            for attempt in task.get("attempts", []):
                attempt.setdefault("model", worker_model)
        tasks.append(task)
        lane = review_task(item_id, item)
        if lane:
            tasks.append(lane)

    item_ids = [str(i) for i in sorted(items)]
    tasks.append(operator_task(COMMIT_GATE, "commit gate: all items settled", "gate",
                               commit.get("requestedAt"), commit.get("approvedAt"), "commit approved",
                               events, inputs=["I" + i for i in item_ids], deps=["I" + i for i in item_ids]))

    ponytail = ledger.get("ponytail")
    if ponytail:
        verdict = str(ponytail.get("verdict") or "PENDING").upper()
        settled = verdict in ("CLEAN", "FINDINGS")
        task = {
            "id": PONYTAIL,
            "title": "ponytail review: whole-run diff",
            "kind": "review",
            "owner": ponytail.get("agent") or "ponytail",
            "state": "done" if settled else "working",
            "deps": ["I" + i for i in item_ids],
            "attempts": [{
                "id": "%s\u00b7a1" % PONYTAIL,
                "n": 1,
                "cause": {"type": "initial"},
                "actor": ponytail.get("agent") or "ponytail",
                "state": "done" if settled else "working",
                "outcome": ({"result": "done", "evidence": "reported", "receipt": "VERDICT %s" % verdict}
                            if settled else None),
            }],
        }
        if ponytail.get("verdict") is None:
            task["attempts"][0].pop("outcome", None)
        started, ended = stamp(ponytail.get("startedAt")), stamp(ponytail.get("endedAt"))
        if started:
            task["attempts"][0]["started_at"] = started
        if ended:
            task["attempts"][0]["ended_at"] = ended
        tasks.append(task)

    document = {
        "dagr": 3,
        "run": run,
        "generated_at": now,
        "tasks": tasks,
    }
    if events:
        document["events"] = sorted(events, key=lambda e: e["at"])
    return document


def find_dagr():
    for candidate in (os.environ.get("DAGR_BIN"),
                      shutil.which("dagr"),
                      os.path.join(os.environ.get("HERDR_PLUGIN_ROOT", ""), "bin", "dagr")):
        if candidate and os.path.exists(candidate):
            return candidate
    root = os.path.expanduser("~/.config/herdr/plugins/github")
    if os.path.isdir(root):
        for name in sorted(os.listdir(root)):
            candidate = os.path.join(root, name, "bin", "dagr")
            if os.path.exists(candidate):
                return candidate
    return None


def load_ledger(target):
    path = target
    if os.path.isdir(target):
        path = os.path.join(target, "orchestration.json")
    with open(path, encoding="utf-8") as handle:
        return json.load(handle), os.path.dirname(os.path.abspath(path))


def self_test():
    ledger = {
        "feature": "demo", "startedAt": "2026-09-27T10:00:00Z", "flow": "A",
        "coordinator": {"pane": "w1:p1"}, "models": {"worker": "pi-default"},
        "gates": {"plan": {"requestedAt": "2026-09-27T09:59:00Z", "approvedAt": "2026-09-27T10:00:00Z"},
                  "commit": {"requestedAt": None, "approvedAt": None}},
        "items": {
            "01": {"title": "one", "status": "done", "blockedBy": [], "reviewCount": 2,
                   "worker": {"agent": "item-01", "pane": "w1:p2"},
                   "reviews": [{"pass": 1, "agent": "review-01-r1", "verdict": "FINDINGS", "report": "reports/r1.md"},
                               {"pass": 2, "agent": "review-01-r2", "verdict": "CLEAN", "report": "reports/r2.md"}],
                   "fixes": [{"pass": 1, "agent": "fix-01-f1"}]},
            "02": {"title": "two", "status": "blocked", "blockedBy": ["01"], "reviewCount": 0,
                   "worker": {"agent": "item-02", "pane": "w1:p3"}, "reviews": [], "fixes": []},
        },
        "ponytail": {"agent": "ponytail", "verdict": "CLEAN", "report": "reports/p.md"},
    }
    doc = project(ledger, "2026-09-27T11:00:00Z")

    # The one semantic rule that matters most: the review settles done, the
    # reviewed attempt is what goes rejected, and the fix is a new attempt.
    one = next(t for t in doc["tasks"] if t["id"] == "I01")
    assert [a["state"] for a in one["attempts"]] == ["rejected", "done"], one["attempts"]
    assert one["attempts"][1]["cause"] == {"type": "sent_back", "by": "review-01-r1",
                                           "ref": "R01\u00b7a1", "reason": "reports/r1.md"}
    lane = next(t for t in doc["tasks"] if t["id"] == "R01")
    assert lane["state"] == "done" and [a["outcome"]["evidence"] for a in lane["attempts"]] == ["reported", "reported"]

    # Every terminal outcome states its evidence; nothing claims `verified`.
    for task in doc["tasks"]:
        for attempt in task.get("attempts", []):
            if attempt["state"] in ("done", "failed", "rejected", "settled_unverified"):
                assert attempt["outcome"]["evidence"] in ("reported", "heuristic", "asserted"), attempt

    ids = [t["id"] for t in doc["tasks"]]
    assert len(ids) == len(set(ids))
    attempt_ids = [a["id"] for t in doc["tasks"] for a in t.get("attempts", [])]
    assert len(attempt_ids) == len(set(attempt_ids)) and not set(attempt_ids) & set(ids)

    blocked = next(t for t in doc["tasks"] if t["id"] == "I02")
    # Blocked by a dependency renders as `waits`; only a dependency-free block
    # is the operator's to unblock.
    assert blocked["state"] == "queued" and "unblock" not in blocked, blocked
    import copy
    independent = copy.deepcopy(ledger)
    independent["items"]["02"]["blockedBy"] = []
    assert next(t for t in project(independent, "2026-09-27T11:00:00Z")["tasks"]
                if t["id"] == "I02")["unblock"] == "operator"
    gate = next(t for t in doc["tasks"] if t["id"] == COMMIT_GATE)
    assert gate["kind"] == "gate" and gate["inputs"] == ["I01", "I02"] and gate["state"] == "queued"
    assert doc["events"][0]["verb"] == "answer" and doc["events"][0]["by"] == "operator"
    assert project(ledger, "2026-09-27T11:00:00Z") == doc  # deterministic

    dagr = find_dagr()
    if dagr:
        import tempfile
        handle = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8")
        try:
            json.dump(doc, handle)
            handle.close()
            result = subprocess.run([dagr, "check", handle.name], capture_output=True, text=True)
            sys.stdout.write(result.stdout)
            assert result.returncode == 0, "dagr check failed: " + result.stdout + result.stderr
        finally:
            os.unlink(handle.name)
    print("self-test ok")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("target", nargs="?", help="run directory or ledger json")
    parser.add_argument("--out", help="run file path (default <rundir>/dagr-run.json)")
    parser.add_argument("--now", help="override generated_at (tests)")
    parser.add_argument("--check", action="store_true", help="run `dagr check` on the result")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return 0
    if not args.target:
        parser.error("need a run directory or ledger path")

    ledger, rundir = load_ledger(args.target)
    document = project(ledger, stamp(args.now) or utcnow())
    out = args.out or os.path.join(rundir, "dagr-run.json")
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    # Write-then-rename: the pane reloads on mtime and must never read a
    # half-written document.
    temp = out + ".tmp"
    with open(temp, "w", encoding="utf-8") as handle:
        json.dump(document, handle, indent=2)
        handle.write("\n")
    os.replace(temp, out)
    print(out)

    if args.check:
        dagr = find_dagr()
        if not dagr:
            print("ledger-to-run: dagr not found; skipped check", file=sys.stderr)
            return 1
        return subprocess.run([dagr, "check", out]).returncode
    return 0


if __name__ == "__main__":
    sys.exit(main())
