#!/usr/bin/env bash
# fleet-gate.sh — how a script that starts sessions asks claude/bin/fleet-gate, in one place.
#
# NOT EXECUTABLE ON ITS OWN. It defines one function and returns; the refusal text and the exit stay with each caller, because what "nothing was touched" means differs between them (a promote stops a session first; a sweep may have resumed some already).
#
#   . claude/lib/fleet-gate.sh
#   fleet_gate_check [extra] [wait]   runs the gate; returns its exit code (0 open, non-zero holding) and sets FLEET_GATE_VERDICT to the gate's own line, or to why the gate could not be run.
#
# `wait`, a whole number of seconds above 0, makes it `fleet-gate --wait <wait>`: it polls until the gate opens (0) or the time runs out (2), and says once on stderr that it is waiting. This is how a script that starts a session waits for the gate BEFORE the start, so the wait costs no session slot. A started session never waits on the gate for its own existence: a session that waits after it was started is already counted as live, so a queue of them holds the gate shut while the load is low (2026-10-02: held about 50 minutes at "20 live sessions" with the 5-minute load near 4). Empty or 0 is the one check, as before; anything else holds.
#
# `extra` raises the session limit by that many for this one check. A promote of a LIVE target passes 1: it stops the target and resumes it under a new id, so the live count ends where it began, and without the allowance a promote at exactly the limit would be refused for a session it does not add. A limit that is not a whole number is passed through untouched, so the gate refuses it.
#
# The gate's stdin is /dev/null, as every other claude call in these scripts is, so it cannot eat the heredoc a --all loop reads from.

FLEET_GATE_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" 2>/dev/null && pwd -P)/fleet-gate"

fleet_gate_check() {
  local extra="${1:-0}" wait="${2:-0}" limit="${FLEET_GATE_SESSIONS:-20}"
  FLEET_GATE_VERDICT=""
  case "$wait" in ''|*[!0-9]*) FLEET_GATE_VERDICT="the gate wait is not a whole number of seconds ('$wait'); holding"; return 1 ;; esac
  wait=$((10#$wait))
  if [ ! -r "$FLEET_GATE_BIN" ]; then
    FLEET_GATE_VERDICT="the fleet gate is missing at $FLEET_GATE_BIN, and a gate that cannot be run holds"
    return 1
  fi
  case "$limit" in ''|*[!0-9]*) ;; *) limit=$((10#$limit + extra)) ;; esac
  if [ "$wait" -gt 0 ]; then
    printf 'fleet-gate: waiting up to %s s for the gate before anything is started\n' "$wait" >&2
    FLEET_GATE_VERDICT=$(FLEET_GATE_SESSIONS="$limit" bash "$FLEET_GATE_BIN" --wait "$wait" </dev/null 2>&1)
  else
    FLEET_GATE_VERDICT=$(FLEET_GATE_SESSIONS="$limit" bash "$FLEET_GATE_BIN" </dev/null 2>&1)
  fi
}
