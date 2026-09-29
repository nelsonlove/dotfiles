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
#   * `claude stop` returns before the process is gone, and the pid leaves the listing before Claude
#     Code stops holding the session as running, so a wake issued in those first seconds forks a copy
#     even though the listing says stopped. The script confirms the row three times, a second apart,
#     before resuming, and the check after the resume is the real guard. (The promotion note recorded the first half of
#     this on 2026-09-22: "claude stop returns before the process has exited, so a script must wait
#     on the pid".)
#   * THE TRAP, and the reason this script always passes the FULL sessionId: `claude --bg --resume`
#     given the short background id starts a NEW session instead of continuing the old one. Measured
#     on 2026-09-26: `[C0-OB] obsidian` resumed by hand with the short id and got a new id that died,
#     while the same wake given the full sessionId continued `[C1-CC] memories` under its own id and
#     it acted on the brief. So `--session` takes either form, resolves the row from the listing, and
#     the resume only ever uses `.sessionId`; an empty or malformed sessionId is refused rather than
#     passed, because `--resume ""` silently starts a new session with the message as its prompt.
#
# Usage:
#   wake-session.sh --session <id|sessionId> --by "<your session name>" --why "<reason>" \
#       [--message "<text>"] [--log <path>] [--notebook-dir <path>] [--archive-dir <path>] [--dry-run]
#   wake-session.sh --all --by "<your session name>" [--resume-stopped --why "<reason>"] \
#       [--log <path>] [--notebook-dir <path>] [--archive-dir <path>] [--dry-run]
#
#   --session  the target's background id or sessionId, as `claude agents --json --all` lists it.
#              Either form is accepted and resolved to the full sessionId, which is the only value
#              the resume is ever given: see THE TRAP below.
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
#   --archive-dir   where ended notebook entries live (default: `03 Agents/03.09 Archive/Agent notebook`). For testing only.
#   --agents-dir    the `03 Agents` folder both default roots are found under. For testing only.
#   --jobs-dir  where Claude Code's job state lives, which is where a target's RANK is read from
#              (`<id>/state.json`, key `template`, through the rank definitions). For testing only, and
#              REFUSED unless it resolves under /tmp or the system temp directory — see the leash below. It
#              is the flag that lets a battery exercise the captain gate without dispatching a captain or
#              naming a throwaway as one: the row comes from the real listing, the rank from a stub.
#   --pause-note  the Pause note the gate reads. For testing only; an ordinary run reads the fleet's
#              own note, and PAUSE_NOTE is deliberately NOT inherited from the environment.
#   --dry-run  print the plan and touch nothing.
#   -h, --help  print this header.
#
# Exit codes: 0 done; 2 refused or failed; 3 the target is alive, so SendMessage it (the command is
# printed) — nothing was touched.
#
# The admiral rank, `[A0]`, rank -1: first the rear admiral Nelson placed between himself and the captains on 2026-09-26, a rank of its own since 2026-09-29, held by `[A0] rear admiral` and `[A0] areas admiral`. The table is numbered rather than shifted so C0..L0 keep their numbers in both scripts (`_fleet-ranks.sh` is where a renumbering belongs). An admiral may wake any rank below a captain and a captain too, because captains report to it, but only on its own ships: `ship_refusal` in the table keeps each admiral to its ships and refuses DV for every caller. Any other `[A0] …` name is refused, and a ship-coded `[A0-CC]` is not an admiral at all. `[A0]` is never a target this script would be asked for, since an admiral outranks every caller it could have.
#
# What it refuses, and why:
#   * A target at or above the caller's rank, and a `[C0]` target for every caller but an admiral: only Nelson or an admiral wakes a captain, and the script cannot verify that it is Nelson.
#   * The ship rule, from the table (`ship_refusal`): a target on DV (80-89 Divorce), for every caller, because only Nelson starts a session there; and a target outside the calling admiral's own ships (`[A0] rear admiral`: CC, OB, HS, MA, FL and bare names; `[A0] areas admiral`: the area ships). A survey leaves such rows out.
#   * An `[A0] …` caller that is not one of the two admirals, and a target that reads as rank -1 but is not one of them (an `[A0]` name, or the admiral definition under another name).
#   * `--all` from the accept verbs' write path (rank -2). That caller sits above every rank, so a survey
#     would list the whole fleet and `--resume-stopped` would resume it; the verb needs one named session at
#     a time, and a mass resume belongs to a rank that answers for it.
#   * A target outside the caller's reporting line. The line is data: each session's notebook entry
#     carries `reports-to`, the name of the session that dispatched it (or `Nelson` for a captain),
#     and this script walks that chain up from the target, reading the most recent entry for each
#     name whatever its status — `ended` is the normal state of a session worth waking. A
#     target with no notebook entry at all, or whose newest entry has no `reports-to`, is refused: a
#     missing record is not a permission.
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
# One known gap inside that: the reporting line is keyed by DISPLAY NAME, because that is what the
# notebook records, so two sessions sharing a name share a line and the newest entry decides for both.
# The session that is actually resumed is always picked by its unique id, never by name, so a
# collision can misjudge permission but can never resume the wrong session.
# Five flags widen them on purpose, for tests: `--notebook-dir` and `--archive-dir` replace the reporting-line record,
# `--pause-note` replaces the pause flag, `--jobs-dir` replaces the job state a target's rank is read from,
# and `--log` sends the record somewhere other than the fleet log. A run that passes any of them is a test, not a fleet act — say so if you use them.
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
# TWO ROOTS, ruled 2026-09-29: a notebook entry that has ENDED moves out of the notebook into the agents
# archive, while running entries stay in the notebook. A stopped session's entry — and its superiors' entries,
# for the reporting line — is therefore usually an ended one, so the index reads BOTH roots or it refuses every
# stopped session after the move. The roots are exactly two, narrowed on Nelson's word on #69 ("narrow it":
# other folders in 03.09 hold other archived things): `03 Agents/03.04 Records/Agent notebook/` and
# `03 Agents/03.09 Archive/Agent notebook/`. Under each, only `<root>/YYYY-MM/Agent session *.md` is read —
# one month folder down, no deeper. Which entry wins is unchanged: the newest by the timestamp in the
# filename, wherever it sits. `--archive-dir` replaces the archive root for tests, `--agents-dir` moves the
# parent both defaults are found under, and `--notebook-dir` without `--archive-dir` reads no archive at all,
# so a test stays sealed.
AGENTS_DIR="$HOME/obsidian/00-09 System/03 Agents"
ARCHIVE_DIR=""   # derived from AGENTS_DIR after the flags are read, unless --archive-dir gives it
ARCHIVE_DIR_SET=0
NOTEBOOK_DIR_SET=0
AGENTS_DIR_SET=0
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

# THE LEASH ON `--jobs-dir`, put on it by the captain on 2026-09-27 when the flag landed. The flag says where
# a TARGET'S RANK is read from, and rank decides reach, so a flag that moves it must not be usable to dress
# an ordinary session up as something else in a real run. The leash: the path must resolve, with symlinks
# followed, to somewhere under /tmp or the system temp directory — the only places a battery writes.
#
# WHY A LEASH AND NOT A REFUSAL OUTRIGHT. The flag adds no authority it did not already have: `--by` is a
# string the caller supplies, so anyone who can pass `--jobs-dir` can already claim any rank they like, and
# anyone holding a shell can skip both scripts entirely. What the flag buys is a real test of the ONE gate
# nobody could otherwise exercise — the captain gate, which needs a captain-ranked target, which needs a
# session dispatched `--agent captain`, which is a captain in the fleet view and is exactly what the fixture
# rule forbids. So it stays, and it stays pointed at a temp directory.
check_jobs_dir() {  # $1 = the path as given; prints the resolved path, or dies
  jd_real=$(cd "$1" 2>/dev/null && pwd -P) || jd_real=""
  [ -n "$jd_real" ] || die "--jobs-dir must name a directory that exists; got '$1'"
  case "$jd_real" in
    /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) printf '%s' "$jd_real"; return 0 ;;
  esac
  if [ -n "${TMPDIR:-}" ]; then
    jd_tmp=$(cd "$TMPDIR" 2>/dev/null && pwd -P) || jd_tmp=""
    if [ -n "$jd_tmp" ]; then
      case "$jd_real" in
        "$jd_tmp"/*) printf '%s' "$jd_real"; return 0 ;;
      esac
    fi
  fi
  die "refused: --jobs-dir is test-only and must be under /tmp or the system temp directory; '$1' resolves to '$jd_real', which is neither"
}
trap on_exit EXIT

while [ $# -gt 0 ]; do
  case "$1" in
    --session)      [ $# -ge 2 ] || die "--session needs a value"; session="$2"; shift 2 ;;
    --by)           [ $# -ge 2 ] || die "--by needs a value"; by="$2"; shift 2 ;;
    --why)          [ $# -ge 2 ] || die "--why needs a value"; why="$2"; shift 2 ;;
    --message)      [ $# -ge 2 ] || die "--message needs a value"; message="$2"; shift 2 ;;
    --log)          [ $# -ge 2 ] || die "--log needs a value"; log="$2"; shift 2 ;;
    --notebook-dir) [ $# -ge 2 ] && [ -n "$2" ] || die "--notebook-dir needs a path"; NOTEBOOK_DIR="$2"; NOTEBOOK_DIR_SET=1; shift 2 ;;
    --archive-dir) [ $# -ge 2 ] && [ -n "$2" ] || die "--archive-dir needs a path"; ARCHIVE_DIR="$2"; ARCHIVE_DIR_SET=1; shift 2 ;;
    --agents-dir)  [ $# -ge 2 ] && [ -n "$2" ] || die "--agents-dir needs a path"; AGENTS_DIR="$2"; AGENTS_DIR_SET=1; shift 2 ;;
    --jobs-dir) [ $# -ge 2 ] && [ -n "$2" ] || die "--jobs-dir needs a path"; JOBS_DIR=$(check_jobs_dir "$2"); shift 2 ;;
    --pause-note)   [ $# -ge 2 ] && [ -n "$2" ] || die "--pause-note needs a path"; pause_note="$2"; shift 2 ;;
    --all)          all_mode=1; shift ;;
    --resume-stopped) resume_stopped=1; shift ;;
    --dry-run)      dry_run=1; shift ;;
    -h|--help)      awk 'NR>1 && !/^#/ {exit} NR>1 {sub(/^# ?/, ""); print}' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

# --agents-dir moves the parent both default roots are found under; an explicit --notebook-dir still wins.
# THE TWO NOTEBOOK ROOTS, from one definition. Guarded the three ways #61 ruled — readable, parses, defines
# what is wanted — because a roots library that silently defined nothing would leave this script reading NO
# notebook at all and refusing every wake for a missing record, which is a lie about the record rather than a
# failure to find it.
NOTEBOOK_ROOTS_LIB="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)/../lib/notebook-roots.sh"
[ -r "$NOTEBOOK_ROOTS_LIB" ] || die "the notebook-roots library is missing or unreadable at $NOTEBOOK_ROOTS_LIB"
bash -n "$NOTEBOOK_ROOTS_LIB" 2>/dev/null || die "the notebook-roots library at $NOTEBOOK_ROOTS_LIB does not parse; refusing rather than reading half a notebook"
# shellcheck source=../lib/notebook-roots.sh
. "$NOTEBOOK_ROOTS_LIB" || die "the notebook-roots library at $NOTEBOOK_ROOTS_LIB could not be sourced"
for fn in notebook_roots_of entries_in_root notebook_dir_for archive_dir_for; do
  command -v "$fn" >/dev/null 2>&1 || die "the notebook-roots library at $NOTEBOOK_ROOTS_LIB parsed but defined no $fn; refusing"
done

# THE DEFAULTS ARE DERIVED BY THE LIBRARY, after the flags are read, so the paths live in exactly one place.
# `--agents-dir` moves the parent both come from; an explicit `--notebook-dir` still wins; `--archive-dir`
# wins for the archive. Deriving here as well would be a second home for the same two strings.
NOTEBOOK_DIR=$(notebook_dir_for "$AGENTS_DIR" "$NOTEBOOK_DIR" "$NOTEBOOK_DIR_SET" "$AGENTS_DIR_SET")
ARCHIVE_DIR=$(archive_dir_for "$AGENTS_DIR" "$ARCHIVE_DIR" "$ARCHIVE_DIR_SET")

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

# --- ranks and ships, from the one table ------------------------------------------------------
# `_fleet-ranks.sh` beside this script holds the rank line and the ship codes: `rank_of_name`,
# `rank_of_caller`, `rank_of_agent`, `word_of_rank`, `bare_code_of_rank`, `code_of_rank`, `KNOWN_SHIPS`,
# `FLOATING_SHIP`, `ship_of_name`, `ship_is_known`, `ships_in_words`, and the admirals' and guarded ships with `ship_is_guarded` and `ship_refusal`. Both this script and its sibling held byte-identical
# copies of most of those, and copies of `rank_of_name` that differed in the comment only — the rank line
# is the one thing two fleet scripts must never disagree about, so it is one file now. Adding a ship code
# is one line THERE, not here.
#
# Sourced by path beside this script, resolved with `pwd -P`, so it works from the repo and through the
# `~/.claude/bin` symlink the installer makes. A missing or unreadable table is fatal: every rank check in
# this script depends on it, and a script that cannot read the rank line must not act on a rank.
FLEET_RANKS="$script_dir/_fleet-ranks.sh"

[ -r "$FLEET_RANKS" ] || die "the rank table is missing or unreadable at $FLEET_RANKS; this script cannot judge a rank without it"
# PARSED BEFORE IT IS SOURCED, and the `|| die` after the `.` is not enough on its own. Under `set -e` a
# SYNTAX ERROR in a sourced file aborts this script before the `||` is ever reached, the EXIT trap is
# entered with a zero status, and `on_exit` does not re-exit — so the script exited 0, which its own header
# documents as "done", having done nothing. An unresolved merge conflict in the table produces exactly
# that, and this file is where a rank gets added, so it is the realistic shape rather than a contrived one.
# Found by the review of #61; the failure did not exist before the extraction, because nothing was sourced.
bash -n "$FLEET_RANKS" 2>/dev/null || die "the rank table at $FLEET_RANKS does not parse (an unresolved merge conflict, or a truncated file); refusing, because a script that cannot read the rank line must not act on a rank"
# shellcheck source=_fleet-ranks.sh
. "$FLEET_RANKS" || die "the rank table at $FLEET_RANKS could not be sourced"
# AND THAT IT DEFINED WHAT IT PROMISES: a table that parses but defines nothing left the script to fail
# later with 127, not with a refusal. One probe is enough — they all come from the same file.
command -v rank_of_name >/dev/null 2>&1 || die "the rank table at $FLEET_RANKS parsed but defined no rank line; refusing"

by_rank=$(rank_of_caller "$by")
[ "$by_rank" != 9 ] || die "--by must start with a rank code, bare or ship-coded ([C0], [C1], [C2], [L0], [L0-CC], [C2-OB] …), or the bare [A0], which carries no ship code; got '$by'"
# An admiral is matched by its FULL NAME: any other `[A0] …` name is refused here, before a single target or a survey (the table's `ship_refusal` says why, in its words).
if [ "$by_rank" = -1 ]; then
  is_admiral "$by" || die "$(admiral_name_refusal "$by")"
fi

# THE WRITE PATH TELLS ONE SESSION AT A TIME. `human:nelson` is rank -2, which is above every rank in the
# fleet, so without this line `--all` would list every session including the captains and the admirals,
# and `--all --resume-stopped` would RESUME THEM ALL — from a `--by` string that nothing authenticates, in one
# command, where the same string was refused outright before package 5 existed. That is not what the verb
# needs: `notify-session.sh` addresses exactly the session a note names, or that ship's captain, one at a
# time. The survey and the mass resume stay with the ranks, who answer for them.
#
# Found by the review of #63, which is the second time in this package that widening ONE gate for this caller
# turned out to widen a road nobody was looking at. The lesson is written here rather than in a report: when a
# rank is added below every existing one, every `-gt`, `-lt` and `!=` that mentions a rank is a site to read,
# not just the one the feature needed.
if [ "$all_mode" = 1 ] && [ "$by_rank" -lt -1 ]; then
  die "refused: '$by' is the accept verbs' write path; it tells one session at a time, and the survey and the mass resume belong to the ranks who answer for them"
fi

# --- the notebook, which is where the reporting line lives ------------------------------------
# One pass over the notebook builds the whole index: for every entry that names a `session:`, a line
# of "session<TAB>reports-to<TAB>path<TAB>status word<TAB>stamp". Read once, because a survey asks
# the same question of every session in the listing and the notebook holds hundreds of entries.
#
# THE STATUS IS READ FROM EITHER KEY until 2026-10-04 — `session-status: running|ended` or `status:
# draft/running|archived/ended` — because the notebook's status machine is folding into the vault's, ruled by
# Nelson through `[A0] rear admiral` on 2026-09-27. The rule, the five state words and the expiry live in
# `claude/lib/session-status.sh`; the `awk` below carries a copy of the rule because it reads the whole
# notebook in one pass, and it says so where it does.
#
# The status is recorded but NEVER required. The first version of this script read the key only
# from an entry that said `running`, which refused every session it exists to wake: under the
# lifecycle rule a session completes its entry and sets `ended` as its last write before it stops, so
# `ended` is the normal state of a wakeable session. Found in the field on `[C2-OB] fileclasses`,
# which had to be woken by hand. Whether a session is alive is read from its process, not from this
# record, so nothing is lost by trusting the record only for the reporting line.
#
# The most recent entry for a name wins, because a name recurs across days. Most recent means by the
# timestamp in the filename, and both forms the notebook holds are counted: the plain
# `Agent session 2026-09-26T1600.md` and the titled form the archivist writes,
# `Agent session 2026-09-26T1500 — some title.md`. An entry whose filename carries no timestamp
# sorts below every stamped one and is used only when nothing else matches.
REPORT_INDEX=""
REPORT_INDEX_BUILT=0

index_awk='
function strip(s) {
  gsub(/\r/, "", s)
  sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s)
  # THE COMMENT COMES OFF BEFORE THE QUOTES, and the order is the whole of it. The fix-forward added this strip
  # to this program and to `claude/lib/session-status.sh` in DIFFERENT positions, so on a quoted value carrying
  # a comment the quote test below ran with the comment still attached and failed, and a `#` inside quotes had
  # the quotes taken off first and part of the value eaten. Six inputs disagreed between the two readers, and
  # no fixture combined a quote with a comment, so the agreement check could not see one of them. The order in
  # claude/lib/session-status.sh is the correct one and this matches it: comment, then whitespace, then quotes.
  #
  # AND NO APOSTROPHE IN THIS BLOCK, ever: it sits in a single-quoted shell string, so one ends the string and
  # the shell parses awk source as commands. That has happened twice in one evening, both times in a careful
  # comment, so the suite now fails on a literal apostrophe anywhere in this program.
  sub(/[ \t]+#.*$/, "", s)
  sub(/[ \t]+$/, "", s)
  gsub(/\t/, " ", s)   # the index is tab-separated, so a tab inside a value would split a field
  if (s ~ /^".*"$/) s = substr(s, 2, length(s) - 2)
  else if (s ~ /^\047.*\047$/) s = substr(s, 2, length(s) - 2)
  return s
}
function stamp_of(path) {
  # The timestamp in the filename, from either form: "Agent session 2026-09-26T1600.md" and
  # "Agent session 2026-09-26T1500 — a title.md" both give 2026-09-26T1500. Empty when there is none,
  # which sorts below every stamped entry because the digits all sort above "".
  base = path
  sub(/^.*\//, "", base)
  if (match(base, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9][0-9][0-9]/)) {
    return substr(base, RSTART, RLENGTH)
  }
  return ""
}
# THE SAME DUAL-READ RULE AS `claude/lib/session-status.sh`, and that file is the AUTHORITY: the five state
# words, the two keys, the disagreement rule and the 2026-10-04 expiry are written there and only summarised
# here. This program cannot source it — it indexes the whole notebook in ONE pass, and a shell function per
# file would turn a survey into hundreds of processes — so it carries the rule and names where the rule lives,
# which is what stops the pair drifting the way the two pause-parser copies did before #61.
#
# NO APOSTROPHES IN THIS BLOCK. It sits inside a single-quoted awk program, so one apostrophe closes the quote
# and the shell parses awk source as commands; the first version of this comment did exactly that.
#
# Nothing in this script GATES on the word: the status was always recorded and never required, because an
# `ended` entry is the normal state of a session worth waking. It reaches the refusal messages and the
# ambiguity note, where saying `conflict` rather than a value that was quietly picked is the whole point.
function state_word() {
  o = ""; n = ""
  if (old_stat == "running" || old_stat == "draft/running") o = "running"
  else if (old_stat == "ended" || old_stat == "archived/ended") o = "ended"
  else if (old_stat != "") o = "other"
  # THE ASYMMETRY, and the library says why at length: `status` is the vault-wide note key, so ONLY these two
  # values are session claims and every other value is not ours to read. `session-status` is ours alone, so
  # anything unrecognised there is a malformed session status. Reading a bare `status: draft` as a claim made
  # seven live entries conflict and killed the renamer for every session, which the review of #65 caught.
  if (new_stat == "draft/running") n = "running"
  else if (new_stat == "archived/ended") n = "ended"
  # A MALFORMED VALUE ON OUR KEY IS NOT A CLAIM, so it cannot disagree with a real one: the claim wins. The
  # library says the same and says why at length; this arm exists because the two were fixed separately and the
  # suite caught the difference on its first run with a fixture for it.
  if (o == "other" && n != "") return n
  if (o != "" && n != "") { if (o == n) return o; else return "conflict" }
  if (n != "") return n
  if (o != "") return o
  return "absent"
}
function flush() {
  # No test on stat: an ended entry is the normal state of a session that can be woken.
  if (fname != "" && sess != "") printf "%s\t%s\t%s\t%s\t%s\n", sess, rt, fname, state_word(), stamp_of(fname)
}
FNR == 1 {
  flush()
  fname = FILENAME; sess = ""; old_stat = ""; new_stat = ""; rt = ""
  infm = ($0 ~ /^---[ \t\r]*$/) ? 1 : 0
  next
}
{
  if (!infm) next
  if ($0 ~ /^---[ \t\r]*$/) { infm = 0; next }
  # COLUMN ZERO, ALL FOUR. These matched a key at ANY indentation and took the last, so a key nested under a
  # parent mapping beat the record own top-level one. For `status` that was a wrong word in a message. For
  # `reports-to` it was a PERMISSION: that key is what `check_reporting_line` walks, so an entry stating
  # `reports-to: [C1-CC] plugins` at column zero and carrying an indented `reports-to: [C0-CC] claude code`
  # under some other block handed the chain to a caller the record does not name, and the wake was allowed.
  # Measured before changing: of 495 entries across both roots, zero carry any of these four keys indented,
  # so nothing real reads differently. `claude/lib/session-status.sh` was anchored in the seventh review
  # round and this copy was not, which is the same pair-drift this program own comment warns about.
  if (match($0, "^session[ \t]*:[ \t]*"))             { sess = strip(substr($0, RLENGTH + 1)) }
  else if (match($0, "^session-status[ \t]*:[ \t]*")) { old_stat = strip(substr($0, RLENGTH + 1)) }
  else if (match($0, "^status[ \t]*:[ \t]*"))         { new_stat = strip(substr($0, RLENGTH + 1)) }
  else if (match($0, "^" key "[ \t]*:[ \t]*"))        { rt   = strip(substr($0, RLENGTH + 1)) }
}
END { flush() }
'

# The roots the index reads, one per line: the notebook, then the archive. With `--notebook-dir` and no
# `--archive-dir`, the notebook alone.
notebook_roots() {
  notebook_roots_of "$NOTEBOOK_DIR" "$NOTEBOOK_DIR_SET" "$ARCHIVE_DIR" "$ARCHIVE_DIR_SET"
}

# The entries under one root: `<root>/YYYY-MM/Agent session *.md`, one month folder down and no deeper.

build_report_index() {
  [ "$REPORT_INDEX_BUILT" = 0 ] || return 0
  REPORT_INDEX_BUILT=1
  # Candidates are files named `Agent session *.md`, in the notebook and in every archive root, that carry
  # a `session:` key — which `session-status:` does not match, since the key must be followed by its
  # colon. An entry with NEITHER status key is still indexed, and the index says `absent` for it; nothing
  # here requires a status.
  local entry_files
  entry_files=$(notebook_roots | while IFS= read -r root; do
    [ -n "$root" ] && [ -d "$root" ] && entries_in_root "$root"
  done | sort || true)
  # An empty file list must never reach xargs: with no arguments grep would read stdin and hang.
  [ -n "$entry_files" ] || return 0
  index_files=$(printf '%s\n' "$entry_files" | tr '\n' '\0' | xargs -0 grep -l -E "^[[:space:]]*session[[:space:]]*:" 2>/dev/null | sort || true)
  # An empty file list must never reach xargs: with no arguments awk would read stdin and hang.
  [ -n "$index_files" ] || return 0
  REPORT_INDEX=$(printf '%s\n' "$index_files" | tr '\n' '\0' | xargs -0 awk -v key="$REPORTS_TO_KEY" "$index_awk" 2>/dev/null || true)
}

# The notebook entry of a session name, and what it says the session reports to. The most recent
# entry by filename timestamp wins, because a name recurs across days; a name with more than one
# entry is reported with the plan rather than hidden, so the caller sees that it was a choice.
lookup_reports_to() {  # $1 = session name; sets rt_value, rt_entry, rt_count, rt_all, rt_status; 1 when there is no entry
  rt_value=""
  rt_entry=""
  rt_status=""
  rt_count=0
  rt_all=""
  build_report_index
  rt_all=$(printf '%s\n' "$REPORT_INDEX" | awk -F '\t' -v n="$1" '$1 == n { print }')
  [ -n "$rt_all" ] || return 1
  rt_count=$(printf '%s\n' "$rt_all" | grep -c . || true)
  # Sort by the filename stamp (field 5), then by path, and take the last: the newest entry. An
  # unstamped filename has an empty key and loses to every stamped one.
  rt_line=$(printf '%s\n' "$rt_all" | sort -t "$(printf '\t')" -k5,5 -k3,3 | tail -n 1)
  rt_value=$(printf '%s' "$rt_line" | cut -f 2)
  rt_entry=$(printf '%s' "$rt_line" | cut -f 3)
  rt_status=$(printf '%s' "$rt_line" | cut -f 4)
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
      chain_reason="no notebook entry for '$chain_cur' under $(notebook_roots | paste -sd ';' - | sed 's/;/ or /g') (an entry with session: \"$chain_cur\", whatever its status), so the line cannot be followed past it$chain_so_far; a missing record is not a permission"
      return 1
    fi
    if [ "$rt_count" -gt 1 ]; then
      chain_doubt="$chain_doubt'$chain_cur' has $rt_count notebook entries, and the newest by filename stamp was taken ($rt_entry, status ${rt_status:-unset}); the others: $(printf '%s\n' "$rt_all" | sort -t "$(printf '\t')" -k5,5 -k3,3 | sed \$d | cut -f 3 | tr '\n' ' ')
"
    fi
    chain_rt="$rt_value"
    if [ -z "$chain_rt" ]; then
      chain_reason="the newest notebook entry of '$chain_cur' ($rt_entry, status ${rt_status:-unset}) carries no '$REPORTS_TO_KEY' key, so the line cannot be followed past it$chain_so_far; a missing record is not a permission"
      return 1
    fi
    [ -z "$chain_path" ] || chain_path="$chain_path; "
    chain_path="$chain_path$chain_cur -> $chain_rt"
    [ "$chain_rt" != "$2" ] || return 0

    # THE ACCEPT VERBS' WRITE PATH CANNOT BE REACHED BY EQUALITY, because it is not a session: nothing
    # reports to `human:nelson`, so the walk above would refuse every target the notifier ever has. What a
    # caller above the fleet can be shown instead is that the line reaches ITS TOP — an admiral, or
    # Nelson himself. A line that ends there is a line inside the fleet, and the verb's own notice may
    # follow it down. A target whose line CANNOT be followed is still refused, which is the property this
    # whole function exists for: a missing record is not a permission. Package 5 found this after widening
    # the rank gate below and leaving this one shut, which made the notifier's wake refuse everything.
    if [ "${by_rank:-9}" -lt -1 ]; then
      case "$chain_rt" in
        Nelson|nelson|NELSON) return 0 ;;
        *) [ "$(rank_of_name "$chain_rt")" != -1 ] || return 0 ;;
      esac
    fi
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
  # An admiral is matched by its FULL NAME. A row that reads as rank -1 (from the admiral definition or an [A0] name) but is not one of the two admirals was not made by Nelson, so its rank cannot be read: row_why says why, for the refusal and the survey (review 1 of #88).
  row_why=""
  if [ "$row_rank" = -1 ] && ! is_admiral "$row_name"; then
    if [ "$(rank_of_name "$row_name")" = -1 ]; then row_why="its [A0] name is not an admiral's name"
    else row_why="it runs the admiral definition but its name is not an admiral's name"; fi
    row_rank=9
  fi
  row_alive=0
  if [ -n "$row_pid" ] && kill -0 "$row_pid" 2>/dev/null; then row_alive=1; fi
}

default_message_for() {  # $1 = target name
  printf '%s' "You are woken by $by: $why. This is your own session continuing under its own id, not a new one, so everything you had is still here. If a write of yours was refused because the fleet was paused, try that write again: the pause was read before this wake, and the gate answers honestly every time. Read the cross-session log delta from the position your notebook entry records: read each entry in full and give it a disposition without restating it in chat, then carry on where you stopped. Report to $by by SendMessage only when something changed, something is asked, or something failed; send nothing that carries no change."
}

# jq -Rs quotes and escapes the whole string, quotes included, so a message carrying a quote, a
# backslash or a newline still prints as a SendMessage the caller can paste as it stands.
# The hand form, for a caller who would rather do it themselves once the session stops. It always
# names the FULL sessionId: a resume given the short background id starts a NEW session instead of
# continuing the old one, which is how `[C0-OB] obsidian` got a new id that died, while the same wake
# given the full sessionId continued `[C1-CC] memories` under its own id and it acted on the brief.
print_hand_resume() {  # $1 = sessionId, $2 = cwd
  printf '  the hand form, once it is stopped — the FULL sessionId, never the short id:\n\n'
  printf '    (cd %s && claude --bg --resume %s "<your message>")\n\n' "$2" "$1"
}

print_sendmessage() {  # $1 = target name, $2 = message
  printf '  a live session is reached only by a Claude session'\''s own SendMessage tool, so send this yourself:\n\n'
  printf '    SendMessage({to: %s, message: %s})\n\n' \
    "$(printf '%s' "$1" | jq -Rs .)" "$(printf '%s' "$2" | jq -Rs .)"
}

# `claude stop` returns before the process is gone, and the listing drops the pid before Claude Code
# stops holding the session as running. A resume inside that window forks a copy — seen once, as a
# junk session named after the wake message — and the check after the resume is what actually catches
# it. This wait is the cheaper first line, and its limits are worth stating plainly: it polls the same
# field the caller already read, so it cannot observe Claude Code's internal hold; what it does catch
# is a pid coming BACK, which is a session restarted by someone else mid-run. Three checks, a second
# apart; a row pruned from the listing meanwhile is stopped for good and needs no further wait.
settle_stopped() {  # uses row_id; 0 when no pid comes back (or the row is gone), 1 when one does
  settle_tries=0
  while [ "$settle_tries" -lt 3 ]; do
    sleep 1
    read_listing
    settle_row=$(printf '%s' "$listing" | jq -c --arg s "$row_id" '[.[] | select(.id==$s)] | first // empty')
    # A row can also leave the listing entirely while this waits. No rule is claimed about when:
    # across five measured runs some throwaway rows went within a minute or two and others were still
    # listed after three minutes, with the fleet's own stopped sessions listed for hours, so whatever
    # removes them is not isolated and is not reliably reproducible. The code only has to cope: a row
    # that has gone carries no pid, and the sessionId the resume needs is already in hand.
    [ -n "$settle_row" ] || return 0
    settle_pid=$(printf '%s' "$settle_row" | jq -r '.pid // empty')
    if [ -n "$settle_pid" ] && kill -0 "$settle_pid" 2>/dev/null; then
      row_pid="$settle_pid"
      return 1
    fi
    settle_tries=$((settle_tries + 1))
  done
  return 0
}

# --- waking a stopped session ----------------------------------------------------------------
# A flagless resume, from the target's own cwd, verified afterwards: the SAME id must be running
# and no new id may have appeared, because a new id means the resume forked a copy instead.
wake_stopped() {  # uses row_*; $1 = the message
  wake_message="$1"
  # Never resume with an empty or short id. `claude --bg --resume ""` does not fail: it starts a NEW
  # session with the message as its prompt, which is how a junk session appears under the target's
  # cwd. The full sessionId is the only value this may pass.
  case "$row_session_id" in
    ????????-????-????-????-????????????) ;;
    *) die "the listing gives no full sessionId for $row_id (got '$row_session_id'), and a resume needs one; nothing was touched" ;;
  esac
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
    die "the resume of $row_id started a copy ($forked_id) instead of continuing it, which means Claude Code still held $row_id as running; $stop_note, nothing was logged, and $row_id was not woken. This is what a wake issued in the seconds right after a 'claude stop' looks like: the pid leaves the listing before the session stops being held as running. Wait a few seconds and run this again, or reach a live session by SendMessage instead. Resume output: $out"
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

$by woke the stopped session \`$row_name\` (background id $row_id, agent \`$row_agent\`, $(word_of_rank "$row_rank")) with a flagless \`claude --bg --resume $row_session_id\` from its own cwd \`$row_cwd\`, so the conversation continues under the same id and nothing was forked; verified from \`claude agents --json --all\` after the resume, where $row_id is running again and no new id appeared. Why: $why. The session was told it is continuing, that a write the pause refused can be tried again, to read the log delta from its recorded position without restating it, and to report to $by only when something changed, is asked, or failed. Posted by \`wake-session.sh\` on behalf of $by, who attests its own log position in its own entries. — $by
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
  [ -z "$row_why" ] || die "refused: \`$row_name\` $row_why; only Nelson makes an admiral, so its rank cannot be read"
  [ "$row_rank" != 9 ] || die "cannot tell the target's rank from its agent ('$row_agent') or its name ('$row_name'); refusing rather than guessing"
  # THE SHIP RULE, the table's one sentence (`ship_refusal`): DV is refused for every caller, and each admiral reaches only its own ships (the areas ruling, 2026-09-29).
  r=$(ship_refusal "$by" "$by_rank" "$(ship_of_name "$row_name")"); [ -z "$r" ] || die "$r"
  # A captain is woken by Nelson, or by an admiral (`[A0] rear admiral` or `[A0] areas admiral`, each on its own ships): captains report to an admiral, so an A0 caller waking one is the chain working, not a breach of it. Every other caller is refused, as before, because the script cannot verify Nelson. `-gt -1` rather than `!= -1`: an admiral is -1 and the accept verbs' write path is -2, and both sit above a captain. Testing for equality with -1 refused the verb's own notice to a stopped captain, which is the case the notifier exists for.
  if [ "$row_rank" = 0 ] && [ "$by_rank" -gt -1 ]; then
    die "refused: \`$row_name\` is a captain; only Nelson or an admiral (\`[A0] rear admiral\` or \`[A0] areas admiral\`, on its own ships) wakes a captain, and this script cannot verify that it is Nelson calling"
  fi
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
    print_hand_resume "$row_session_id" "$row_cwd"
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
  if ! settle_stopped; then
    printf '  it came back with pid %s while the listing was being confirmed, so it is alive after all and is NOT resumed.\n' "$row_pid"
    print_sendmessage "$row_name" "$message"
    printf '  nothing was touched; no record was written.\n'
    exit 3
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
    unknown_list="$unknown_list    $row_id  $row_name (agent '$row_agent'; ${row_why:-no rank code in the name})
"
    continue
  fi
  # The survey hides captains from everyone but an admiral, for the same reason the single target refuses them: a captain is woken by Nelson or by A0, so only an A0 caller is shown one.
  if [ "$row_rank" = 0 ] && [ "$by_rank" -gt -1 ]; then continue; fi   # above a captain: A0 (-1) and the verb path (-2)
  # The ship rule, as for a single target: DV is never offered, and an admiral sees only its own ships.
  row_ship=$(ship_of_name "$row_name")
  if [ -n "$(ship_refusal "$by" "$by_rank" "$row_ship")" ]; then continue; fi
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
  survey_rows="$survey_rows$row_ship$TAB$row_state$TAB$row_display
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
      # THE LIST COMES FROM THE TABLE (`ships_in_words`), never from a hand-written one.
      print_ship_block "$one_ship" "SHIP $one_ship — not one of the known ships ($(ships_in_words)); listed as the name spells it"
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
  # A row pruned from the listing meanwhile is stopped for good, and the row captured by the survey
  # still carries its sessionId, so the sweep treats it exactly as the single-target path does rather
  # than skipping it: the two must not disagree about the same state.
  [ -n "$sweep_row" ] || sweep_row="$one_row"
  load_row "$sweep_row"
  if [ "$row_alive" = 1 ]; then
    printf '  skipped %s (%s): it is running again now (pid %s), so it needs a SendMessage, not a resume\n' "$row_id" "$row_name" "$row_pid"
    continue
  fi
  if ! settle_stopped; then
    printf '  skipped %s (%s): a pid came back (%s) while the listing was being confirmed, so it is alive and needs a SendMessage\n' "$row_id" "$row_name" "$row_pid"
    continue
  fi
  one_message="$message"
  [ -n "$one_message" ] || one_message=$(default_message_for "$row_name")
  wake_stopped "$one_message"
done <<EOF
$stopped_rows
EOF
exit 0
