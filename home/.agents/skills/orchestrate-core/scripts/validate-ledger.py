#!/usr/bin/env python3
"""Check a run ledger against the item lifecycle and the ledger invariants.

Both threads skills run this after every ledger write, and the Herdr projection
reports it as part of rendering, so a write error is caught by the writer while
it still knows what it meant. The contract is `../threads.md#the-item-lifecycle`
(the transitions) with `../cause-contract.md` (the cause vocabulary) and
`../ledger.md` (the shape); the checks themselves are `ledger_errors` in
`orchestrate_common.py`, so this file and the projection cannot drift.

It reads one file, never a run, and exits non-zero on any error.

    python3 validate-ledger.py <ledger.json>
    python3 validate-ledger.py --self-test
"""

import copy
import json
import sys

from orchestrate_common import ledger_errors

# A ledger both runtimes write, with one item in each status the checker has
# something to say about. `ledger-to-run.py`'s self-test reads the same shape.
GOOD = {
    "runtime": "bb", "feature": "demo", "project": "p", "tracker": "scratch demo",
    "flow": "A", "mode": "gated",
    "startedAt": "2026-09-27T10:00:00Z", "finishedAt": None,
    "models": {"worker": "pi-default"}, "served": {"worker": "pi-default"},
    "ciBaseline": [], "validationBaseline": {},
    "classFixes": [{"class": "unbounded-retry", "brief": "cap the retry loop at its caller",
                    "items": ["01"], "id": "fix-class-1", "session": None,
                    "startedAt": "2026-09-27T10:06:00Z", "endedAt": "2026-09-27T10:09:00Z"}],
    "executors": [{"id": "manager-1", "pane": None, "session": None,
                   "startedAt": "2026-09-27T10:00:00Z", "endedAt": None}],
    "gates": {"plan": {"requestedAt": "2026-09-27T09:59:00Z",
                       "approvedAt": "2026-09-27T10:00:00Z", "auto": None},
              "commit": {"requestedAt": None, "approvedAt": None, "auto": None}},
    "items": {
        "01": {"title": "one", "status": "done", "blockedBy": [], "prUrl": None,
               "dispatchAttempt": {"at": "2026-09-27T09:59:30Z", "role": "worker",
                                   "label": "ITEM · one"},
               "worker": {"id": "item-01", "startedAt": "2026-09-27T10:00:00Z",
                          "endedAt": "2026-09-27T10:12:00Z"},
               "startedAt": "2026-09-27T10:00:00Z", "endedAt": "2026-09-27T10:12:00Z",
               "reviews": [{"pass": 1, "id": "review-01-r1", "verdict": "FINDINGS",
                            "report": "reports/r1.md",
                            "startedAt": "2026-09-27T10:00:00Z", "endedAt": "2026-09-27T10:05:00Z"},
                           {"pass": 2, "id": "review-01-r2", "verdict": "CLEAN",
                            "report": "reports/r2.md",
                            "startedAt": "2026-09-27T10:10:00Z", "endedAt": "2026-09-27T10:12:00Z"}],
               "fixes": [{"pass": 1, "id": "fix-01-f1",
                          "startedAt": "2026-09-27T10:06:00Z", "endedAt": "2026-09-27T10:09:00Z"}]},
        "02": {"title": "two", "status": "blocked", "blockedBy": ["01"],
               "cause": {"code": "worker_blocked", "detail": "the worker asks which retry budget applies"},
               "worker": {"id": "item-02", "startedAt": "2026-09-27T10:00:00Z", "endedAt": None},
               "startedAt": "2026-09-27T10:00:00Z", "endedAt": "2026-09-27T10:03:00Z",
               "reviews": [], "fixes": []},
        "03": {"title": "three", "status": "failed", "blockedBy": [],
               "cause": {"code": "dispatch_failed", "detail": "agent start refused: agent_name_taken"},
               "worker": {"id": "item-03"}, "reviews": [], "fixes": []},
        "04": {"title": "four", "status": "todo", "blockedBy": ["02"],
               "worker": {}, "startedAt": None, "endedAt": None, "reviews": [], "fixes": []},
    },
    "ponytail": [{"pass": 1, "id": "ponytail", "verdict": "CLEAN", "report": "reports/p.md",
                  "startedAt": "2026-09-27T10:40:00Z", "endedAt": "2026-09-27T10:41:00Z"}],
}


def fixture():
    return copy.deepcopy(GOOD)


def self_test():
    # `GOOD`'s item 01 is the blind spot the lifecycle decision accepts (threads.md):
    # a record batched past `running` — worker, stamps, reviews and a CLEAN verdict,
    # with no trace of the status it replaced — is indistinguishable from one written
    # as the run moved, so it must read clean. Every harmful variant is refused below.
    assert ledger_errors(fixture()) == [], ledger_errors(fixture())

    def rejects(name, mutate, needle):
        ledger = fixture()
        mutate(ledger)
        found = ledger_errors(ledger)
        assert any(needle in problem for problem in found), (name, found)

    # A status and the fields written beside it must agree.
    rejects("todo with a worker",
            lambda l: l["items"]["04"].update(worker={"id": "item-04"}),
            "a todo item has not been dispatched")
    rejects("running with no worker",
            lambda l: l["items"]["04"].update(status="running", startedAt="2026-09-27T10:00:00Z"),
            "status running with no worker.id")
    rejects("running with an endedAt",
            lambda l: l["items"]["04"].update(status="running", startedAt="2026-09-27T10:00:00Z",
                                              endedAt="2026-09-27T10:01:00Z",
                                              worker={"id": "item-04"}),
            "a settlement with no status")
    rejects("unknown status", lambda l: l["items"]["04"].update(status="settled"),
            "is not one of todo, running, done, failed, blocked")

    # The block vocabulary is closed and paired with the status it belongs to.
    rejects("blocked with no cause",
            lambda l: l["items"]["02"].pop("cause"),
            "with no cause")
    rejects("invented code",
            lambda l: l["items"]["02"]["cause"].update(code="made_up"),
            "is not in the contract")
    rejects("no detail",
            lambda l: l["items"]["02"]["cause"].update(detail="  "),
            "with no detail")
    rejects("two-line detail",
            lambda l: l["items"]["02"]["cause"].update(detail="first\nsecond"),
            "more than one line")
    rejects("cause on a done item",
            lambda l: l["items"]["01"].update(cause={"code": "turn_stalled", "detail": "x"}),
            "blocked or failed only")

    # The two stops whose evidence is in the record itself (review-contract.md).
    rejects("a refutation cause with no refutation recorded",
            lambda l: l["items"]["02"].update(
                cause={"code": "finding_refuted", "detail": "the guard the finding asks for exists"}),
            "with no fix round carrying a refutation")
    rejects("nonconvergent before two findings rounds",
            lambda l: l["items"]["02"].update(
                cause={"code": "nonconvergent", "detail": "the retry cap came back"}),
            "cannot have bounced off each other")
    rejects("a refutation with no quotation",
            lambda l: (l["items"]["01"].update(
                status="blocked",
                cause={"code": "finding_refuted", "detail": "the guard already exists"}),
                l["items"]["01"]["fixes"][0].update(
                    refutation={"finding": "unbounded retry", "evidence": "  "})),
            "a refutation is the quotation")

    # The write that precedes the spawn (threads.md#the-ledger).
    rejects("a dispatch attempt with no label",
            lambda l: l["items"]["04"].update(
                dispatchAttempt={"at": "2026-09-27T09:00:00Z", "role": "worker"}),
            "no label")
    rejects("a dispatch attempt for an invented role",
            lambda l: l["items"]["04"].update(
                dispatchAttempt={"at": "2026-09-27T09:00:00Z", "role": "scout", "label": "x"}),
            "role 'scout' is not one of")
    rejects("a dispatch attempt with a typed stamp",
            lambda l: l["items"]["04"].update(
                dispatchAttempt={"at": "soon", "role": "worker", "label": "x"}),
            "is not an ISO-8601 UTC stamp")

    # The receipt beside the request (threads.md#models).
    rejects("a served model that names nothing",
            lambda l: l.update(served={"worker": "  "}),
            "an unknown receipt is absent")
    rejects("a served model under an invented role",
            lambda l: l.update(served={"scout": "m"}),
            "is not a role")

    # One diagnosis recorded once, however many items the class reached.
    rejects("a class fix with no brief",
            lambda l: l["classFixes"][0].pop("brief"),
            "a reused diagnosis is the point")
    rejects("a class fix that reached no item",
            lambda l: l["classFixes"][0].update(items=[]),
            "a class fix that reached nothing")
    rejects("a class fix naming something that is not an item",
            lambda l: l["classFixes"][0].update(items=["99"]),
            "is not an item")
    rejects("a class fix run by the manager",
            lambda l: l["classFixes"][0].update(id="manager-1"),
            "is an executor")

    # The `done` rule, and the round a FINDINGS verdict says happened.
    rejects("done with no reviews",
            lambda l: l["items"]["01"].update(reviews=[]),
            "status done with no reviews")
    rejects("done on FINDINGS",
            lambda l: l["items"]["01"]["reviews"][1].update(verdict="FINDINGS"),
            "done is a CLEAN review")
    rejects("done with no endedAt",
            lambda l: l["items"]["01"].update(endedAt=None),
            "a settlement is stamped")
    rejects("FINDINGS with no fix round and no cause",
            lambda l: l["items"]["01"].update(
                reviews=[{"pass": 1, "id": "review-01-r1", "verdict": "FINDINGS",
                          "startedAt": "2026-09-27T10:00:00Z", "endedAt": "2026-09-27T10:05:00Z"}],
                fixes=[]),
            "no fix round and no cause")
    rejects("a re-review with no fix before it",
            lambda l: l["items"]["01"].update(fixes=[]),
            "the round it opened is missing")
    rejects("a fourth findings round",
            lambda l: l["items"]["01"].update(
                reviews=[{"pass": n, "id": "review-01-r%d" % n, "verdict": "FINDINGS",
                          "endedAt": "2026-09-27T10:0%d:00Z" % n,
                          "startedAt": "2026-09-27T10:00:00Z"} for n in range(1, 5)],
                fixes=[{"pass": n, "id": "fix-01-f%d" % n,
                        "startedAt": "2026-09-27T10:00:00Z", "endedAt": "2026-09-27T10:01:00Z"}
                       for n in range(1, 5)]),
            "a fourth is never spawned")
    rejects("a fix no review opened",
            lambda l: l["items"]["01"]["fixes"][0].update({"pass": 7}),
            "no review opened this round")
    rejects("a hole in the pass numbers",
            lambda l: l["items"]["01"]["reviews"][1].update({"pass": 3}),
            "one entry per pass, 1..n")
    rejects("a verdict that is neither",
            lambda l: l["items"]["01"]["reviews"][1].update(verdict="MAYBE"),
            "is not CLEAN or FINDINGS")
    rejects("a review lane with no id",
            lambda l: l["items"]["01"]["reviews"][1].pop("id"),
            "a lane no retro can price")
    rejects("a fix lane with no id",
            lambda l: l["items"]["01"]["fixes"][0].pop("id"),
            "a lane no retro can price")
    rejects("a ponytail lane with no id",
            lambda l: l["ponytail"][0].pop("id"),
            "a lane no retro can price")
    rejects("a retro entry with no session",
            lambda l: l.update(retro={"id": "retro-1", "startedAt": "2026-09-27T12:00:00Z"}),
            "a lane no retro can price")
    rejects("a retired executor with no endedAt",
            lambda l: l["executors"].insert(0, {"id": "manager-0", "startedAt": None}),
            "handed over with no endedAt")

    # Who acted: the executor never implements, and a worker does not review itself.
    rejects("the manager implemented the item",
            lambda l: l["items"]["01"]["worker"].update(id="manager-1"),
            "is an executor")
    rejects("the manager reviewed the run",
            lambda l: l["items"]["01"]["reviews"][0].update(id="manager-1"),
            "is an executor")
    rejects("an item reviewed by its own worker",
            lambda l: l["items"]["01"]["reviews"][0].update(id="item-01"),
            "is this item's own worker")
    rejects("the manager ran the ponytail pass",
            lambda l: l["ponytail"][0].update(id="manager-1"),
            "is an executor")

    # Stamps are read, never typed.
    rejects("backwards review",
            lambda l: l["items"]["01"]["reviews"][0].update(startedAt="2026-09-27T10:20:00Z",
                                                            endedAt="2026-09-27T10:19:00Z"),
            "precedes startedAt")
    rejects("a gate approved before it was requested",
            lambda l: l["gates"]["commit"].update(requestedAt="2026-09-27T11:00:00Z",
                                                  approvedAt="2026-09-27T10:59:00Z"),
            "gates.commit")
    rejects("a sentence where a stamp belongs",
            lambda l: l.update(finishedAt="done"),
            "is not an ISO-8601 UTC stamp")
    rejects("finishedAt before the run began",
            lambda l: l.update(finishedAt="2026-09-27T09:00:00Z"),
            "precedes startedAt")

    # A terminal marker must not stand over live work.
    rejects("an item still running under finishedAt",
            lambda l: (l.update(finishedAt="2026-09-27T11:00:00Z"),
                       l["items"]["04"].update(status="running", startedAt="2026-09-27T10:00:00Z",
                                               worker={"id": "item-04"})),
            "under finishedAt")
    rejects("a ponytail pass with no verdict",
            lambda l: (l.update(finishedAt="2026-09-27T11:00:00Z",
                                items={k: v for k, v in l["items"].items()
                                       if v["status"] in ("done", "blocked", "failed")}),
                       l["ponytail"][0].pop("verdict")),
            "no verdict under finishedAt")

    # Drift, not shape: the fields ledger.md names as gone.
    rejects("a stored attempts array",
            lambda l: l["items"]["01"].update(attempts=[{"n": 1}]),
            "drift, not shape")
    rejects("a stored reviewCount",
            lambda l: l["items"]["01"].update(reviewCount=2),
            "drift, not shape")
    rejects("a second copy of the plan gate",
            lambda l: l.update(planGate={"requestedAt": None, "approvedAt": None}),
            "drift, not shape")
    rejects("the old executor field",
            lambda l: l.update(managerChain=["manager-1"]),
            "drift, not shape")

    # What the run must carry for every reader to work.
    rejects("no runtime", lambda l: l.pop("runtime"), "no 'runtime'")
    rejects("no items", lambda l: l.update(items={}), "no 'items'")
    rejects("a list-shaped items", lambda l: l.update(items=[{"id": "01"}]),
            "not an object")
    rejects("a list-shaped gates", lambda l: l.update(gates=["plan", "commit"]),
            "not an object")
    rejects("a blocker that is not an item",
            lambda l: l["items"]["04"].update(blockedBy=["99"]),
            "is not an item")
    rejects("a ponytail FINDINGS with no fix beside it",
            lambda l: l["ponytail"][0].update(verdict="FINDINGS"),
            "FINDINGS with no fix beside it")
    rejects("a finished run whose done item has no ponytail pass",
            lambda l: (l.update(finishedAt="2026-09-27T11:00:00Z", ponytail=[],
                                items={k: v for k, v in l["items"].items()
                                       if v["status"] in ("done", "blocked", "failed")}),
                       l["items"]["01"].update(endedAt="2026-09-27T10:45:00Z"),
                       l["items"]["02"].update(endedAt="2026-09-27T10:45:00Z")),
            "with a done item and no settled ponytail pass")
    rejects("not an object", lambda l: l.update(items={"01": "done"}), "not an object")

    # The mid-run state the ponytail rule must NOT fire on: the lane runs after the
    # items settle, so a done item with no pass yet is ordinary, not a write error.
    mid_run = fixture()
    mid_run["ponytail"] = []
    mid_run["items"] = {"01": mid_run["items"]["01"]}
    assert ledger_errors(mid_run) == [], ledger_errors(mid_run)

    # A refuted round that records its evidence is the valid shape, not a stop the
    # checker distrusts: the round is on the item, so the cause can point at it.
    refuted = fixture()
    refuted["items"]["02"]["cause"] = {
        "code": "finding_refuted",
        "detail": "the finding asks for a guard that already exists at retry.ts:40"}
    refuted["items"]["02"]["reviews"] = [
        {"pass": 1, "id": "review-02-r1", "verdict": "FINDINGS",
         "startedAt": "2026-09-27T10:00:00Z", "endedAt": "2026-09-27T10:05:00Z"}]
    refuted["items"]["02"]["fixes"] = [
        {"pass": 1, "id": "fix-02-f1", "startedAt": "2026-09-27T10:06:00Z",
         "endedAt": "2026-09-27T10:09:00Z",
         "refutation": {"finding": "unbounded retry at retry.ts:12",
                        "evidence": "retry.ts:40 \"for (let i = 0; i < MAX_RETRIES; i++)\""}}]
    assert ledger_errors(refuted) == [], ledger_errors(refuted)

    print("self-test OK")
    return 0


def main(argv):
    if "--self-test" in argv[1:]:
        return self_test()
    if len(argv) != 2:
        print("usage: validate-ledger.py <ledger.json> | --self-test", file=sys.stderr)
        return 2
    try:
        with open(argv[1], encoding="utf-8") as handle:
            ledger = json.load(handle)
    except (OSError, ValueError) as exc:
        print("FAIL: %s" % exc)
        return 1
    problems = ledger_errors(ledger)
    if problems:
        print("FAIL: %d write error(s)" % len(problems))
        for problem in problems:
            print("  " + problem)
        return 1
    print("OK: %d item(s)" % len(ledger.get("items") or {}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
