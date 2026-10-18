#!/usr/bin/env python3
"""The machine copies of the contracts' constants, shared by the runtime scripts.

The cause vocabulary is owned by `../cause-contract.md`, and the item lifecycle
by `../threads.md`. This module is their single machine copy: the checker and both retro scripts
import it instead of defining the set three times, so a change to the vocabulary
is a change here and in the contract, and nowhere else. `ledger_errors` is the ledger write-error checker — `validate-ledger.py`
is its command line, and both runtimes run it after every ledger write — and
`stamp` and `ponytail_passes` are the shape readers the Herdr retro prices a lane
from.

    python3 orchestrate_common.py --self-test
"""

import datetime
import os
import re

CAUSE_CODES = frozenset((
    "worker_blocked", "turn_stalled", "artifact_unchanged", "finding_refuted",
    "nonconvergent", "cap_exhausted", "spec_conflict", "model_unavailable",
    "dispatch_failed", "unclassified",
))

# The roles a dispatch can be for (ledger.md's `dispatchAttempt`), and the two
# stops whose evidence the contract says is in the record itself.
DISPATCH_ROLES = ("worker", "review", "fix", "ponytail")
EVIDENCED_CAUSES = ("finding_refuted", "nonconvergent")

STATUSES = ("todo", "running", "done", "failed", "blocked")
TERMINAL_STATUSES = ("done", "failed", "blocked")
CAUSED_STATUSES = ("blocked", "failed")
VERDICT_PREFIXES = ("CLEAN", "FINDINGS")
CAP = 3  # findings rounds per item — review-contract.md
REQUIRED_RUN_FIELDS = ("runtime", "feature", "flow", "mode", "startedAt", "executors", "items")
# Fields ledger.md names as gone: a reader cannot tell which of two copies it
# holds, so their presence is drift and not shape.
LEGACY_RUN_FIELDS = ("planGate", "managerChain")
LEGACY_ITEM_FIELDS = ("reviewCount", "reviewThreadId", "fixRounds", "attempts")

CONTRACT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "cause-contract.md")


def contract_codes(path=CONTRACT):
    """The codes named by the contract's markdown table."""
    codes = set()
    row = re.compile(r"^\|\s*`([a-z_]+)`\s*\|")
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            match = row.match(line)
            if match:
                codes.add(match.group(1))
    return frozenset(codes)


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", str(text or "").lower()).strip("-")


def corpus_dirname(date, runtime, project, feature):
    """`<date>-<runtime>-<project>-<feature>`: the one corpus directory name."""
    parts = [slug(date), slug(runtime), slug(project), slug(feature)]
    return "-".join(p for p in parts if p) or "run"


def stamp(value):
    """Normalize one ISO-8601 timestamp, or None when absent/unusable."""
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed.astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def ponytail_passes(ledger):
    """The ponytail passes in order.

    The schema's `ponytail` is a **list** of passes; an older ledger holds one
    mapping instead. Both are read here, because a reader that crashes on the
    shape the skill writes takes its whole view down with it.
    """
    passes = (ledger or {}).get("ponytail") or []
    if isinstance(passes, dict):
        passes = [passes]
    return [entry for entry in passes if isinstance(entry, dict) and entry.get("id")]


def _verdict_kind(value):
    """'CLEAN', 'FINDINGS', or None when the verdict is not one of the two."""
    word = str(value or "").upper()
    for prefix in VERDICT_PREFIXES:
        if word.startswith(prefix):
            return prefix
    return None


def ledger_errors(ledger):
    """The ledger write errors provable from the ledger alone.

    `../threads.md#the-item-lifecycle` owns the transitions; this is the half of
    them a single snapshot can prove. A transition's *legality* cannot be read
    from one file — the previous status is gone — so a row is caught by what the
    state fails to carry: a status and the fields written beside it disagreeing
    (a `todo` with a worker, a `running` with an `endedAt`), a stamp typed
    instead of read, a `done` with no clean review, a terminal marker standing
    over live work, a cause outside the contract's closed set.

    The blind spot that leaves is deliberate, and threads.md's *The item
    lifecycle* says why it is not closed with a history check or an event log.

    These are errors and not warnings, because each one is a coordinator write
    mistake and the coordinator runs this after every write, so it sees the
    mistake while it still knows what it meant. The retro reads the transcripts
    and owns the rest (an interval outside its own agent's session window).
    Membership of `flow`/`mode` is `validate-manifest.py`'s — the ledger only
    copies those fields.
    """
    if not isinstance(ledger, dict):
        return ["ledger: not a JSON object"]
    problems = []

    for field in REQUIRED_RUN_FIELDS:
        if not ledger.get(field):
            problems.append("run: no %r — the ledger must read true mid-run" % field)
    for field in LEGACY_RUN_FIELDS:
        if field in ledger:
            problems.append("run: %r is drift, not shape (ledger.md)" % field)

    def typed(value, where):
        if value and not stamp(value):
            problems.append("%s: %r is not an ISO-8601 UTC stamp (YYYY-MM-DDTHH:MM:SSZ)"
                            % (where, value))

    def backwards(start, end, where):
        begun, done = stamp(start), stamp(end)
        if begun and done and done < begun:
            problems.append("%s: endedAt %s precedes startedAt %s" % (where, end, start))

    def as_object(value, where):
        """A mapping field, reported rather than crashed on.

        A pre-shape ledger holds `items` or `gates` as a list. Every reader here
        keys them by name, and one that meets a list stops reading the whole
        record — bb's normalise_items tolerates it, so this does too.
        """
        if not value:
            return {}
        if not isinstance(value, dict):
            problems.append("%s: %s, not an object — a reader that meets a list here stops "
                            "reading the record" % (where, type(value).__name__))
            return {}
        return value

    def rounds(entries, where, verdicts=False, ids=False):
        """Pass numbers are 1..n, every verdict is CLEAN or FINDINGS, and every
        entry in a lane a reader prices carries the id it is priced by."""
        passes = []
        for entry in entries or []:
            if not isinstance(entry, dict):
                problems.append("%s: not an object" % where)
                continue
            passes.append(entry.get("pass"))
            if not entry.get("id") and (ids or _verdict_kind(entry.get("verdict"))):
                if entry.get("verdict"):
                    problems.append("%s[pass %s]: verdict %s with no id — a lane no retro can price"
                                    % (where, entry.get("pass"), entry.get("verdict")))
                else:
                    problems.append("%s[pass %s]: no id — a lane no retro can price"
                                    % (where, entry.get("pass")))
            if verdicts:
                kind = _verdict_kind(entry.get("verdict"))
                if entry.get("verdict") and not kind:
                    problems.append("%s[pass %s]: verdict %r is not CLEAN or FINDINGS"
                                    % (where, entry.get("pass"), entry.get("verdict")))
                if entry.get("verdict") and not entry.get("endedAt"):
                    problems.append("%s[pass %s]: verdict %s with no endedAt"
                                    % (where, entry.get("pass"), entry.get("verdict")))
                backwards(entry.get("startedAt"), entry.get("endedAt"),
                          "%s[pass %s]" % (where, entry.get("pass")))
        if passes and sorted(passes) != list(range(1, len(passes) + 1)):
            problems.append("%s: pass numbers are %s — one entry per pass, 1..n"
                            % (where, passes))
        return passes

    typed(ledger.get("startedAt"), "run.startedAt")
    typed(ledger.get("finishedAt"), "run.finishedAt")

    # `served` is the receipt beside `models`' request (threads.md#models). A role
    # whose record named no model is absent and reads as unverified; a present one
    # that names nothing is the write error.
    served = as_object(ledger.get("served"), "run.served")
    for role, model in served.items():
        if role not in ("worker", "code-review", "ponytail"):
            problems.append("run.served: %r is not a role" % role)
        if not isinstance(model, str) or not model.strip():
            problems.append("run.served.%s: %r is not a model — an unknown receipt is absent, "
                            "not empty (threads.md#models)" % (role, model))

    finished = stamp(ledger.get("finishedAt"))
    if finished and stamp(ledger.get("startedAt")) and finished < stamp(ledger.get("startedAt")):
        problems.append("run: finishedAt %s precedes startedAt %s"
                        % (ledger["finishedAt"], ledger["startedAt"]))

    # WHO acted is checkable, and it is the half of "the coordinator never implements
    # items itself" and "a worker reviewing its own work does not count" that a
    # single snapshot can hold (threads.md#rules).
    executors = [e for e in (ledger.get("executors") or []) if isinstance(e, dict)]
    executor_ids = {e["id"] for e in executors if e.get("id")}

    # One entry per diagnosis, however many items the class reached
    # (review-contract.md). A class fix with no lane is a diagnosis no retro can
    # price, and a class fix naming no item is a class no reader can check.
    for index, fix in enumerate(ledger.get("classFixes") or []):
        where = "classFixes[%d]" % index
        if not isinstance(fix, dict):
            problems.append("%s: not an object" % where)
            continue
        if not str(fix.get("class") or "").strip():
            problems.append("%s: no class — the slug is what a later finding matches" % where)
        if not str(fix.get("brief") or "").strip():
            problems.append("%s: no brief — a reused diagnosis is the point of the entry" % where)
        if not fix.get("id"):
            problems.append("%s: no id — a lane no retro can price" % where)
        elif fix["id"] in executor_ids:
            problems.append("%s: %r is the coordinator — the coordinator never repairs the classes its own "
                            "run produced (threads.md#rules)" % (where, fix["id"]))
        typed(fix.get("startedAt"), where + ".startedAt")
        typed(fix.get("endedAt"), where + ".endedAt")
        backwards(fix.get("startedAt"), fix.get("endedAt"), where)
        if not fix.get("items"):
            problems.append("%s: no items — a class fix that reached nothing" % where)
        known_items = ledger.get("items") if isinstance(ledger.get("items"), dict) else {}
        for member in fix.get("items") or []:
            if str(member) not in {str(i) for i in known_items}:
                problems.append("%s.items: %s is not an item" % (where, member))
    # A retired coordinator — one that handed over to a successor — has ended by
    # definition. The last one may not have: threads.md lets the manager finish its
    # own handover acts after `finishedAt`, so a snapshot cannot tell a live
    # coordinator from one at rest. This check stops at the retiree for that reason.
    for index, executor in enumerate(executors[:-1]):
        if not executor.get("endedAt"):
            problems.append("executors[%d]: %r handed over with no endedAt"
                            % (index, executor.get("id")))
    retro = ledger.get("retro")
    if isinstance(retro, dict) and not retro.get("session"):
        problems.append("retro: %r with no session — a lane no retro can price (ledger.md)"
                        % retro.get("id"))

    items = as_object(ledger.get("items"), "run.items")
    for item_id, item in items.items():
        where = "items[%s]" % item_id
        if not isinstance(item, dict):
            problems.append("%s: not an object" % where)
            continue
        for field in LEGACY_ITEM_FIELDS:
            if field in item:
                problems.append("%s.%s is drift, not shape (ledger.md)" % (where, field))
        status = item.get("status")
        if status not in STATUSES:
            problems.append("%s: status %r is not one of %s" % (where, status, ", ".join(STATUSES)))
        typed(item.get("startedAt"), where + ".startedAt")
        typed(item.get("endedAt"), where + ".endedAt")
        backwards(item.get("startedAt"), (item.get("worker") or {}).get("endedAt"),
                  where + ".worker")
        worker_id = (item.get("worker") or {}).get("id")
        if worker_id and worker_id in executor_ids:
            problems.append("%s.worker.id: %r is the coordinator — the coordinator dispatches and never "
                            "implements items itself (threads.md#rules)" % (where, worker_id))

        # The write that precedes the spawn, so a resume can find the lane
        # (threads.md#the-ledger). Its shape is all one snapshot can prove.
        attempt = item.get("dispatchAttempt")
        if attempt is not None:
            if not isinstance(attempt, dict):
                problems.append("%s.dispatchAttempt: not an object" % where)
            else:
                typed(attempt.get("at"), where + ".dispatchAttempt.at")
                if not attempt.get("at"):
                    problems.append("%s.dispatchAttempt: no at — the write precedes the spawn, so "
                                    "its time is the point" % where)
                if attempt.get("role") not in DISPATCH_ROLES:
                    problems.append("%s.dispatchAttempt: role %r is not one of %s"
                                    % (where, attempt.get("role"), ", ".join(DISPATCH_ROLES)))
                if not str(attempt.get("label") or "").strip():
                    problems.append("%s.dispatchAttempt: no label — the label is how a resume "
                                    "finds the lane" % where)

        # The state and the fields written beside it must agree: each disagreement
        # is a transition that left no trace in `status`.
        if status == "todo":
            for field in ("worker", "startedAt", "endedAt", "reviews", "fixes"):
                if item.get(field):
                    problems.append("%s: status todo with %s written — a todo item has not "
                                    "been dispatched" % (where, field))
        if status == "running":
            if not (item.get("worker") or {}).get("id"):
                problems.append("%s: status running with no worker.id" % where)
            if not item.get("startedAt"):
                problems.append("%s: status running with no startedAt" % where)
            if item.get("endedAt"):
                problems.append("%s: status running with endedAt %s — a settlement with no "
                                "status" % (where, item["endedAt"]))

        # An item the run stopped on is typed: a `blocked`/`failed` item carries a
        # `cause` from the contract's closed set, and nothing else carries one.
        cause = item.get("cause")
        cause_code = cause.get("code") if isinstance(cause, dict) else None
        if status in CAUSED_STATUSES:
            if not isinstance(cause, dict) or not cause.get("code"):
                problems.append("%s: status %r with no cause (cause-contract.md)"
                                % (where, status))
            else:
                if cause["code"] not in CAUSE_CODES:
                    problems.append("%s.cause: code %r is not in the contract"
                                    % (where, cause["code"]))
                if not str(cause.get("detail") or "").strip():
                    problems.append("%s.cause: %s with no detail" % (where, cause["code"]))
                elif "\n" in str(cause["detail"]):
                    problems.append("%s.cause: %s detail is more than one line"
                                    % (where, cause["code"]))
        elif cause:
            problems.append("%s: cause on a %r item — a cause is for blocked or failed only"
                            % (where, status))

        review_passes = rounds(item.get("reviews"), where + ".reviews", verdicts=True, ids=True)
        fix_passes = rounds(item.get("fixes"), where + ".fixes", ids=True)
        for review in item.get("reviews") or []:
            if not isinstance(review, dict) or not review.get("id"):
                continue
            review_id = review["id"]
            if review_id in executor_ids:
                problems.append("%s.reviews[pass %s]: %r is the coordinator — the coordinator never "
                                "reviews the run it executes (threads.md#rules)"
                                % (where, review.get("pass"), review_id))
            elif worker_id and review_id == worker_id:
                problems.append("%s.reviews[pass %s]: %r is this item's own worker — a worker "
                                "reviewing its own work is not a review (threads.md#rules)"
                                % (where, review.get("pass"), review_id))
        for fix_pass in fix_passes:
            if fix_pass not in review_passes:
                problems.append("%s.fixes[pass %s]: no review opened this round" % (where, fix_pass))
        # A refutation is recorded on the round that made it, and it is what the
        # stop names (review-contract.md). Neither is provable from the cause alone.
        refuted = any(isinstance(fix, dict) and isinstance(fix.get("refutation"), dict)
                      for fix in item.get("fixes") or [])
        for fix in item.get("fixes") or []:
            refutation = (fix or {}).get("refutation") if isinstance(fix, dict) else None
            if refutation is None:
                continue
            if not isinstance(refutation, dict):
                problems.append("%s.fixes[pass %s].refutation: not an object"
                                % (where, (fix or {}).get("pass")))
                continue
            for field in ("finding", "evidence"):
                if not str(refutation.get(field) or "").strip():
                    problems.append("%s.fixes[pass %s].refutation: no %s — a refutation is the "
                                    "quotation that disproves the finding"
                                    % (where, (fix or {}).get("pass"), field))
        if cause_code in ("finding_refuted",) and not refuted:
            problems.append("%s: cause finding_refuted with no fix round carrying a refutation "
                            "(review-contract.md)" % where)
        if cause_code == "nonconvergent" and len(fix_passes) < 2:
            problems.append("%s: cause nonconvergent with %d findings round(s) — the rounds "
                            "cannot have bounced off each other" % (where, len(fix_passes)))
        # Cap: the findings rounds are the ones that opened a fix, and a fourth is
        # never spawned.
        if len(fix_passes) > CAP:
            problems.append("%s: %d findings rounds — the cap is %d, a fourth is never spawned "
                            "(review-contract.md)" % (where, len(fix_passes), CAP))
        for index, review in enumerate(item.get("reviews") or []):
            kind = _verdict_kind((review or {}).get("verdict"))
            if kind != "FINDINGS":
                continue
            later = index < len(item.get("reviews") or []) - 1
            opened = (review or {}).get("pass") in fix_passes
            if later and not opened:
                problems.append("%s.reviews[pass %s]: FINDINGS with no fix round, and the next "
                                "review ran — the round it opened is missing"
                                % (where, (review or {}).get("pass")))
            elif not later and not opened and status not in CAUSED_STATUSES:
                problems.append("%s.reviews[pass %s]: FINDINGS with no fix round and no cause — "
                                "write the round this verdict opened, or record the stop that "
                                "ended the item" % (where, (review or {}).get("pass")))

        # `done` is the review's CLEAN and the ponytail's settle — threads.md.
        if status == "done":
            reviews = item.get("reviews") or []
            if not reviews:
                problems.append("%s: status done with no reviews" % where)
            elif _verdict_kind((reviews[-1] or {}).get("verdict")) != "CLEAN":
                problems.append("%s: status done on a last verdict of %r — done is a CLEAN review"
                                % (where, (reviews[-1] or {}).get("verdict")))
            if not item.get("endedAt"):
                problems.append("%s: status done with no endedAt — a settlement is stamped" % where)
        if finished and status not in TERMINAL_STATUSES:
            problems.append("%s: status %r under finishedAt %s"
                            % (where, status, finished))
        if finished and stamp(item.get("endedAt")) and finished < stamp(item.get("endedAt")):
            problems.append("%s: endedAt %s after finishedAt %s — a terminal marker standing "
                            "over a later write" % (where, item["endedAt"], finished))

    for item_id, item in items.items():
        if not isinstance(item, dict):
            continue
        for blocker in item.get("blockedBy") or []:
            if str(blocker) not in {str(i) for i in items}:
                problems.append("items[%s].blockedBy: %s is not an item" % (item_id, blocker))

    passes = ledger.get("ponytail") or []
    if isinstance(passes, dict):  # a pre-list ledger holds one mapping
        passes = [passes]
    settled_ponytail = any(_verdict_kind((p or {}).get("verdict")) for p in passes if isinstance(p, dict))
    for pass_ in passes:
        if not isinstance(pass_, dict):
            problems.append("ponytail: not an object")
            continue
        where = "ponytail[pass %s]" % pass_.get("pass")
        if not pass_.get("id"):
            problems.append("%s: no id — a lane no retro can price" % where)
        elif pass_["id"] in executor_ids:
            problems.append("%s: %r is the coordinator — the coordinator never runs the pass that "
                            "checks its own run" % (where, pass_["id"]))
        backwards(pass_.get("startedAt"), pass_.get("endedAt"), where)
        if pass_.get("verdict") and not pass_.get("endedAt"):
            problems.append("%s: verdict %s with no endedAt" % (where, pass_["verdict"]))
        if pass_.get("verdict") and not _verdict_kind(pass_["verdict"]):
            problems.append("%s: verdict %r is not CLEAN or FINDINGS" % (where, pass_["verdict"]))
        if _verdict_kind(pass_.get("verdict")) == "FINDINGS" and not (pass_.get("fix") or {}).get("id"):
            problems.append("%s: FINDINGS with no fix beside it — write the round this verdict "
                            "opened, or record the stop that ended it" % where)
        if finished and not pass_.get("verdict"):
            problems.append("%s: no verdict under finishedAt %s" % (where, finished))
        fix = pass_.get("fix") or {}
        backwards(fix.get("startedAt"), fix.get("endedAt"), where + ".fix")
        review = fix.get("review") or {}
        backwards(review.get("startedAt"), review.get("endedAt"), where + ".fix.review")
        if finished and (review.get("id") or review.get("session")) and not review.get("verdict"):
            problems.append("%s.fix.review: a review with no verdict under finishedAt %s"
                            % (where, finished))
    # The other half of the `done` rule, checked where it is provable: the ponytail
    # lane runs after the items settle, so a done item with no pass yet is an
    # ordinary mid-run state, and only a finished run contradicts itself. Which
    # pass read which item is not in the ledger's shape, so this is as far as one
    # snapshot can hold the two together.
    if finished and not settled_ponytail \
            and any(isinstance(item, dict) and item.get("status") == "done"
                    for item in items.values()):
        problems.append("run: finishedAt %s with a done item and no settled ponytail pass — an "
                        "item is done on a clean review AND a settled ponytail (threads.md)"
                        % finished)

    for name, gate in as_object(ledger.get("gates"), "run.gates").items():
        if isinstance(gate, dict):
            backwards(gate.get("requestedAt"), gate.get("approvedAt"), "gates.%s" % name)
    return problems


def self_test():
    codes = contract_codes()
    assert codes, "no codes read from %s" % CONTRACT
    assert codes == CAUSE_CODES, "contract and CAUSE_CODES disagree: %s" % sorted(codes ^ CAUSE_CODES)
    assert corpus_dirname("2026-01-01", "bb", "P", "F") == "2026-01-01-bb-p-f"
    assert corpus_dirname(None, None, None, None) == "run"
    assert stamp("2026-01-01T00:00:00Z") == "2026-01-01T00:00:00Z"
    assert stamp("done") is None and stamp(None) is None and stamp("") is None
    assert _verdict_kind("CLEAN") == "CLEAN" and _verdict_kind("findings") == "FINDINGS"
    assert _verdict_kind("MAYBE") is None and _verdict_kind(None) is None
    # A lane is read from either shape, and junk entries are skipped, not fatal.
    assert ponytail_passes({"ponytail": []}) == []
    assert ponytail_passes({}) == []
    assert [p["id"] for p in ponytail_passes({"ponytail": {"id": "p1"}})] == ["p1"]
    assert [p["id"] for p in ponytail_passes(
        {"ponytail": [{"id": "p1"}, {"id": None}, "junk", None]})] == ["p1"]


if __name__ == "__main__":
    self_test()
    print("self-test OK")
