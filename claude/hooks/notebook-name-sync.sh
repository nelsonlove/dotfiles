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

# The fast path: a RUNNING entry already carrying this name means nothing has drifted. The status test is not
# optional — a name recurs across days, so an `ended` entry from an earlier day carrying the same name would
# otherwise satisfy this and leave today's running entry misnamed for good.
#
# EITHER KEY DECIDES, until 2026-10-04, because the notebook's status machine is folding into the vault's:
# `session-status: running` or `status: draft/running`. The rule and its five states live in
# `claude/lib/session-status.sh`, which this reads rather than restates — the grep that used to be here knew
# only the old key, so the day the vault's migration landed this hook would have found no running entry for
# any session and quietly renamed nothing, every turn, with nothing in any log to say why.
#
# THE LIBRARY IS OPTIONAL HERE, AND THAT IS THE POINT: this hook must never fail a turn, so if the rule cannot
# be read it says so once on stderr and does nothing, rather than refusing. A missed rename is a name out of
# step in a record; a refusal is Nelson's session unable to think.
in_step=0
SESSION_STATUS_LIB="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)/../lib/session-status.sh"
if [ -r "$SESSION_STATUS_LIB" ] && bash -n "$SESSION_STATUS_LIB" 2>/dev/null && . "$SESSION_STATUS_LIB" 2>/dev/null && command -v session_status_of >/dev/null 2>&1; then
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    session_status_of "$hit"
    # `${sess_state:-}` AND NOT `$sess_state`. The guard above proves the rule file is readable, parses, and
    # defines the reader — and a file can pass all three while setting no globals at all, which under `set -u`
    # made this line an unbound-variable abort: rc=1 from a hook whose whole contract is that it never fails a
    # turn. Found by the review of the fix-forward, which added the broken-library cases and missed this shape.
    case "${sess_state:-}" in
      running) in_step=1; break ;;
      conflict)
        # Not renamed, and said out loud: an entry that disagrees with itself is a thing a human must fix, and
        # this hook is the only machinery that reads it every turn.
        printf 'notebook-name-sync: %s disagrees with itself about its session status — %s; nothing renamed\n' "$hit" "${sess_detail:-no detail}" >&2
        in_step=1; break ;;
    esac
  done <<EOF
$(grep -rlF --include='*.md' "session: \"$name\"" "$NOTEBOOK_DIR" 2>/dev/null || true)
EOF
else
  printf 'notebook-name-sync: the session-status rule at %s could not be read, so nothing was renamed this turn\n' "$SESSION_STATUS_LIB" >&2
  exit 0
fi
[ "$in_step" = 0 ] || exit 0

[ -x "$RENAME" ] || exit 0
if ! out=$("$RENAME" "$sid" 2>&1); then
  printf 'notebook-name-sync: rename-notebook.sh refused or failed for %s: %s\n' "$sid" "$(printf '%s' "$out" | tail -n 1)" >&2
fi
exit 0
