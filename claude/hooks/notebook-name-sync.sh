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
SESSIONS_DIR="${NOTEBOOK_NAME_SYNC_SESSIONS_DIR:-$HOME/.claude/sessions}"
JOBS_DIR="${NOTEBOOK_NAME_SYNC_JOBS_DIR:-$HOME/.claude/jobs}"

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
reg_file=""
for candidate in "$SESSIONS_DIR"/*.json; do
  [ -f "$candidate" ] || continue
  if [ "$(jq -r '.sessionId // ""' "$candidate" 2>/dev/null || echo "")" = "$sid" ]; then
    name=$(jq -r '.name // ""' "$candidate" 2>/dev/null || echo "")
    reg_file="$candidate"
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
# THE ROSTER KEYS, package 6. A session's notebook entry is the record OF that session, so it carries
# `session-id` (full, 36 characters), `session`, `agent` and `cwd`. This writes `agent` and `cwd` beside the
# id, on a turn only, into the entry the loop below has just agreed is this session's running one.
#
# WHY THE HOOK AND NOT THE SESSION. `claude rm` takes the job away — the listing row, the job state and the
# saved options — and leaves the transcript. After that the entry is the only place the name, the agent and
# the directory still exist, and a post-rm resume needs all three. A session that forgets to write them is
# a session that cannot be brought back, so the machinery writes them rather than the instructions asking.
#
# AGENT IS READ, NEVER INFERRED: the job state's `template` first, the registry's `agent` as the fallback,
# and NOTHING WRITTEN when both are absent — an invented agent is worse than a missing one, because a resume
# would bring the session back as something it never was. `claude` is a legitimate value and is written
# verbatim; it is what a session Nelson opened himself runs as, and it sits under rank-coded names all over
# the fleet.
#
# CWD IS THE REGISTRY'S FIRST, the job state's as the fallback, because the transcript lives under the
# project directory of the cwd the session is IN, not the one it started in — Claude Code moves it and leaves
# a `.superseded-<ms>` marker behind. Measured on this machine; `claude/lib/session-roster.sh` carries the
# three values and both markers as the evidence.
#
# IT NEVER FAILS A TURN and it never rewrites a value that is already right: a key is written only when it is
# missing or different, the file is rewritten through a temp file and moved into place, and every failure is
# silent except one line on stderr. A notebook entry is a record — this adds keys to it and changes nothing
# else, and if it cannot, the turn goes on.
roster_write() {  # $1 = this session's running entry
  rw_entry="$1"
  [ -n "$rw_entry" ] && [ -f "$rw_entry" ] && [ -w "$rw_entry" ] || return 0

  # The agent: job state first, registry second, nothing if neither says.
  rw_job_id=$(jq -r '.jobId // ""' "$reg_file" 2>/dev/null || echo "")
  [ -n "$rw_job_id" ] || rw_job_id=$(printf '%s' "$sid" | cut -c1-8)
  rw_agent=$(jq -r '.template // ""' "$JOBS_DIR/$rw_job_id/state.json" 2>/dev/null || echo "")
  [ -n "$rw_agent" ] || rw_agent=$(jq -r '.agent // ""' "$reg_file" 2>/dev/null || echo "")

  # The cwd: the registry's, then the job state's.
  rw_cwd=$(jq -r '.cwd // ""' "$reg_file" 2>/dev/null || echo "")
  [ -n "$rw_cwd" ] || rw_cwd=$(jq -r '.cwd // ""' "$JOBS_DIR/$rw_job_id/state.json" 2>/dev/null || echo "")

  rw_tmp="$rw_entry.roster.$$"
  if ! awk -v sid="$sid" -v agent="$rw_agent" -v cwd="$rw_cwd" '
    # Only inside the frontmatter block, and only the three keys. Everything else passes through byte for
    # byte, including the body, because this is a record and nothing here is entitled to rewrite it.
    NR == 1 { if ($0 !~ /^---[ \t\r]*$/) { bad = 1; exit 1 } print; infm = 1; next }
    infm && /^---[ \t\r]*$/ {
      if (!seen_id && sid != "")     print "session-id: " sid
      if (!seen_agent && agent != "") print "agent: " agent
      if (!seen_cwd && cwd != "")    print "cwd: " cwd
      infm = 0; print; next
    }
    infm && /^[ \t]*session-id[ \t]*:/ { seen_id = 1;    if (sid   != "") { print "session-id: " sid; next } }
    infm && /^[ \t]*agent[ \t]*:/      { seen_agent = 1; if (agent != "") { print "agent: " agent;    next } }
    infm && /^[ \t]*cwd[ \t]*:/        { seen_cwd = 1;   if (cwd   != "") { print "cwd: " cwd;        next } }
    { print }
  ' "$rw_entry" > "$rw_tmp" 2>/dev/null; then
    rm -f "$rw_tmp" 2>/dev/null || true
    return 0
  fi
  # Nothing is moved into place unless the result still looks like the entry: a frontmatter fence on line one
  # and no fewer lines than it had. A truncated record is worse than an unwritten key.
  rw_old_lines=$(grep -c '' "$rw_entry" 2>/dev/null || echo 0)
  rw_new_lines=$(grep -c '' "$rw_tmp" 2>/dev/null || echo 0)
  if [ -s "$rw_tmp" ] && [ "$rw_new_lines" -ge "$rw_old_lines" ] && [ "$(head -n 1 "$rw_tmp")" = "---" ]; then
    if ! cmp -s "$rw_tmp" "$rw_entry"; then
      mv "$rw_tmp" "$rw_entry" 2>/dev/null || printf 'notebook-name-sync: could not write the roster keys into %s\n' "$rw_entry" >&2
    fi
  fi
  rm -f "$rw_tmp" 2>/dev/null || true
  return 0
}

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
      running)
        in_step=1
        # ON A TURN ONLY, never on a resume. The ruling is explicit and the reason is a race: a resume is the
        # moment the roster keys are READ — by the post-rm path, to know what to resume as — so writing them
        # in the same breath would have the wake reading values this hook is still deciding. The first
        # version of this wrote on both, and the suite caught it.
        [ "$event" != "UserPromptSubmit" ] || roster_write "$hit"
        break ;;
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
