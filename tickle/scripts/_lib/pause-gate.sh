#!/bin/bash
# _lib/pause-gate.sh <job-id>
# Tickle gate: exit 0 if the fleet is NOT paused, exit 1 (skip) if it is.
# Used as a `type: script` trigger so no scheduled job runs while the fleet
# is paused. Compose it with the hostname gate through _lib/gated.sh.
#
# The fleet pause is ruled by 01.65 Operator's console (design rule 10,
# implementation step 8): ONE flag note in the vault is the whole state, and
# every scheduled job runs a gate that reads it. The backup jobs are exempt by
# name — a pause that stops the safety net makes the fleet less safe. Reads
# are never gated; this only stops a job's `run:` command.
#
# Script-trigger exit-code contract (tickle SKILL.md, "Script trigger
# contract", and internal/runner EvaluateScriptTrigger):
#   exit 0  = run the job        (history status "matched")
#   exit 1  = skip the job       (history status "skipped")
#   other   = check failed       (history status "failed"; job does not run)
# A bad argument list therefore exits 2, so a mis-wired trigger is loud in
# `tickle logs` rather than a silent forever-skip.
#
# Usage in a job YAML:
#   triggers:
#     - type: script
#       schedule: "*/30 * * * *"
#       command: ["@config/scripts/_lib/pause-gate.sh", "<job-id>"]
#       timeout: 10s
#
# PAUSE_NOTE overrides the note path, for testing only.
set -u

if [ "$#" -ne 1 ]; then
  echo "usage: pause-gate.sh <job-id>" >&2
  exit 2
fi

job_id="$1"

# NOTE: split into an if-guard rather than PAUSE_NOTE="${PAUSE_NOTE:-...}" on
# one line. bash 3.2 (macOS /bin/bash) mis-parses the literal apostrophe in
# "Operator's" inside a ${VAR:-default} expansion even when double-quoted.
if [ -z "${PAUSE_NOTE:-}" ]; then
  PAUSE_NOTE="$HOME/obsidian/00-09 System/00 System management/00.08 Operator's console/Pause.md"
fi

# The backup jobs are exempt by name (01.65 rule 10) — they run paused or not.
case "$job_id" in
  obsidian-backup|vault-backup) exit 0 ;;
esac

# No note -> no pause -> run.
[ -f "$PAUSE_NOTE" ] || exit 0

fm=$(awk '/^---[ \t]*$/{n++; next} n==1{print} n>=2{exit}' "$PAUSE_NOTE")

fm_value() {
  printf '%s\n' "$fm" \
    | grep -E "^$1:" \
    | head -1 \
    | sed -E "s/^$1:[[:space:]]*//" \
    | sed -E 's/^"(.*)"$/\1/' \
    | sed -E "s/[[:space:]]+$//"
}

paused=$(fm_value paused | tr -d '[:space:]')

# Not paused, or the key is absent or malformed -> run. Only a literal true
# stops a job, so a half-written note can never wedge the fleet shut.
[ "$paused" = "true" ] || exit 0

by=$(fm_value paused-by)
since=$(fm_value paused-since)
why=$(fm_value paused-why)
[ -n "$by" ] || by="(unset)"
[ -n "$since" ] || since="(unset)"
[ -n "$why" ] || why="(unset)"

echo "[pause-gate] fleet paused — skipping '$job_id' (note: $PAUSE_NOTE; paused-by: $by; paused-since: $since; paused-why: $why)" >&2
exit 1
