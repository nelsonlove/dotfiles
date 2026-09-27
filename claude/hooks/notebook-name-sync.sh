#!/usr/bin/env bash
# notebook-name-sync.sh — when a session's name has changed, put its notebook entry's filename back
# in step, by calling ~/.claude/bin/rename-notebook.sh.
#
# Registered on UserPromptSubmit and on SessionStart with reason `resume`, per the shape Nelson
# cleared in the queue note "Rule on the notebook rename machinery and whether existing entries are
# retitled": a rename in the fleet view is caught on the session's next turn or its next wake. Hook
# input carries `session_id` but never the display name, so the session registry is the only route to
# the current name, and the rename script does that lookup.
#
# The fast path is a grep for the name and a grep for the status. If a RUNNING entry already carries
# `session: "<current name>"`, the filename and the key are in step and this exits silently. Only
# when no running entry carries the current name does it call the script, which is the one place that
# knows which forms may be renamed, which entries are records, and how to rename through Obsidian.
#
# It never blocks a prompt: every path exits 0, the script's output goes nowhere (its record is the
# cross-session log line it writes), and a failure says so on stderr only, which does not enter the
# session's context.
#
# Deliberately NOT handled: an idle background session renamed in the view stays misnamed until it is
# next messaged or woken. That consequence was accepted in the ruling.

set -u

NOTEBOOK_DIR="${NOTEBOOK_NAME_SYNC_DIR:-$HOME/obsidian/00-09 System/03 Agents/03.04 Records/Agent notebook}"
RENAME="${NOTEBOOK_NAME_SYNC_SCRIPT:-$HOME/.claude/bin/rename-notebook.sh}"
SESSIONS_DIR="$HOME/.claude/sessions"

input=$(cat 2>/dev/null || true)
[ -n "$input" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

event=$(printf '%s' "$input" | jq -r '.hook_event_name // ""' 2>/dev/null || echo "")
sid=$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null || echo "")
source_reason=$(printf '%s' "$input" | jq -r '.source // .reason // ""' 2>/dev/null || echo "")

[ -n "$sid" ] || exit 0
case "$event" in
  UserPromptSubmit) ;;
  SessionStart)
    # Only a resume: a fresh start has no entry yet, and a clear or compact is not a rename.
    [ "$source_reason" = "resume" ] || exit 0 ;;
  *) exit 0 ;;
esac

# The current name, from the registry keyed by sessionId.
name=""
for candidate in "$SESSIONS_DIR"/*.json; do
  [ -f "$candidate" ] || continue
  if [ "$(jq -r '.sessionId // ""' "$candidate" 2>/dev/null || echo "")" = "$sid" ]; then
    name=$(jq -r '.name // ""' "$candidate" 2>/dev/null || echo "")
    break
  fi
done
[ -n "$name" ] || exit 0

# The fast path: a RUNNING entry already carrying this name means nothing has drifted. The
# session-status test is not optional — a name recurs across days, so an `ended` entry from an
# earlier day carrying the same name would otherwise satisfy this and leave today's running entry
# misnamed for good. Two cheap greps: the name narrows it to a file or two, the status decides.
in_step=0
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  if grep -qE '^[[:space:]]*session-status[[:space:]]*:[[:space:]]*"?running"?[[:space:]]*$' "$hit" 2>/dev/null; then
    in_step=1
    break
  fi
done <<EOF
$(grep -rlF --include='*.md' "session: \"$name\"" "$NOTEBOOK_DIR" 2>/dev/null || true)
EOF
[ "$in_step" = 0 ] || exit 0

[ -x "$RENAME" ] || exit 0
if ! out=$("$RENAME" "$sid" 2>&1); then
  printf 'notebook-name-sync: rename-notebook.sh refused or failed for %s: %s\n' "$sid" "$(printf '%s' "$out" | tail -n 1)" >&2
fi
exit 0
