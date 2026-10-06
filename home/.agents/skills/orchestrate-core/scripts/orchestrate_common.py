#!/usr/bin/env python3
"""The machine copies of the contracts' constants, shared by the runtime scripts.

The cause vocabulary is owned by `../cause-contract.md`. This module is its
single machine copy: both retro scripts and the Herdr ledger projection import
it instead of defining the set three times, so a change to the vocabulary is a
change here and in the contract, and nowhere else.

    python3 orchestrate_common.py --self-test
"""

import os
import re

CAUSE_CODES = frozenset((
    "worker_blocked", "turn_stalled", "artifact_unchanged", "cap_exhausted",
    "spec_conflict", "model_unavailable", "dispatch_failed", "unclassified",
))

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


def self_test():
    codes = contract_codes()
    assert codes, "no codes read from %s" % CONTRACT
    assert codes == CAUSE_CODES, "contract and CAUSE_CODES disagree: %s" % sorted(codes ^ CAUSE_CODES)
    assert corpus_dirname("2026-01-01", "bb", "P", "F") == "2026-01-01-bb-p-f"
    assert corpus_dirname(None, None, None, None) == "run"


if __name__ == "__main__":
    self_test()
    print("self-test OK")
