<!-- Part of /orchestrate-herdr-threads. Load it at the first settle and again when a turn stalls; `../SKILL.md` owns the order. -->

# Waiting

`herdr agent wait` fires on a **transition**, not on the current state, so a
worker that settled while nobody was looking is invisible to it. Check first,
then wait — and treat every wait timeout as a checkpoint, not a failure:

```sh
# the lane's heartbeat: the pi session transcript recorded when the agent started
sess_of() { jq -r --arg id "$1" \
  '[.items[].worker, .items[].reviews[], .items[].fixes[], .ponytail[], .ponytail[].fix,
    .ponytail[].fix.review] | .[]? | select(.id == $id) | .session' \
  "$RUNDIR/orchestration.json" | head -1; }

# settle <agent-name>: loop until the turn is over, or until the agent is unreadable
while :; do
  st=$(herdr agent get "<name>" 2>/dev/null | jq -r '.result.agent.agent_status // empty')
  case "$st" in idle|done|blocked|"") break;; esac   # "" = no agent left: inspect, never assume
  # liveness: an open turn that has written nothing for STALE_GAP_SEC is a candidate, not a verdict
  sess=$(sess_of "<name>")
  age=$(( $(date +%s) - $(python3 -c 'import os,sys;print(int(os.stat(sys.argv[1]).st_mtime))' \
    "${sess:-/dev/null}" 2>/dev/null || date +%s) ))
  [ -n "$sess" ] && [ "$age" -gt 900 ] && \
    herdr agent read "<name>" --source recent-unwrapped --lines 60   # confirm before acting
  herdr agent wait "<name>" --until idle --until done --until blocked --timeout 600000 \
    > "$RUNDIR/logs/wait-<name>.json" 2>&1 || true
done
```

The transcript's mtime is the lane's heartbeat: an open turn that has written
nothing for longer than `STALE_GAP_SEC` (900s) is a **stale candidate**. Confirm
it with `agent read` — a tool call longer than the gap writes nothing until it
returns, so a long test run is the expected false positive — and only then apply
the stalled-turn recovery below. This is
[`threads.md#liveness`](../../orchestrate-core/threads.md#liveness)'s rule, not a
second one.

**A finished pi turn reports `idle` or `done` — treat both alike.** Herdr returns
`agent_status: "done"` for a pi agent whose turn ended (14 of 14 wait logs in the
run that produced this line) and `idle` for one caught between turns; a
coordinator that expected only `idle` would read every settle as an agent exit.
Break on `idle`, `done`, `blocked` and the empty status alike, and include both
`idle` and `done` in the `--until` list. Whichever arrives is a settle
**candidate**, not proof: the agent's report file on disk is what settles it.

A wave dispatches in parallel and settles in parallel — one shell block each:

```sh
for id in <id1> <id2>; do
  herdr agent prompt "item-$id" "$(cat "$RUNDIR/prompts/item-$id.txt")" \
    > "$RUNDIR/logs/prompt-item-$id.json" 2>&1 &
done
wait                       # prompts are in their panes; the status each leaves is read next
# settle-wait the wave with the loop above in parallel; freeze each diff as it settles
for id in <id1> <id2>; do
  ( while :; do
      st=$(herdr agent get "item-$id" 2>/dev/null | jq -r '.result.agent.agent_status // empty')
      case "$st" in idle|done|blocked|"") break;; esac
      sess=$(sess_of "item-$id")
      age=$(( $(date +%s) - $(python3 -c 'import os,sys;print(int(os.stat(sys.argv[1]).st_mtime))' \
        "${sess:-/dev/null}" 2>/dev/null || date +%s) ))
      [ -n "$sess" ] && [ "$age" -gt 900 ] && \
        herdr agent read "item-$id" --source recent-unwrapped --lines 60
      herdr agent wait "item-$id" --until idle --until done --until blocked --timeout 600000 >/dev/null 2>&1 || true
    done ) &
done
wait
```

**A prompt's exit code is not a delivery report.** `--wait --timeout <ms>` says
whether the agent's status became readable inside that window and nothing more:
`{"error":{"code":"timeout"}}` from a prompt whose agent is working is the normal
outcome of a short window, not a lost prompt. Never re-prompt on that code alone —
`herdr agent get` and `herdr agent read` say whether the text arrived, and a
genuinely unprompted agent is re-prompted only after that read. The log is for the
case where the prompt never landed at all.

**Wake on the first settle, not the last.** A block that ends in `wait` hands back
control only when the slowest agent in it is done, so a worker that settled two
minutes in keeps its review waiting for as long as its sibling runs — the run pays
for the slowest agent twice, once in work and once in the wait. Settle each agent
in its own bounded call, or wake on the first (`wait -n`), and do its work the
moment it settles: freeze that diff, dispatch that review, then go back to waiting
for the rest. Keep the settle loop's budget short and *below* the timeout that
wraps the call — a 1500s budget inside a 1600s bash timeout reports neither, and
the turn is gone for 26 minutes.

**A stalled turn is not a settle.** `idle` — or a `wait` timeout — with no report
file on disk means the turn died mid-work, not that the agent finished: read the
pane (`herdr agent read "<name>" --source recent-unwrapped --lines 60`) and, if
the turn ended without a report, re-prompt **that same agent** once with
`continue` — never the whole prompt again. A second stall is a blocker: record
it with `cause.code: turn_stalled`, notify the operator, and keep the rest of the
frontier moving. A turn that ended mid-generation is invisible in every status
field the run reads, so this
check is the only thing that catches it.

**Reading and releasing.** The report file is the truth; the scrollback tail is
the summary: `head -1` the report for a verdict, then
`herdr agent read "<name>" --source recent-unwrapped --lines 60` for the final
message. A **review, fix or ponytail** tab is released —
`herdr tab close "$tab"` — once its settlement is recorded; that recording is
what makes the close safe. A **worker** tab is retained until the run's cleanup,
so a fix round re-prompts the same agent instead of respawning it. Release only
tabs this coordinator created, and never close one before its verdict or report
is on disk. Retention is the other safe choice, and it is *required* while a loop
can still re-open the tab — a reviewer whose completion carried no verdict, a turn
that stalled and needs `continue`, a ponytail pass awaiting a fix round: keep that
tab until the loop is closed, then release it.

**Respawn into the same pane.** When an agent has exited and its item needs
another turn, restart it in the pane recorded in the ledger — the tab keeps its
label and position, and the freed name is reused:

```sh
herdr agent start "item-<slug>" --kind pi --pane "<recorded pane>" \
  > "$RUNDIR/logs/start-item-<slug>-f<n>.json"
```

**Blocked dialog.** `blocked` is a user-facing gate. Inspect `agent get` and
`agent read`, then: if the approved manifest answers the question exactly, answer
it in the pane (`herdr pane send-text "<pane>" "<answer>"`, then
`herdr pane send-keys "<pane>" Enter`) and confirm the worker resumes working;
otherwise record the blocker with `cause.code: worker_blocked`, notify the
operator, and end the turn. The
coordinator never guesses an answer and never leaves a blocked worker unwatched.

**Escalation round-trip.** A worker that reports `ESCALATE:` has stopped on one
question ([`threads.md#escalation`](../../orchestrate-core/threads.md#escalation)).
Answer it from the approved manifest when the manifest answers — prompt the
**same** agent with the answer (`herdr agent prompt "<name>" "<answer>"`) and the
item stays `running`. When it does not: in `gated`, put that one question to the
operator with `AskUserQuestion`, the worker's options as its choices, and on the
reply prompt that same agent; the
item returns to `running` and its `cause` is cleared. In `land` and `unattended`
there is no human, so record `cause.code: worker_blocked` (its `detail` is the
question), surface it, and keep the frontier moving. Never respawn a worker to
answer a question its own context already holds.

