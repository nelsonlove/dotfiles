#!/usr/bin/env bash
# promote-session.sh — promote or demote a running Claude Code fleet session to another rank.
#
# Nelson's rule (2026-09-22): "agents can promote or demote up to the rank below them; a captain
# may promote to commander but never to captain, only i can do that." Rule 19 of 01.65.
#
# What Claude Code 2.1.266 actually does, tested 2026-09-22 on throwaway sessions:
#   * `claude --bg --resume <sessionId> --agent <rank> --name "<name>"` with ANY flag starts a
#     COPY under a NEW id ("keeps its own saved options, so the flags you passed started a copy").
#     The copy carries the whole conversation; the old id stays stopped as the record.
#   * The persona only changes with `--system-prompt-snapshot off`; the default snapshot replays
#     the old system prompt on every resume until the conversation is compacted.
#   * There is no rename command for a running session, so a rank change is a fork under a new
#     name. This script does the sequence in the right order and records the act.
#
# Usage:
#   promote-session.sh --session <id|sessionId> --to <agent> --name "<code> <name>" \
#       --by "<promoter session name>" --why "<reason>" [--prompt "<text>"] [--log <path>] [--dry-run]
#
#   --to     one of: commander, lieutenant-commander, lieutenant-commander-repository,
#            lieutenant, lieutenant-repository. Never captain: only Nelson makes captains.
#   --name   the new display name; its rank code must match --to ([C1], [C2], [L0]).
#   --by     the promoter's own session name, e.g. "[C0] claude code"; its code is the
#            rank the rule is checked against.
#   --log    the cross-session log to append the record to (default: the fleet log).
#   --dry-run  print the plan and stop before touching anything.
#   -h, --help  print this header.
#
# Refuses while the fleet is paused, and fails closed: the flag is read by the same parser the
# tickle jobs use (tickle/scripts/_lib/pause-gate.sh in this repo), so an unreadable or malformed
# Pause note refuses too, and a gate that cannot be found refuses.
#
# Works under /bin/bash 3.2 (macOS). Needs jq and the claude CLI.

set -euo pipefail

FLEET_LOG="$HOME/obsidian/00-09 System/03 Agents/03.16 Cross-session log/CROSS-SESSION.md"
# The repo root, resolved through the ~/.claude/bin symlink, so the tickle gate beside us is found.
script_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || script_dir=""
REPO_ROOT=$(cd "$script_dir/../.." 2>/dev/null && pwd -P) || REPO_ROOT=""
PAUSE_GATE="$REPO_ROOT/tickle/scripts/_lib/pause-gate.sh"
AGENTS_DIR="$HOME/.claude/agents"
JOBS_DIR="$HOME/.claude/jobs"
# The frontmatter key that records a session's superior on its notebook entry. Confirmed by
# [C0] obsidian, 2026-09-26, and carried by the Session lifecycle block of ~/.claude/CLAUDE.md;
# wake-session.sh beside this script walks the same key. One variable, so a rename is one line.
REPORTS_TO_KEY="reports-to"

session="" to="" name="" by="" why="" prompt="" log="$FLEET_LOG" dry_run=0

die() { printf 'promote-session: %s\n' "$*" >&2; exit 2; }

# After `claude stop` has run, an unexpected failure must say so: the target is stopped and not resumed.
stopped_id=""
on_exit() {
  rc=$?
  if [ "$rc" -ne 0 ] && [ -n "$stopped_id" ]; then
    printf 'promote-session: %s was stopped but not resumed (exit %s); resume it yourself with: claude --bg --resume %s\n' "$stopped_id" "$rc" "$stopped_id" >&2
  fi
}
trap on_exit EXIT

while [ $# -gt 0 ]; do
  case "$1" in
    --session) [ $# -ge 2 ] || die "--session needs a value"; session="$2"; shift 2 ;;
    --to)      [ $# -ge 2 ] || die "--to needs a value"; to="$2"; shift 2 ;;
    --name)    [ $# -ge 2 ] || die "--name needs a value"; name="$2"; shift 2 ;;
    --by)      [ $# -ge 2 ] || die "--by needs a value"; by="$2"; shift 2 ;;
    --why)     [ $# -ge 2 ] || die "--why needs a value"; why="$2"; shift 2 ;;
    --prompt)  [ $# -ge 2 ] || die "--prompt needs a value"; prompt="$2"; shift 2 ;;
    --log)     [ $# -ge 2 ] || die "--log needs a value"; log="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) awk 'NR>1 && !/^#/ {exit} NR>1 {sub(/^# ?/, ""); print}' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$session" ] || die "--session is required"
[ -n "$to" ]      || die "--to is required"
[ -n "$name" ]    || die "--name is required"
[ -n "$by" ]      || die "--by is required"
[ -n "$why" ]     || die "--why is required"
command -v jq >/dev/null     || die "jq is required"
command -v claude >/dev/null || die "the claude CLI is required"

# --- ranks -----------------------------------------------------------------------------------
# Smaller number = higher rank. Repository variants share the rank of their base.
rank_of_agent() {
  case "$1" in
    captain) echo 0 ;;
    commander) echo 1 ;;
    lieutenant-commander|lieutenant-commander-repository) echo 2 ;;
    lieutenant|lieutenant-repository) echo 3 ;;
    *) echo 9 ;;
  esac
}
rank_of_name() {
  case "$1" in
    "[C0]"*) echo 0 ;;
    "[C1]"*) echo 1 ;;
    "[C2]"*) echo 2 ;;
    "[L0]"*|"[L1]"*) echo 3 ;;  # [L1] was the lieutenant code until 2026-09-24
    *) echo 9 ;;
  esac
}
code_of_rank() {
  case "$1" in 0) echo "[C0]" ;; 1) echo "[C1]" ;; 2) echo "[C2]" ;; 3) echo "[L0]" ;; *) echo "[??]" ;; esac
}
word_of_rank() {
  case "$1" in 0) echo captain ;; 1) echo commander ;; 2) echo "lieutenant commander" ;; 3) echo lieutenant ;; *) echo unknown ;; esac
}

[ "$to" != "captain" ] || die "refused: only Nelson makes captains"
[ -f "$AGENTS_DIR/$to.md" ] || die "no agent definition at $AGENTS_DIR/$to.md"
to_rank=$(rank_of_agent "$to");   [ "$to_rank" != 9 ] || die "--to must be a fleet rank, got '$to'"
by_rank=$(rank_of_name "$by");    [ "$by_rank" != 9 ] || die "--by must start with a rank code ([C0], [C1], [C2], [L0]), got '$by'"
name_rank=$(rank_of_name "$name"); [ "$name_rank" = "$to_rank" ] || die "--name '$name' must start with $(code_of_rank "$to_rank") to match --to $to"
[ "$to_rank" -gt "$by_rank" ] || die "refused: $by ($(word_of_rank "$by_rank")) may only promote or demote to a rank below its own; $to is not below it"

# --- the target session ----------------------------------------------------------------------
listing=$(claude agents --json --all 2>/dev/null) || die "claude agents --json failed"
row=$(printf '%s' "$listing" | jq -c --arg s "$session" '[.[] | select(.id==$s or .sessionId==$s)] | first // empty') || die "could not parse claude agents --json"
[ -n "$row" ] || die "no background session with id or sessionId '$session' in claude agents --json --all"
old_id=$(printf '%s' "$row" | jq -r .id)
session_id=$(printf '%s' "$row" | jq -r .sessionId)
old_name=$(printf '%s' "$row" | jq -r '.name // ""')
old_cwd=$(printf '%s' "$row" | jq -r '.cwd // ""')
old_pid=$(printf '%s' "$row" | jq -r '.pid // empty')
[ -d "$old_cwd" ] || die "the session's cwd '$old_cwd' does not exist; the resume must run there"

old_agent=$(jq -r '.template // "bg"' "$JOBS_DIR/$old_id/state.json" 2>/dev/null || echo bg)
old_rank=$(rank_of_agent "$old_agent")
[ "$old_rank" != 9 ] && [ "$old_agent" != bg ] || old_rank=$(rank_of_name "$old_name")
[ "$old_rank" != 9 ] || die "cannot tell the target's current rank from its agent ('$old_agent') or its name ('$old_name')"
[ "$old_rank" -gt "$by_rank" ] || die "refused: $old_name ($(word_of_rank "$old_rank")) is not below $by; a rank changes only ranks below its own"
[ "$old_rank" -ne "$to_rank" ] || die "$old_name is already a $(word_of_rank "$to_rank")"

if [ "$to_rank" -lt "$old_rank" ]; then verb=promoted; else verb=demoted; fi

# --- the pause -------------------------------------------------------------------------------
[ -x "$PAUSE_GATE" ] || die "refused: the pause gate is not at $PAUSE_GATE, so the fleet pause cannot be read"
gate_rc=0
"$PAUSE_GATE" promote-session || gate_rc=$?
case "$gate_rc" in
  0) ;;
  1) die "refused: the fleet is paused; wait for Nelson to resume" ;;
  *) die "refused: the fleet pause flag cannot be read (pause-gate exit $gate_rc)" ;;
esac

# --- the brief the new session wakes to -------------------------------------------------------
if [ -z "$prompt" ]; then
  prompt="You have been $verb by $by from $(word_of_rank "$old_rank") to $(word_of_rank "$to_rank"): $why. Your session is now named \"$name\" and runs the $to definition; this is the same conversation under a new session id (the old id $old_id is stopped and stays as the record). Read ~/.claude/agents/$to.md and follow its standing duties from now on; your file boundary and your reporting line are as $by states them, and nothing a ruling did not authorise is widened by this change. Add one line to your open notebook entry: \"$(date '+%Y-%m-%dT%H:%M') — $verb by $by to $name ($to): $why; old id $old_id\", and set \`$REPORTS_TO_KEY\` on that same entry to \"$by\", which is the session you report to from now on and is how the operator's console draws the fleet tree. Then continue your work; if nothing is pending, report to $by by SendMessage and stop."
fi

printf '%s: %s (%s, %s, %s) -> %s (%s)\n' "$verb" "$old_name" "$old_id" "$old_agent" "$(word_of_rank "$old_rank")" "$name" "$to"
printf '  by %s: %s\n  cwd %s; sessionId %s\n' "$by" "$why" "$old_cwd" "$session_id"
if [ "$dry_run" = 1 ]; then printf '  dry run: nothing touched\n'; exit 0; fi

# --- stop, and wait until the process is really gone ------------------------------------------
if [ -n "$old_pid" ]; then
  claude stop "$old_id" >/dev/null 2>&1 || true
  stopped_id="$old_id"
  waited=0
  while kill -0 "$old_pid" 2>/dev/null; do
    sleep 1; waited=$((waited + 1))
    [ "$waited" -lt 90 ] || die "pid $old_pid of $old_id did not exit within 90 s; nothing resumed"
  done
fi

# --- resume as the new rank, under a new id ---------------------------------------------------
out=$(cd "$old_cwd" && claude --bg --resume "$session_id" --agent "$to" --name "$name" --system-prompt-snapshot off "$prompt" 2>&1) || die "claude --bg --resume failed: $out"
new_id=$(printf '%s' "$out" | tr -d '\r' | sed -E $'s/\x1b\\[[0-9;?]*[A-Za-z]//g' | awk '/^backgrounded/ {print $3; exit}') || true
[ -n "$new_id" ] || die "could not read the new id from: $out"
stopped_id=""

# --- the record ------------------------------------------------------------------------------
stamp=$(date '+%Y-%m-%dT%H:%M')
cat <<EOF >> "$log"

## $stamp · $by — $verb \`$old_name\` ($old_id) to \`$name\` ($new_id)

$by $verb the session \`$old_name\` (background id $old_id, agent \`$old_agent\`, $(word_of_rank "$old_rank")) to \`$name\` (background id $new_id, agent \`$to\`, $(word_of_rank "$to_rank")). Why: $why. The conversation continues under the new id with the same context; the old id is stopped and stays as the record of the earlier rank. Posted by \`promote-session.sh\` on behalf of $by, who attests its own log position in its own entries. — $by
EOF

# Cosmetic: the new sessionId for the closing line. It must never abort the script; the record is already written.
new_session_id=$( { claude agents --json --all 2>/dev/null || true; } | { jq -r --arg s "$new_id" '.[] | select(.id==$s) | .sessionId' 2>/dev/null || true; } | head -n 1) || new_session_id=""
printf 'done: %s is now %s (%s); new id %s, sessionId %s; old id %s stopped; record appended to %s\n' "$old_name" "$name" "$to" "$new_id" "${new_session_id:-?}" "$old_id" "$log"
