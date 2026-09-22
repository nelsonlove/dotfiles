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

# ---- flag parser (keep identical to claude/hooks/pause-guard.sh) ----
# Sets: flag_state = absent | paused | clear | bad, flag_reason, flag_block.
# CR is stripped everywhere: a CRLF note otherwise never matches the `---`
# fence, which used to leave the frontmatter empty and the gate wide open.

sq="'"
flag_state=""
flag_reason=""
flag_block=""

fm_value() {
  printf '%s\n' "$flag_block" \
    | grep -E "^[[:space:]]*$1[[:space:]]*:" \
    | head -n 1 \
    | sed -E "s/^[[:space:]]*$1[[:space:]]*:[[:space:]]*//" \
    | sed -E "s/^\"(.*)\"\$/\1/; s/^${sq}(.*)${sq}\$/\1/" \
    | sed -E "s/[[:space:]]+\$//"
}

read_pause_flag() {
  if [ ! -e "$PAUSE_NOTE" ]; then
    flag_state="absent"
    return 0
  fi
  if [ ! -f "$PAUSE_NOTE" ] || [ ! -r "$PAUSE_NOTE" ]; then
    flag_state="bad"
    flag_reason="the note exists but is not a readable file"
    return 0
  fi

  # The opening fence must be the FIRST line. Matching any `---` anywhere
  # would read a thematic break in the body as the start of frontmatter.
  first_line=$(head -n 1 "$PAUSE_NOTE" 2>/dev/null | tr -d '\r' | sed -E "s/[[:space:]]+\$//")
  if [ "$first_line" != "---" ]; then
    flag_state="bad"
    flag_reason="the note has no frontmatter block (it does not begin with ---)"
    return 0
  fi

  flag_block=$(tr -d '\r' < "$PAUSE_NOTE" | awk 'NR==1{next} /^---[ \t]*$/{closed=1; exit} {print} END{if(!closed) exit 1}')
  if [ $? -ne 0 ]; then
    flag_state="bad"
    flag_reason="the note's frontmatter block is never closed"
    return 0
  fi

  paused_line=$(printf '%s\n' "$flag_block" | grep -E "^[[:space:]]*paused[[:space:]]*:" | head -n 1)
  if [ -z "$paused_line" ]; then
    flag_state="bad"
    flag_reason="the note's frontmatter has no 'paused' key"
    return 0
  fi

  paused_value=$(printf '%s' "$paused_line" \
    | sed -E "s/^[[:space:]]*paused[[:space:]]*:[[:space:]]*//" \
    | sed -E "s/[[:space:]]+#.*\$//" \
    | sed -E "s/^\"(.*)\"\$/\1/; s/^${sq}(.*)${sq}\$/\1/" \
    | sed -E "s/^[[:space:]]+//; s/[[:space:]]+\$//" \
    | tr '[:upper:]' '[:lower:]')

  case "$paused_value" in
    true|yes) flag_state="paused" ;;
    false|no) flag_state="clear" ;;
    *)
      flag_state="bad"
      flag_reason="the note's 'paused' value is not true/false/yes/no (found: '$paused_value')"
      ;;
  esac
  return 0
}
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
