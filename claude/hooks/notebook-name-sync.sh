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
# THE ONE PARSE OF `session-id` FOR THIS HOOK, matching `claude/lib/session-roster.sh`'s
# `roster_id_in_frontmatter` line for line. The hook cannot source that library — it runs before anything sets
# a library path and must never fail a turn — so the program is duplicated, and the suite compares the two
# texts so they cannot drift. Two parsers of one line disagreeing is the defect this package produced twice.
nns_id_in_frontmatter() {  # $1 = the entry; prints the id, or nothing
  [ -n "${1:-}" ] && [ -f "$1" ] || return 0
  awk '
    # ONE PARSE OF `session-id`, SHARED. Prints the id an entry states, or nothing when its block is unclosed.
    # Inside a closed block, at column zero, the LAST occurrence wins, and the value is normalised exactly as
    # `roster_value` normalises it: a QUOTED value is taken whole (a `#` inside quotes is part of the value),
    # and only an UNQUOTED one can carry a trailing ` # comment`. Order decides which, and this is the order.
    NR == 1 { if ($0 !~ /^---[ \t\r]*$/) exit 1; infm = 1; next }
    infm && /^---[ \t\r]*$/ { closed = 1; exit }
    infm && /^session-id[ \t]*:/ {
      v = $0
      sub(/^session-id[ \t]*:[ \t]*/, "", v); gsub(/\r/, "", v); sub(/[ \t]+$/, "", v)
      if (v ~ /^".*"/)        { sub(/^"/, "", v); sub(/".*$/, "", v) }
      else if (v ~ /^\047.*\047/) { sub(/^\047/, "", v); sub(/\047.*$/, "", v) }
      else                    { sub(/[ \t]+#.*$/, "", v); sub(/[ \t]+$/, "", v) }
      if (seen++) dup = 1
      last = v
    }
    # A KEY STATED TWICE PRINTS NOTHING, because `roster_value` returns nothing for it and these two must not
    # disagree about any line. Taking the last one here would have made `roster_entry_is_id` say "ours" about
    # a record the reader calls unidentified — the same split this shared program exists to end.
    END { if (closed && !dup) print last }' "$1" 2>/dev/null || true
}

roster_write() {  # $1 = this session's running entry
  rw_entry="$1"
  [ -n "$rw_entry" ] && [ -f "$rw_entry" ] && [ -w "$rw_entry" ] || return 0
  # NO ID, NO WRITE. Blanking an unwritable value (below) must never be able to reach `session-id` itself —
  # that key is the record's identity and the thing the post-rm resume needs most. If this session has no id
  # there is nothing to record, so the whole write stands down.
  [ -n "$sid" ] || return 0

  # IT MUST BE OUR ENTRY, AND THE TEST IS THE ID — NOT THE NAME. The loop that found this file matched on the
  # DISPLAY NAME and took the first entry reading `running`, in directory order. A name recurs: eleven sessions
  # shared one on 2026-09-26, and a stale `draft/running` entry from an earlier session sorts first. The review
  # of #71 proved the consequence — today's facts written over another session's record, today's real entry
  # left with nothing. So: an entry that already carries a DIFFERENT `session-id` is never touched. An entry
  # with no id is adopted, because that is what an entry written before this ruling looks like, and an entry
  # carrying our own id is ours to keep current.
  # THE LAST `session-id` WINS, because that is what the reader takes. They disagreed: this read the FIRST and
  # `roster_value` the LAST, so an entry carrying ours first and a foreign id second was written to here and
  # read as somebody else's there. Two readers of one record must not pick different lines.
  rw_existing=$(nns_id_in_frontmatter "$rw_entry")
  if [ -n "$rw_existing" ] && [ "$rw_existing" != "$sid" ]; then
    printf 'notebook-name-sync: %s carries session-id %s, not this session; nothing written\n' "$rw_entry" "$rw_existing" >&2
    return 0
  fi

  # AND THE FRONTMATTER MUST BE CLOSED. Without a closing fence there is no block, only a file — and the first
  # version of this stayed "inside frontmatter" to the end of it, rewriting body lines that happened to begin
  # `agent:` or `cwd:`. A record whose prose is edited is worse than a key that never lands.
  awk 'NR == 1 { if ($0 !~ /^---[ \t\r]*$/) exit 1; next }
       /^---[ \t\r]*$/ { found = 1; exit }
       END { exit (found ? 0 : 1) }' "$rw_entry" 2>/dev/null || return 0

  # AND NO KEY MAY APPEAR TWICE AT COLUMN ZERO. The writer rewrites a key in place and the reader takes the
  # LAST one, and this rewrote the FIRST — so an entry reading `session-id: <foreign>` and then a blank
  # `session-id:` counted as id-less (the last value is empty), was adopted, and had the FOREIGN line
  # overwritten with ours. The identity guard above was reached by a different road. The same split on `cwd`
  # sent a resume to a directory nobody wrote. Rewriting the last instead leaves a stale duplicate standing,
  # and deleting the earlier one makes the file shorter than the guard below allows. A record that states one
  # key twice is a record a human must settle, and this hook leaves it alone.
  if ! awk 'NR == 1 { if ($0 !~ /^---[ \t\r]*$/) { bad = 1; exit } infm = 1; next }
            infm && /^---[ \t\r]*$/ { exit }
            infm && /^session-id[ \t]*:/ { if (seen_id++)    bad = 1 }
            infm && /^agent[ \t]*:/      { if (seen_agent++) bad = 1 }
            infm && /^cwd[ \t]*:/        { if (seen_cwd++)   bad = 1 }
            END { exit (bad ? 1 : 0) }' "$rw_entry" 2>/dev/null; then
    printf 'notebook-name-sync: %s states session-id, agent or cwd twice; nothing written\n' "$rw_entry" >&2
    return 0
  fi

  # AND NONE OF THE THREE KEYS MAY BE A FOLDED OR BLOCK VALUE. `agent: >` with an indented line under it is one
  # value across two lines; replacing the first line leaves the second orphaned under the new scalar, and the
  # line-count guard below does not see it because the file did not shrink. Dropping the continuation was the
  # other road, and it makes the file SHORTER than the guard allows — so the guard would have to be loosened
  # to let a shrinking write through, which is the one thing it exists to stop. A shape this cannot rewrite
  # safely is a shape it does not rewrite: it says so and leaves the record alone.
  #
  # `exit 1` HERE WOULD NOT BE THE EXIT STATUS. In awk, `exit` in a main rule jumps to END, and an `exit` in
  # END replaces the status — so a first version that ended `END { exit 0 }` found the folded value, exited 1,
  # ran END, and reported success. The whole guard was dead on arrival and the suite caught it on the first
  # run. The verdict lives in a flag; END is the only place that decides the status.
  if ! awk 'NR == 1 { if ($0 !~ /^---[ \t\r]*$/) { bad = 1; exit } infm = 1; next }
            infm && /^---[ \t\r]*$/ { exit }
            infm && k && /^[ \t]+[^ \t]/ { bad = 1; exit }
            infm { k = ($0 ~ /^(session-id|agent|cwd)[ \t]*:/) }
            END { exit (bad ? 1 : 0) }' "$rw_entry" 2>/dev/null; then
    printf 'notebook-name-sync: %s holds a multi-line session-id, agent or cwd; nothing written\n' "$rw_entry" >&2
    return 0
  fi

  # The agent: job state first, registry second, nothing if neither says.
  rw_job_id=$(jq -r '.jobId // ""' "$reg_file" 2>/dev/null || echo "")
  [ -n "$rw_job_id" ] || rw_job_id=$(printf '%s' "$sid" | cut -c1-8)
  rw_agent=$(jq -r '.template // ""' "$JOBS_DIR/$rw_job_id/state.json" 2>/dev/null || echo "")
  [ -n "$rw_agent" ] || rw_agent=$(jq -r '.agent // ""' "$reg_file" 2>/dev/null || echo "")

  # The cwd: the registry's, then the job state's.
  rw_cwd=$(jq -r '.cwd // ""' "$reg_file" 2>/dev/null || echo "")
  [ -n "$rw_cwd" ] || rw_cwd=$(jq -r '.cwd // ""' "$JOBS_DIR/$rw_job_id/state.json" 2>/dev/null || echo "")

  # A VALUE GOES IN QUOTED, OR NOT AT ALL. Unquoted, a trailing space or a ` #` was lost on the round trip —
  # and the reader strips exactly those — so a post-rm resume would have started in the wrong directory. A
  # value carrying a double quote or a backslash is REFUSED rather than escaped: nothing in a cwd or an agent
  # name legitimately holds one, and a quoting bug in a vault note breaks the note's properties. A value
  # carrying a NEWLINE is not refused here — `awk -v` rejects it first and the whole write is lost, including
  # `session-id`. That is safe and it is not what this test does, so the comment says so rather than claiming
  # a guard that lives somewhere else.
  # ONE CHARACTER PER ALTERNATIVE, IN A BRACKET EXPRESSION. This class has now been wrong twice, both times
  # through quoting. Built through two layers of shell quoting it matched a plain `n`, so every path holding
  # one — every real path — was thrown away and `cwd` was never written. Rewritten as `*'\\'*` it matched TWO
  # backslashes, because inside single quotes a backslash is literal; a single one went through to `awk -v`,
  # which interprets escapes, and a value holding `\n` wrote a real line break inside a quoted scalar, `\t` a
  # tab, `\b` a backspace byte. `[\\]` says one backslash and cannot be read as anything else.
  # A CONTROL CHARACTER IS REFUSED TOO, not only a quote and a backslash. A backspace byte in a cwd went raw
  # into the quoted scalar, and YAML does not allow a raw control character there — the note's properties stop
  # parsing, which is the same damage by a quieter route. A real newline never reaches this: `awk -v` fails on
  # it first and the whole write is lost, which is safe. Tabs and non-ASCII are fine and are kept.
  case "$rw_agent" in *[\\]*|*'"'*|*[[:cntrl:]]*) rw_agent="" ;; esac
  case "$rw_cwd"   in *[\\]*|*'"'*|*[[:cntrl:]]*) rw_cwd="" ;; esac

  rw_tmp="$rw_entry.roster.$$"
  if ! awk -v sid="$sid" -v agent="$rw_agent" -v cwd="$rw_cwd" '
    function q(v) { return "\"" v "\"" }
    # Only inside the frontmatter block, only at column zero, and only these three keys. Column zero matters:
    # `^[ \t]*cwd:` also matches a key nested under a parent mapping, and rewriting that hoists it out and
    # destroys the parent — the review found it, with the line count unchanged so the guard below passed.
    NR == 1 { print; infm = 1; next }
    infm && /^---[ \t\r]*$/ {
      if (!seen_id && sid != "")      print "session-id: " q(sid)
      if (!seen_agent && agent != "") print "agent: " q(agent)
      if (!seen_cwd && cwd != "")     print "cwd: " q(cwd)
      infm = 0; print; next
    }
    # A KEY WHOSE VALUE WE CANNOT WRITE IS BLANKED, NOT LEFT. Dropping the value and leaving the old line
    # meant the record kept a STALE directory — the session had moved somewhere this cannot express, and the
    # entry went on naming the old one, which a post-rm resume would have believed. An empty value says "not
    # known" honestly; the old one lies.
    infm && /^session-id[ \t]*:/ { if (!seen_id)    { seen_id = 1;    print "session-id: " (sid   != "" ? q(sid)   : "\"\""); next } }
    infm && /^agent[ \t]*:/      { if (!seen_agent) { seen_agent = 1; print "agent: "      (agent != "" ? q(agent) : "\"\""); next } }
    infm && /^cwd[ \t]*:/        { if (!seen_cwd)   { seen_cwd = 1;   print "cwd: "        (cwd   != "" ? q(cwd)   : "\"\""); next } }
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

# OUR OWN ENTRY FIRST, THEN THE NEWEST. A plain reverse sort put the newest same-named entry first, and the
# loop stops at the first one it can use — so a LATER-started session of the same name, whose entry carries
# its own id, sorted ahead of this session's own older entry and the write refused on the foreign id. It fails
# safe (nothing is written), but it fails where the old arbitrary order would sometimes have succeeded. An
# entry carrying OUR id is unambiguously ours, so it goes first; everything else follows newest-first, which
# is what stops a stale id-less entry from winning by being alphabetically early.
rc_fm_id() {  # $1 = the entry, $2 = the id — true when the entry's FRONTMATTER names exactly this id
  [ -f "$1" ] || return 1
  rc_found=$(nns_id_in_frontmatter "$1")
  [ "$rc_found" = "$2" ]
}

roster_candidates_for() {  # $1 = display name, $2 = this session's id, $3 = the notebook root
  rc_all=$(grep -rlF --include='*.md' "session: \"$1\"" "$3" 2>/dev/null || true)
  [ -n "$rc_all" ] || return 0
  rc_mine=""; rc_rest=""
  while IFS= read -r rc_f; do
    [ -n "$rc_f" ] || continue
    # STRICT, AND INSIDE THE FRONTMATTER ONLY. A whole-file grep let a BODY line reading `session-id: <ours>`
    # — a pasted handoff, a quoted block — promote another session's id-less entry to "ours", where the writer
    # (which reads only the frontmatter, sees no id, and adopts an id-less entry by design) wrote our facts
    # over that session's record. This is the ownership question, so it takes the strict test; the loose one
    # lives in the library and answers a different question at the opposite cost.
    if rc_fm_id "$rc_f" "$2"; then
      rc_mine="$rc_mine$rc_f
"
    else
      rc_rest="$rc_rest$rc_f
"
    fi
  done <<EOF
$rc_all
EOF
  printf '%s' "$rc_mine"
  printf '%s' "$rc_rest" | sort -r
}

# THE NEWEST CANDIDATE FIRST among the rest, not the first in directory order. The loop below stops at the first entry that
# reads `running`, and an entry's filename is its stamp, so a reverse sort puts the newest first. Without it a
# STALE running entry from an earlier session of the same name won — and an entry with no `session-id` is
# adopted by design, because that is what an entry written before the roster ruling looks like, so the stale
# one took today's id, agent and cwd while the live session's own entry got nothing. A name recurs: eleven
# sessions shared one on 2026-09-26. This does not make a wrong entry right; it stops the oldest winning by
# accident.
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
$(roster_candidates_for "$name" "$sid" "$NOTEBOOK_DIR")
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
