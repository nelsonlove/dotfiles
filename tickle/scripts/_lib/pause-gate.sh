#!/bin/bash
# _lib/pause-gate.sh <job-id>
# Tickle gate: exit 0 if the fleet is NOT paused, exit 1 (skip) if it is,
# exit 2 (check failed) if the pause flag cannot be read or understood.
# Used as a `type: script` trigger so no scheduled job runs while the fleet
# is paused. Compose it with the hostname gate through _lib/gated.sh.
#
# The fleet pause is ruled by 01.65 Operator's console (design rule 10,
# implementation step 8): ONE flag note in the vault is the whole state, and
# every scheduled job runs a gate that reads it. The backup jobs are exempt by
# name — a pause that stops the safety net makes the fleet less safe. Reads
# are never gated; this only stops a job's `run:` command.
#
# FAILS CLOSED. A pause is a human saying stop, so "I could not tell" must
# never mean "carry on". Only two states let a job run: the note is absent,
# or the note parsed and says not paused. An unreadable note, a note with no
# frontmatter block, a missing or unrecognised `paused` value, and any
# unexpected shell failure all exit 2, which tickle records as `failed` and
# which does NOT run the job.
#
# Script-trigger exit-code contract (tickle SKILL.md, "Script trigger
# contract", and internal/runner EvaluateScriptTrigger):
#   exit 0  = run the job        (history status "matched")
#   exit 1  = skip the job       (history status "skipped")
#   other   = check failed       (history status "failed"; job does not run)
# Exit 1 is reachable ONLY from the deliberate "paused" path below. Every
# other non-zero exit is rewritten to 2 by the EXIT trap, because a stray 1 —
# `set -u` on an unbound variable exits 1 — would be an invisible permanent
# skip, indistinguishable from a healthy quiet period. That is the same class
# of silent failure that hid a 29-hour obsidian-backup outage (see on-host.sh).
#
# Usage in a job YAML:
#   triggers:
#     - type: script
#       schedule: "*/30 * * * *"
#       command: ["@config/scripts/_lib/pause-gate.sh", "<job-id>"]
#       timeout: 10s
#
# PAUSE_NOTE overrides the note path, for testing only.
#
# The flag parser below is duplicated verbatim in claude/hooks/pause-guard.sh,
# the session-side half of the same rule. The two install through different
# paths (TICKLE_CONFIG_HOME here, the ~/.claude/hooks symlink there) and must
# never disagree about what "paused" means: change both together.
set -u

# Rewrite every unexpected exit to 2. Only the deliberate skip keeps 1.
pause_gate_skip=0
on_exit() {
  exit_rc=$?
  [ "$exit_rc" -eq 0 ] && exit 0
  if [ "$exit_rc" -eq 1 ] && [ "${pause_gate_skip:-0}" = "1" ]; then
    exit 1
  fi
  exit 2
}
trap on_exit EXIT

if [ "$#" -ne 1 ]; then
  echo "usage: pause-gate.sh <job-id>" >&2
  exit 2
fi

job_id="$1"

# HOME can be absent from a daemon environment. Resolve it rather than
# tripping `set -u` (which would exit 1 — a silent skip) further down.
if [ -z "${HOME:-}" ]; then
  HOME=$(cd ~ 2>/dev/null && pwd) || HOME=""
  [ -n "$HOME" ] || HOME="/Users/nelson"
  export HOME
fi

# NOTE: split into an if-guard rather than PAUSE_NOTE="${PAUSE_NOTE:-...}" on
# one line. bash 3.2 (macOS /bin/bash) mis-parses the literal apostrophe in
# "Operator's" inside a ${VAR:-default} expansion even when double-quoted.
if [ -z "${PAUSE_NOTE:-}" ]; then
  PAUSE_NOTE="$HOME/obsidian/00-09 System/00 System management/00.08 Operator's console/Pause.md"
fi

# The backup jobs are exempt by name (01.65 rule 10) — they run paused or not,
# and they run even when the flag note itself cannot be read.
case "$job_id" in
  obsidian-backup|vault-backup) exit 0 ;;
esac

# ---- the flag parser, from the one shared file ----
# `claude/lib/pause-flag.sh` holds it. This block and its twin in `claude/hooks/pause-guard.sh` carried BYTE-IDENTICAL copies of
# a 69-line parser, each with a comment telling the reader to keep it identical to the other — and by the
# time they were unified they already differed by one word.
#
# Found by walking UP to the repo root rather than counting levels, because the two callers sit at
# different depths and a copied `../..` resolves to a path that does not exist. `.git` is a directory in
# the main checkout and a file in a worktree, so `-e` covers both, and from a worktree this reads that
# worktree's own copy.
pf_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || pf_dir=""
while [ -n "$pf_dir" ] && [ ! -e "$pf_dir/.git" ]; do [ "$pf_dir" != "/" ] || { pf_dir=""; break; }; pf_dir=$(dirname "$pf_dir"); done
PAUSE_FLAG_LIB="$pf_dir/claude/lib/pause-flag.sh"
# EXIT 2, not 1: tickle reads 1 as "skip" and 2 as "check failed". A parser this script cannot find is
# a check it cannot make, and a skip would be an invisible permanent one — the silent-failure class that
# hid a 29-hour obsidian-backup outage. The message names the directory searched, because "not found" with
# no path is the least actionable failure there is.
if [ -z "$pf_dir" ] || [ ! -r "$PAUSE_FLAG_LIB" ]; then
  printf 'pause-gate: the pause parser could not be found from %s (no .git above it, or %s is unreadable); exiting 2 so tickle records a failed check rather than a silent skip\n' "$(dirname "$0")" "$PAUSE_FLAG_LIB" >&2
  exit 2
fi
# shellcheck source=../lib/pause-flag.sh
. "$PAUSE_FLAG_LIB" || { printf 'pause-gate: the pause parser at %s could not be sourced; exiting 2 so tickle records a failed check rather than a silent skip\n' "$PAUSE_FLAG_LIB" >&2; exit 2; }
# ---- end flag parser ----

read_pause_flag

case "$flag_state" in
  absent|clear)
    exit 0
    ;;
  bad)
    echo "[pause-gate] CANNOT READ the fleet pause flag — refusing to run '$job_id' (note: $PAUSE_NOTE; $flag_reason)" >&2
    exit 2
    ;;
esac

by=$(fm_value paused-by)
since=$(fm_value paused-since)
why=$(fm_value paused-why)
[ -n "$by" ] || by="(unset)"
[ -n "$since" ] || since="(unset)"
[ -n "$why" ] || why="(unset)"

echo "[pause-gate] fleet paused — skipping '$job_id' (note: $PAUSE_NOTE; paused-by: $by; paused-since: $since; paused-why: $why)" >&2
pause_gate_skip=1
exit 1
