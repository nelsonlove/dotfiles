#!/usr/bin/env bash
# fleet-gate.sh — how a script that starts sessions asks claude/bin/fleet-gate, in one place.
#
# NOT EXECUTABLE ON ITS OWN. It defines one function and returns; the refusal text and the exit stay with each caller, because what "nothing was touched" means differs between them (a promote stops a session first; a sweep may have resumed some already).
#
#   . claude/lib/fleet-gate.sh
#   fleet_gate_check [extra]   runs the gate; returns its exit code (0 open, non-zero holding) and sets FLEET_GATE_VERDICT to the gate's own line, or to why the gate could not be run.
#
# `extra` raises the session limit by that many for this one check. A promote of a LIVE target passes 1: it stops the target and resumes it under a new id, so the live count ends where it began, and without the allowance a promote at exactly the limit would be refused for a session it does not add. A limit that is not a whole number is passed through untouched, so the gate refuses it.
#
# The gate's stdin is /dev/null, as every other claude call in these scripts is, so it cannot eat the heredoc a --all loop reads from.

FLEET_GATE_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" 2>/dev/null && pwd -P)/fleet-gate"

fleet_gate_check() {
  local extra="${1:-0}" limit="${FLEET_GATE_SESSIONS:-20}"
  FLEET_GATE_VERDICT=""
  if [ ! -r "$FLEET_GATE_BIN" ]; then
    FLEET_GATE_VERDICT="the fleet gate is missing at $FLEET_GATE_BIN, and a gate that cannot be run holds"
    return 1
  fi
  case "$limit" in ''|*[!0-9]*) ;; *) limit=$((10#$limit + extra)) ;; esac
  FLEET_GATE_VERDICT=$(FLEET_GATE_SESSIONS="$limit" bash "$FLEET_GATE_BIN" </dev/null 2>&1)
}
