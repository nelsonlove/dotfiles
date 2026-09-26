#!/usr/bin/env bash
# wake-session.sh — wake a stopped Claude Code fleet session, or say how to reach a live one.
#
# Nelson's question (2026-09-26): nothing wakes or resumes a subordinate after a pause or a stop.
# `promote-session.sh` beside this script changes a session's rank; this one only says "carry on".
# The rank line is rule 19 of 01.65 Operator's console: a rank reaches only ranks below its own.
#
# What Claude Code 2.1.266 actually does, tested on throwaway sessions:
#   * A FLAGLESS `claude --bg --resume <sessionId> "<message>"` continues a STOPPED session under
#     the SAME id, with its whole conversation. Any flag (--agent, --name, --system-prompt-snapshot)
#     makes a COPY under a new id instead, which is what promote-session.sh uses on purpose.
#   * A session that is still RUNNING cannot be resumed at all: the same resume makes a copy and
#     says "already running". Only a Claude session's own SendMessage tool reaches a live session's
#     socket; no CLI can. So for a live target this script prints the SendMessage to send and stops.
#
# Usage:
#   wake-session.sh --session <id|sessionId> --by "<your session name>" --why "<reason>" \
#       [--message "<text>"] [--log <path>] [--notebook-dir <path>] [--dry-run]
#   wake-session.sh --all --by "<your session name>" [--resume-stopped --why "<reason>"] \
#       [--log <path>] [--notebook-dir <path>] [--dry-run]
#
#   --session  the target's background id or sessionId, as `claude agents --json --all` lists it.
#   --by       your own session name, e.g. "[C1-OB] spec"; its rank code is the rank the rules are
#              checked against. The script cannot verify who is calling it, so it never grants a
#              captain's reach to a name that does not carry a captain's code.
#   --why      the reason, recorded in the cross-session log. Required with --session, and with
#              --all --resume-stopped.
#   --message  the text the woken session reads. A default brief is written when this is omitted.
#   --all      survey every session below your rank instead of waking one — a read, so it lists and
#              composes nothing to send; grouped by ship code
#              (`CC` in `[L0-CC] dotfiles`, and a "no ship code" block for a bare `[L0] dotfiles`,
#              because a ship is never guessed) and inside each ship by state: alive and idle (which
#              needs a SendMessage — run --session on one to get the text), alive and busy (left
#              alone), stopped (offered, and resumed only with --resume-stopped).
#   --resume-stopped  with --all, resume every stopped session in your line, one log entry each.
#   --log      the cross-session log to append the record to (default: the fleet log).
#   --notebook-dir  where the agent notebook lives. For testing only.
#   --pause-note  the Pause note the gate reads. For testing only; an ordinary run reads the fleet's
#              own note, and PAUSE_NOTE is deliberately NOT inherited from the environment.
#   --dry-run  print the plan and touch nothing.
#   -h, --help  print this header.
#
# Exit codes: 0 done; 2 refused or failed; 3 the target is alive, so SendMessage it (the command is
# printed) — nothing was touched.
#
# What it refuses, and why:
#   * A target at or above the caller's rank, and a `[C0]` target always: only Nelson wakes a
#     captain, and the script cannot verify that it is Nelson calling.
#   * A target outside the caller's reporting line. The line is data now: each session's open
#     notebook entry carries `reports-to`, the name of the session that dispatched it (or `Nelson`
#     for a captain), and this script walks that chain up from the target. A target with no running
#     notebook entry, or an entry with no `reports-to`, is refused: a missing record is not a
#     permission.
#   * Any wake while the fleet is paused. The flag is read by the same parser the tickle jobs use
#     (tickle/scripts/_lib/pause-gate.sh in this repo), so an unreadable or malformed Pause note
#     refuses too, and a gate that cannot be found refuses. The --all survey is a read, and a pause
#     never gates a read, so the pause is checked there only before a session is resumed.
#   * A target whose rank cannot be told from its agent definition or its name, and a caller trying
#     to wake itself. Neither is guessed at.
#
# What these refusals are, and are not: they stop a mistake and a hasty act, not a determined
# caller. `--by` is what the caller says it is, the reporting line is read from notebook files any
# fleet session can write, and anyone holding a shell can run `claude --bg --resume` and skip this
# script altogether. So the rails are a discipline with a record, not an authentication boundary.
# Three flags widen them on purpose, for tests: `--notebook-dir` replaces the reporting-line record,
# `--pause-note` replaces the pause flag, and `--log` sends the record somewhere other than the
# fleet log. A run that passes any of them is a test, not a fleet act — say so if you use them.
#
# Works under /bin/bash 3.2 (macOS). Needs jq and the claude CLI.

set -euo pipefail

FLEET_LOG="$HOME/obsidian/00-09 System/03 Agents/03.16 Cross-session log/CROSS-SESSION.md"
# The repo root, resolved through the ~/.claude/bin symlink, so the tickle gate beside us is found.
script_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || script_dir=""
REPO_ROOT=$(cd "$script_dir/../.." 2>/dev/null && pwd -P) || REPO_ROOT=""
PAUSE_GATE="$REPO_ROOT/tickle/scripts/_lib/pause-gate.sh"
JOBS_DIR="$HOME/.claude/jobs"
NOTEBOOK_DIR="$HOME/obsidian/00-09 System/03 Agents/03.04 Records/Agent notebook"
# The frontmatter key that records a session's superior. Confirmed by [C0] obsidian, 2026-09-26,
# and carried by the Session lifecycle block of ~/.claude/CLAUDE.md. One variable, so a rename of
# the key is one line here and one line in promote-session.sh.
REPORTS_TO_KEY="reports-to"

session="" by="" why="" message="" log="$FLEET_LOG" pause_note="" dry_run=0 all_mode=0 resume_stopped=0

die() { printf 'wake-session: %s\n' "$*" >&2; exit 2; }

# A resume that landed but whose record did not must say so; the log is how the fleet sees the act.
woken_unlogged=""
on_exit() {
  rc=$?
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 3 ] && [ -n "$woken_unlogged" ]; then
    printf 'wake-session: %s was woken but its record was not appended to the log (exit %s); write it by hand\n' "$woken_unlogged" "$rc" >&2
  fi
}
trap on_exit EXIT

while [ $# -gt 0 ]; do
  case "$1" in
    --session)      [ $# -ge 2 ] || die "--session needs a value"; session="$2"; shift 2 ;;
    --by)           [ $# -ge 2 ] || die "--by needs a value"; by="$2"; shift 2 ;;
    --why)          [ $# -ge 2 ] || die "--why needs a value"; why="$2"; shift 2 ;;
    --message)      [ $# -ge 2 ] || die "--message needs a value"; message="$2"; shift 2 ;;
    --log)          [ $# -ge 2 ] || die "--log needs a value"; log="$2"; shift 2 ;;
    --notebook-dir) [ $# -ge 2 ] || die "--notebook-dir needs a value"; NOTEBOOK_DIR="$2"; shift 2 ;;
    --pause-note)   [ $# -ge 2 ] || die "--pause-note needs a value"; pause_note="$2"; shift 2 ;;
    --all)          all_mode=1; shift ;;
    --resume-stopped) resume_stopped=1; shift ;;
    --dry-run)      dry_run=1; shift ;;
    -h|--help)      awk 'NR>1 && !/^#/ {exit} NR>1 {sub(/^# ?/, ""); print}' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$by" ] || die "--by is required"
command -v jq >/dev/null     || die "jq is required"
command -v claude >/dev/null || die "the claude CLI is required"

if [ "$all_mode" = 1 ]; then
  [ -z "$session" ] || die "--all surveys every session below your rank; do not pass --session with it"
  [ "$resume_stopped" = 0 ] || [ -n "$why" ] || die "--resume-stopped needs --why: the reason goes in the log"
else
  [ -n "$session" ] || die "--session is required (or --all to survey every session below your rank)"
  [ -n "$why" ]     || die "--why is required"
  [ "$resume_stopped" = 0 ] || die "--resume-stopped belongs to --all"
fi

# --- ranks -----------------------------------------------------------------------------------
# Smaller number = higher rank. Repository variants share the rank of their base. Identical to
# promote-session.sh; the two scripts must never disagree about the rank line.
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
  # Both forms of the code: the bare `[L0]` and the ship-suffixed `[L0-CC]` / `[L0-OB]` the rank
  # files took on 2026-09-26, where CC is the Claude Code ship and OB the obsidian ship.
  case "$1" in
    "[C0]"*|"[C0-"*) echo 0 ;;
    "[C1]"*|"[C1-"*) echo 1 ;;
    "[C2]"*|"[C2-"*) echo 2 ;;
    "[L0]"*|"[L0-"*|"[L1]"*|"[L1-"*) echo 3 ;;  # [L1] was the lieutenant code until 2026-09-24
    *) echo 9 ;;
  esac
}
word_of_rank() {
  case "$1" in 0) echo captain ;; 1) echo commander ;; 2) echo "lieutenant commander" ;; 3) echo lieutenant ;; *) echo unknown ;; esac
}
# The ship a name declares, `CC` in `[L0-CC] dotfiles`; empty for a bare `[L0] dotfiles`, which is
# never guessed at — a wrong ship code puts a session in the wrong tree, and only Nelson renames.
# The known ships are CC (Claude Code), OB (obsidian) and FL (floating: a session shared across
# captains). An unknown code still groups under itself and is labelled, because a new ship must not
# make the fleet unreachable; the rank check and the reporting line are what actually gate a wake,
# and neither reads the ship. So FL needs no exception here: this script never refuses on ship.
KNOWN_SHIPS="CC OB FL"
ship_of_name() {
  printf '%s' "$1" | sed -n -E 's/^\[[A-Za-z][0-9]-([A-Za-z]{1,4})\].*/\1/p'
}
ship_is_known() {
  case " $KNOWN_SHIPS " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

by_rank=$(rank_of_name "$by")
[ "$by_rank" != 9 ] || die "--by must start with a rank code, bare or ship-coded ([C0], [C1], [C2], [L0], [L0-CC], [C2-OB] …), got '$by'"

# --- the notebook, which is where the reporting line lives ------------------------------------
# One pass over the notebook builds the whole index: for every entry whose frontmatter says
# `session-status: running`, a line of "session<TAB>reports-to<TAB>path". Read once, because a
# survey asks the same question of every session in the listing and the notebook holds hundreds of
# entries. The candidates are sorted, so for a name with more than one open entry the last line
# wins, which is the newest filename — the filenames are timestamps.
REPORT_INDEX=""
REPORT_INDEX_BUILT=0

index_awk='
function strip(s) {
  gsub(/\r/, "", s)
  sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s)
  gsub(/\t/, " ", s)   # the index is tab-separated, so a tab inside a value would split a field
  if (s ~ /^".*"$/) s = substr(s, 2, length(s) - 2)
  else if (s ~ /^\047.*\047$/) s = substr(s, 2, length(s) - 2)
  return s
}
function flush() {
  if (fname != "" && stat == "running" && sess != "") printf "%s\t%s\t%s\n", sess, rt, fname
}
FNR == 1 {
  flush()
  fname = FILENAME; sess = ""; stat = ""; rt = ""
  infm = ($0 ~ /^---[ \t\r]*$/) ? 1 : 0
  next
}
{
  if (!infm) next
  if ($0 ~ /^---[ \t\r]*$/) { infm = 0; next }
  if (match($0, "^[ \t]*session[ \t]*:[ \t]*"))             { sess = strip(substr($0, RLENGTH + 1)) }
  else if (match($0, "^[ \t]*session-status[ \t]*:[ \t]*")) { stat = strip(substr($0, RLENGTH + 1)) }
  else if (match($0, "^[ \t]*" key "[ \t]*:[ \t]*"))        { rt   = strip(substr($0, RLENGTH + 1)) }
}
END { flush() }
'

build_report_index() {
  [ "$REPORT_INDEX_BUILT" = 0 ] || return 0
  REPORT_INDEX_BUILT=1
  [ -d "$NOTEBOOK_DIR" ] || return 0
  index_files=$(grep -rl -E "^[[:space:]]*session-status[[:space:]]*:" "$NOTEBOOK_DIR" 2>/dev/null | sort || true)
  # An empty file list must never reach xargs: with no arguments awk would read stdin and hang.
  [ -n "$index_files" ] || return 0
  REPORT_INDEX=$(printf '%s\n' "$index_files" | tr '\n' '\0' | xargs -0 awk -v key="$REPORTS_TO_KEY" "$index_awk" 2>/dev/null || true)
}

# The open notebook entry of a session name, and what it says the session reports to. A name with
# more than one OPEN entry is ambiguous — a stale entry nobody closed, or two sessions sharing a
# name, which ids forbid but names do not — so the count and the paths are reported with the plan
# rather than hidden: the newest still wins, but the caller gets to see that it was a choice.
lookup_reports_to() {  # $1 = session name; sets rt_value, rt_entry, rt_count, rt_all; 1 when there is no entry
  rt_value=""
  rt_entry=""
  rt_count=0
  rt_all=""
  build_report_index
  rt_all=$(printf '%s\n' "$REPORT_INDEX" | awk -F '\t' -v n="$1" '$1 == n { print }')
  [ -n "$rt_all" ] || return 1
  rt_count=$(printf '%s\n' "$rt_all" | grep -c . || true)
  rt_line=$(printf '%s\n' "$rt_all" | tail -n 1)
  rt_value=$(printf '%s' "$rt_line" | cut -f 2)
  rt_entry=$(printf '%s' "$rt_line" | cut -f 3)
  return 0
}

# Walks `reports-to` up from the target until it reaches the caller. Sets chain_reason on refusal
# and chain_path on success. Returns 0 when the caller is somewhere up the target's line.
check_reporting_line() {  # $1 = target name, $2 = caller name
  chain_reason=""
  chain_path=""
  chain_doubt=""
  chain_cur="$1"
  chain_hops=0
  chain_seen="|$1|"
  while :; do
    chain_so_far=""
    [ -z "$chain_path" ] || chain_so_far=" (the line so far: $chain_path)"
    if ! lookup_reports_to "$chain_cur"; then
      chain_reason="no open notebook entry for '$chain_cur' under $NOTEBOOK_DIR (an entry with session: \"$chain_cur\" and session-status: running), so the line cannot be followed past it$chain_so_far; a missing record is not a permission"
      return 1
    fi
    if [ "$rt_count" -gt 1 ]; then
      chain_doubt="$chain_doubt'$chain_cur' has $rt_count open notebook entries, and the newest was taken ($rt_entry); the others: $(printf '%s\n' "$rt_all" | sed \$d | cut -f 3 | tr '\n' ' ')
"
    fi
    chain_rt="$rt_value"
    if [ -z "$chain_rt" ]; then
      chain_reason="the open notebook entry of '$chain_cur' ($rt_entry) carries no '$REPORTS_TO_KEY' key, so the line cannot be followed past it$chain_so_far; a missing record is not a permission"
      return 1
    fi
    [ -z "$chain_path" ] || chain_path="$chain_path; "
    chain_path="$chain_path$chain_cur -> $chain_rt"
    [ "$chain_rt" != "$2" ] || return 0
    chain_hops=$((chain_hops + 1))
    if [ "$chain_hops" -ge 8 ]; then
      chain_reason="the reporting line of '$1' did not reach $2 within 8 hops ($chain_path)"
      return 1
    fi
    case "$chain_rt" in
      Nelson|nelson|NELSON)
        chain_reason="'$chain_cur' reports to $chain_rt, not to $2 ($chain_path); a session outside your line is woken by its own superior or by Nelson"
        return 1 ;;
    esac
    case "$chain_seen" in
      *"|$chain_rt|"*)
        chain_reason="the reporting line of '$1' loops at '$chain_rt' ($chain_path)"
        return 1 ;;
    esac
    chain_seen="$chain_seen$chain_rt|"
    chain_cur="$chain_rt"
  done
}

# --- the pause -------------------------------------------------------------------------------
# PAUSE_NOTE is unset for the gate unless --pause-note names one on purpose: the gate reads that
# variable as a testing override, and an inherited one would quietly point the pause at the wrong
# note. The fleet's real Pause note is what an ordinary run reads, every time.
read_pause_gate() {  # sets gate_rc; the gate's own line on stderr says which note it read
  [ -x "$PAUSE_GATE" ] || die "refused: the pause gate is not at $PAUSE_GATE, so the fleet pause cannot be read"
  gate_rc=0
  if [ -n "$pause_note" ]; then
    PAUSE_NOTE="$pause_note" "$PAUSE_GATE" wake-session </dev/null || gate_rc=$?
  else
    env -u PAUSE_NOTE "$PAUSE_GATE" wake-session </dev/null || gate_rc=$?
  fi
}

check_pause() {  # refuses unless the fleet is clear
  read_pause_gate
  case "$gate_rc" in
    0) ;;
    1) die "refused: the fleet is paused; wait for Nelson to resume" ;;
    *) die "refused: the fleet pause flag cannot be read (pause-gate exit $gate_rc)" ;;
  esac
}

# A dry run touches nothing, so it refuses nothing either: it reads the flag and says what a real
# run would do with it.
report_pause() {
  read_pause_gate
  case "$gate_rc" in
    0) printf '  the pause is clear, so a real run would go ahead.\n' ;;
    1) printf '  the fleet is PAUSED, so a real run would refuse at this point.\n' ;;
    *) printf '  the pause flag cannot be read (pause-gate exit %s), so a real run would refuse at this point.\n' "$gate_rc" ;;
  esac
}

# --- the listing -----------------------------------------------------------------------------
read_listing() {
  listing=$(claude agents --json --all </dev/null 2>/dev/null) || die "claude agents --json --all failed"
  printf '%s' "$listing" | jq -e 'type == "array"' >/dev/null 2>&1 || die "could not parse claude agents --json --all"
}

# Fills row_* from one listing row. The rank of record is the agent definition in the job state;
# the name code is the fallback, for a session dispatched with no --agent.
load_row() {  # $1 = a row as JSON
  row_id=$(printf '%s' "$1" | jq -r '.id // ""')
  row_session_id=$(printf '%s' "$1" | jq -r '.sessionId // ""')
  row_name=$(printf '%s' "$1" | jq -r '.name // ""')
  row_cwd=$(printf '%s' "$1" | jq -r '.cwd // ""')
  row_pid=$(printf '%s' "$1" | jq -r '.pid // empty')
  row_status=$(printf '%s' "$1" | jq -r '.status // ""')
  row_agent=$(jq -r '.template // "bg"' "$JOBS_DIR/$row_id/state.json" 2>/dev/null || echo bg)
  row_rank=$(rank_of_agent "$row_agent")
  if [ "$row_rank" = 9 ] || [ "$row_agent" = bg ]; then row_rank=$(rank_of_name "$row_name"); fi
  row_alive=0
  if [ -n "$row_pid" ] && kill -0 "$row_pid" 2>/dev/null; then row_alive=1; fi
}

default_message_for() {  # $1 = target name
  printf '%s' "You are woken by $by: $why. This is your own session continuing under its own id, not a new one, so everything you had is still here. If a write of yours was refused because the fleet was paused, try that write again: the pause was read before this wake, and the gate answers honestly every time. Read the cross-session log delta from the position your notebook entry records, give every new entry a disposition, then carry on where you stopped. When you have something, report to $by by SendMessage; if nothing is left to do, say that instead, complete your notebook entry and stop."
}

# jq -Rs quotes and escapes the whole string, quotes included, so a message carrying a quote, a
# backslash or a newline still prints as a SendMessage the caller can paste as it stands.
print_sendmessage() {  # $1 = target name, $2 = message
  printf '  a live session is reached only by a Claude session'\''s own SendMessage tool, so send this yourself:\n\n'
  printf '    SendMessage({to: %s, message: %s})\n\n' \
    "$(printf '%s' "$1" | jq -Rs .)" "$(printf '%s' "$2" | jq -Rs .)"
}

# --- waking a stopped session ----------------------------------------------------------------
# A flagless resume, from the target's own cwd, verified afterwards: the SAME id must be running
# and no new id may have appeared, because a new id means the resume forked a copy instead.
wake_stopped() {  # uses row_*; $1 = the message
  wake_message="$1"
  [ -d "$row_cwd" ] || die "the session's cwd '$row_cwd' does not exist; the resume must run there"
  # </dev/null so the resume cannot eat the heredoc the --all loop is reading from.
  out=$(cd "$row_cwd" && claude --bg --resume "$row_session_id" "$wake_message" </dev/null 2>&1) || die "claude --bg --resume failed: $out"
  woken_unlogged="$row_id"

  # Did it continue the session, or fork a copy? The CLI says so in its own words — "started a copy
  # as <id>" when it still held the session as running, and the id it backgrounded either way. A
  # copy is this script's own doing, so it stops the copy before refusing, rather than leaving a
  # second session running, which is the very hazard the live path exists to avoid.
  out_clean=$(printf '%s' "$out" | tr -d '\r' | sed -E $'s/\x1b\\[[0-9;?]*[A-Za-z]//g')
  copy_id=$(printf '%s\n' "$out_clean" | sed -n -E 's/.*started a copy as ([0-9a-f]{6,}).*/\1/p' | head -n 1)
  bg_id=$(printf '%s\n' "$out_clean" | awk '/^backgrounded/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9a-f]{6,}$/) { print $i; exit } }')
  forked_id="$copy_id"
  if [ -z "$forked_id" ] && [ -n "$bg_id" ] && [ "$bg_id" != "$row_id" ]; then forked_id="$bg_id"; fi
  if [ -n "$forked_id" ]; then
    woken_unlogged=""
    stop_note="the copy was stopped by this script"
    claude stop "$forked_id" >/dev/null 2>&1 || stop_note="the copy could NOT be stopped; stop $forked_id yourself"
    die "the resume of $row_id started a copy ($forked_id) instead of continuing it, which means Claude Code still held $row_id as running; $stop_note, nothing was logged, and $row_id was not woken. Check the target with 'claude agents --json --all' and reach a live one by SendMessage instead. Resume output: $out"
  fi

  waited=0
  while :; do
    verify_row=$(printf '%s' "$listing" | jq -c --arg s "$row_id" '[.[] | select(.id==$s)] | first // empty')
    verify_pid=$(printf '%s' "$verify_row" | jq -r '.pid // empty' 2>/dev/null || true)
    [ -z "$verify_pid" ] || break
    waited=$((waited + 1))
    if [ "$waited" -ge 20 ]; then
      woken_unlogged=""
      die "$row_id did not come up within 20 s of the resume (no pid in the listing); nothing was logged. Resume output: $out"
    fi
    sleep 1
    read_listing
  done

  stamp=$(date '+%Y-%m-%dT%H:%M')
  cat <<EOF >> "$log"

## $stamp · $by — woke \`$row_name\` ($row_id), which was stopped, and it continues under the same id

$by woke the stopped session \`$row_name\` (background id $row_id, agent \`$row_agent\`, $(word_of_rank "$row_rank")) with a flagless \`claude --bg --resume $row_session_id\` from its own cwd \`$row_cwd\`, so the conversation continues under the same id and nothing was forked; verified from \`claude agents --json --all\` after the resume, where $row_id is running again and no new id appeared. Why: $why. The session was told it is continuing, that a write the pause refused can be tried again, to read the log delta from its recorded position and to report back to $by. Posted by \`wake-session.sh\` on behalf of $by, who attests its own log position in its own entries. — $by
EOF
  woken_unlogged=""
  printf 'done: %s (%s) is running again under the same id; pid %s; record appended to %s\n' "$row_name" "$row_id" "$verify_pid" "$log"
}

# --- mode: one target ------------------------------------------------------------------------
if [ "$all_mode" = 0 ]; then
  read_listing
  row=$(printf '%s' "$listing" | jq -c --arg s "$session" '[.[] | select(.id==$s or .sessionId==$s)] | first // empty') \
    || die "could not parse claude agents --json --all"
  [ -n "$row" ] || die "no background session with id or sessionId '$session' in claude agents --json --all"
  load_row "$row"

  [ "$row_name" != "$by" ] || die "refused: '$session' is $by itself; a session does not wake itself"
  [ "$row_rank" != 9 ] || die "cannot tell the target's rank from its agent ('$row_agent') or its name ('$row_name'); refusing rather than guessing"
  [ "$row_rank" != 0 ] || die "refused: \`$row_name\` is a captain; only Nelson wakes a captain, and this script cannot verify that it is Nelson calling"
  [ "$row_rank" -gt "$by_rank" ] \
    || die "refused: $by ($(word_of_rank "$by_rank")) may only wake a session below its own rank; \`$row_name\` is a $(word_of_rank "$row_rank")"

  if ! check_reporting_line "$row_name" "$by"; then
    die "refused: \`$row_name\` is not in $by's reporting line — $chain_reason"
  fi

  # A dry run reads the flag and reports it; a real run is refused by it. Composing a wake for a live
  # target is not exempt: handing the caller the message is the wake, one keystroke short, and a
  # pause is Nelson saying that nobody gets woken.
  [ "$dry_run" = 1 ] || check_pause

  [ -n "$message" ] || message=$(default_message_for "$row_name")

  printf 'wake: %s (%s, %s, %s) in %s\n' "$row_name" "$row_id" "$row_agent" "$(word_of_rank "$row_rank")" "$row_cwd"
  printf '  by %s: %s\n  reporting line: %s\n' "$by" "$why" "$chain_path"
  [ -z "$chain_doubt" ] || printf '%s' "$chain_doubt" | sed 's/^/  ambiguous: /'

  if [ "$row_alive" = 1 ]; then
    printf '  it is ALIVE (pid %s, %s), so it is NOT resumed: a resume of a running session forks a copy.\n' "$row_pid" "${row_status:-status unknown}"
    print_sendmessage "$row_name" "$message"
    [ "$dry_run" = 0 ] || report_pause
    printf '  nothing was touched; no record was written, because nothing happened yet.\n'
    exit 3
  fi

  if [ -n "$row_pid" ]; then
    printf '  the listing still shows pid %s but that process is gone, so the session is stopped.\n' "$row_pid"
  fi
  printf '  it is STOPPED, so a flagless resume continues it under the same id.\n'
  if [ "$dry_run" = 1 ]; then
    report_pause
    printf '  dry run: nothing touched\n'
    exit 0
  fi
  wake_stopped "$message"
  exit 0
fi

# --- mode: survey everything below the caller ------------------------------------------------
# The survey itself is a read, and a pause never gates a read; the pause is checked below, before
# anything is actually resumed.
read_listing

if [ "$by_rank" -ge 3 ]; then
  printf 'nothing to survey: %s is a %s, and below a lieutenant there is only the ensign, which is not a session.\n' "$by" "$(word_of_rank "$by_rank")"
  exit 0
fi

TAB=$(printf '\t')
survey_rows="" outside_list="" unknown_list="" stopped_rows=""
rows=$(printf '%s' "$listing" | jq -c '.[]')
while IFS= read -r one_row; do
  [ -n "$one_row" ] || continue
  load_row "$one_row"
  [ "$row_name" != "$by" ] || continue
  if [ "$row_rank" = 9 ]; then
    unknown_list="$unknown_list    $row_id  $row_name (agent '$row_agent'; no rank code in the name)
"
    continue
  fi
  [ "$row_rank" != 0 ] || continue
  [ "$row_rank" -gt "$by_rank" ] || continue
  if ! check_reporting_line "$row_name" "$by"; then
    outside_list="$outside_list    $row_id  $row_name — $chain_reason
"
    continue
  fi
  if [ "$row_alive" = 1 ]; then
    if [ "$row_status" = idle ]; then row_state=idle; else row_state=busy; fi
    row_display="$row_id  $row_name ($(word_of_rank "$row_rank"), pid $row_pid, ${row_status:-status unknown}) in $row_cwd"
  else
    row_state=stopped
    row_display="$row_id  $row_name ($(word_of_rank "$row_rank")) in $row_cwd"
    stopped_rows="$stopped_rows$one_row
"
  fi
  survey_rows="$survey_rows$(ship_of_name "$row_name")$TAB$row_state$TAB$row_display
"
done <<EOF
$rows
EOF

print_state_group() {  # $1 = ship code ("" for a bare name), $2 = state, $3 = heading
  printf '  %s\n' "$3"
  state_group=$(printf '%s\n' "$survey_rows" | awk -F "$TAB" -v s="$1" -v st="$2" 'NF >= 3 && $1 == s && $2 == st { print "    " $3 }')
  if [ -n "$state_group" ]; then printf '%s\n' "$state_group"; else printf '    (none)\n'; fi
}

print_ship_block() {  # $1 = ship code ("" for a bare name), $2 = the heading for the block
  printf '\n%s\n' "$2"
  print_state_group "$1" idle    'ALIVE AND IDLE — needs a SendMessage; a CLI cannot reach a live session:'
  print_state_group "$1" busy    'ALIVE AND BUSY — leave them alone; they are working:'
  print_state_group "$1" stopped 'STOPPED — a flagless resume continues each under its own id:'
}

by_ship=$(ship_of_name "$by")
printf 'survey by %s (%s%s): every session below its rank, from claude agents --json --all\n' \
  "$by" "$(word_of_rank "$by_rank")" "$( [ -n "$by_ship" ] && printf ', ship %s' "$by_ship" || printf ', no ship code' )"

ships=$(printf '%s\n' "$survey_rows" | awk -F "$TAB" 'NF >= 3 && $1 != "" { print $1 }' | sort -u)
if [ -n "$ships" ]; then
  while IFS= read -r one_ship; do
    [ -n "$one_ship" ] || continue
    if ship_is_known "$one_ship"; then
      print_ship_block "$one_ship" "SHIP $one_ship"
    else
      print_ship_block "$one_ship" "SHIP $one_ship — not one of the known ships ($KNOWN_SHIPS); listed as the name spells it"
    fi
  done <<EOF
$ships
EOF
fi
bare_rows=$(printf '%s\n' "$survey_rows" | awk -F "$TAB" 'NF >= 3 && $1 == "" { print }')
if [ -n "$bare_rows" ]; then
  print_ship_block "" "NO SHIP CODE — these names carry only a rank code, and the ship is not guessed"
fi
if [ -z "$ships" ] && [ -z "$bare_rows" ]; then
  printf '\n  (no session below your rank is in your reporting line)\n'
fi

if [ -n "$outside_list" ]; then
  printf '\nNOT IN YOUR LINE — never woken or messaged by you:\n%s' "$outside_list"
fi
if [ -n "$unknown_list" ]; then
  printf '\nRANK UNKNOWN — skipped rather than guessed:\n%s' "$unknown_list"
fi

if [ -z "$stopped_rows" ]; then
  printf '\nnothing stopped in your line, so there is nothing to resume.\n'
  exit 0
fi

if [ "$resume_stopped" = 0 ]; then
  printf '\nto resume every stopped session above, run the same command with --resume-stopped --why "<reason>";\n'
  printf 'to wake one of them only, run: %s --session <id> --by "%s" --why "<reason>"\n' "$(basename "$0")" "$by"
  exit 0
fi

if [ "$dry_run" = 1 ]; then
  printf '\n'
  report_pause
  printf 'dry run: the stopped sessions above would be resumed, one log entry each; nothing touched\n'
  exit 0
fi

check_pause

# The survey above is a snapshot, and a sweep takes seconds per session, so each target's state is
# read again from a fresh listing immediately before its own resume: one that somebody else started
# in the meantime is left alone rather than resumed into a copy.
printf '\nresuming every stopped session above:\n'
while IFS= read -r one_row; do
  [ -n "$one_row" ] || continue
  load_row "$one_row"
  sweep_id="$row_id"
  read_listing
  sweep_row=$(printf '%s' "$listing" | jq -c --arg s "$sweep_id" '[.[] | select(.id==$s)] | first // empty')
  if [ -z "$sweep_row" ]; then
    printf '  skipped %s: it is no longer in the listing\n' "$sweep_id"
    continue
  fi
  load_row "$sweep_row"
  if [ "$row_alive" = 1 ]; then
    printf '  skipped %s (%s): it is running again now (pid %s), so it needs a SendMessage, not a resume\n' "$row_id" "$row_name" "$row_pid"
    continue
  fi
  one_message="$message"
  [ -n "$one_message" ] || one_message=$(default_message_for "$row_name")
  wake_stopped "$one_message"
done <<EOF
$stopped_rows
EOF
exit 0
