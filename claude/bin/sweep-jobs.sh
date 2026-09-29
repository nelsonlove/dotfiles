#!/usr/bin/env bash
# sweep-jobs.sh — remove the job of a session that has finished, and only then.
#
# WHAT A JOB IS, and why removing one is not tidying. `~/.claude/jobs/<short id>/` holds a session's listing
# row, its state and its saved options; `claude rm <short id>` deletes them and leaves the transcript. After
# that the session can still be resumed BY FULL ID, but only if its name, agent and directory were recorded
# somewhere first — which is what the roster keys in its notebook entry are for. So a job may be removed when
# the entry can stand in for it, and never before.
#
# THE CONDITION, ruled 2026-09-29, and all of it must hold:
#   * the entry carries ALL FOUR keys — `session-id` (full, 36 characters), `session`, `agent`, `cwd`;
#   * the entry reads `archived/ended` (or the old `ended` inside the dual-read window, to 2026-10-04);
#   * the session is not alive.
# Anything else is skipped, and the skip is the safe side: a job left behind costs a directory, while a job
# removed from under a session that still needs it costs the session.
#
# A SHORT OR JUNK `session-id` IS A SKIP, NEVER A REFUSAL, and the reason is a measurement rather than a
# preference: **324 historical entries hold a short or junk value** in that key, against about thirty holding a full one (the 324 reproduces exactly; the total moves between runs, because sessions write while the count is taken) — 8-character
# ids, plus literal `vaultbridge` and `.inf` — because that is what the key meant before the ruling. A sweeper
# that refused on them would refuse 324 records that are simply old. The resume path refuses, because there it
# concerns the one session being woken; here it skips. Do not tighten this without re-measuring the population.
#
# IT RUNS ON NELSON'S WORD AND NEVER ON A SCHEDULE. There is no tickle job for this and there must not be:
# a sweep is a deletion, and a deletion that runs while nobody is watching is how a fleet loses a session it
# A DRY RUN, AND ONLY A DRY RUN. On the captain's word this ships with no delete path at all: `--go` is
# refused, `claude rm` is never called, and no file is removed by any flag or input — a test asserts that with
# a recording stub on PATH rather than trusting the reading. The delete path returns as its own PR after a
# week of this script's output has been read as evidence, and issue #78 carries what it must bring with it.
#
# So every line this prints is written to be judged later: the job id, the verdict, the reason, and the live
# checks the verdict rested on — the listing row, the pid test, and the newest entry with its status. A week
# of that reads as a case for or against the delete path. A week of "WOULD REMOVE abc12345" would not.
#
# Usage:
#   sweep-jobs.sh [--jobs-dir <path>] [--notebook-dir <path>]
#                 [--archive-dir <path>] [--log <path>] [--claude-bin <path>]
#
#   --go          REFUSED. It names issue #78, which holds the delete path and the week of evidence it waits on.
#   --jobs-dir    where the jobs live (default `~/.claude/jobs`). For testing only.
#   --agents-dir  the parent both notebook roots are derived from. For testing only, and it was an accepted
#                 no-op until the review of #71 — it is honoured now, and named here because a flag a script
#                 accepts and ignores is worse than one it refuses.
#   --notebook-dir, --archive-dir   the two notebook roots; same meaning as in `wake-session.sh`, and
#                 `--notebook-dir` alone reads no archive, so a test stays sealed. For testing only.
#   --claude-bin  the `claude` binary to call for the listing and the removal. For testing only — a suite
#                 points it at a recorder and nothing is removed for real.
#
# Exit: 0 whatever it decided (a sweep that finds nothing to do is a success); 2 refused, before anything.
#
# THE TWO ID FORMS: `claude rm` takes the SHORT job id, which is the job directory's name; `--resume` needs
# the FULL sessionId, which is what the entry carries. This script reads the full id from the entry and uses
# the directory name for the removal, and never derives one from the other.
#
# Works under /bin/bash 3.2 (macOS). Needs jq.

set -u
set -o pipefail

PROG=sweep-jobs
JOBS_DIR="$HOME/.claude/jobs"
AGENTS_DIR="$HOME/obsidian/00-09 System/03 Agents"
AGENTS_DIR_SET=0
NOTEBOOK_DIR=""      # derived from AGENTS_DIR by the library, after the flags are read
NOTEBOOK_DIR_SET=0
ARCHIVE_DIR=""       # likewise
ARCHIVE_DIR_SET=0
CLAUDE_BIN="claude"

die() { printf '%s: %s\n' "$PROG" "$*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    # REFUSED, AND IT SAYS WHY. Silently ignoring a flag that used to delete is worse than not having it: the
    # caller asked for a removal and would read a dry-run tally as a report of one.
    --go) die "--go is not available: this ships as a dry run while a week of its output is read as evidence. The delete path is issue #78, which carries the rules it must bring with it." ;;
    --by) die "--by belongs to the delete path, which is not in this version; see issue #78" ;;
    --jobs-dir) [ $# -ge 2 ] && [ -n "$2" ] || die "--jobs-dir needs a path"; JOBS_DIR="$2"; shift 2 ;;
    --notebook-dir) [ $# -ge 2 ] && [ -n "$2" ] || die "--notebook-dir needs a path"; NOTEBOOK_DIR="$2"; NOTEBOOK_DIR_SET=1; shift 2 ;;
    --archive-dir) [ $# -ge 2 ] && [ -n "$2" ] || die "--archive-dir needs a path"; ARCHIVE_DIR="$2"; ARCHIVE_DIR_SET=1; shift 2 ;;
    # `--log` went with the delete path: the only thing this wrote to the fleet log was a release line for a
    # removal, and there are no removals. It is refused rather than ignored, so a caller who passes it learns
    # that nothing is being logged instead of assuming it is.
    --log) die "--log belongs to the delete path, which is not in this version; nothing is written to the fleet log; see issue #78" ;;
    --claude-bin) [ $# -ge 2 ] && [ -n "$2" ] || die "--claude-bin needs a path"; CLAUDE_BIN="$2"; shift 2 ;;
    --agents-dir) [ $# -ge 2 ] && [ -n "$2" ] || die "--agents-dir needs a path"; AGENTS_DIR="$2"; AGENTS_DIR_SET=1; shift 2 ;;
    -h|--help) sed -n '2,/^set -u$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument '$1'" ;;
  esac
done


script_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || script_dir=""
for lib in notebook-roots session-status session-roster; do
  path="$script_dir/../lib/$lib.sh"
  [ -r "$path" ] || die "the $lib library is missing or unreadable at $path"
  bash -n "$path" 2>/dev/null || die "the $lib library at $path does not parse; refusing rather than sweeping on half a rule"
  # shellcheck disable=SC1090
  . "$path" || die "the $lib library at $path could not be sourced"
done
for fn in notebook_roots_of entries_in_root notebook_entry_files_of notebook_dir_for archive_dir_for \
          session_status_of roster_read roster_id_is_full roster_newest_entry_for_id; do
  command -v "$fn" >/dev/null 2>&1 || die "the libraries parsed but defined no $fn; refusing to sweep on half a rule"
done
command -v jq >/dev/null 2>&1 || die "jq is required"

# THE TWO ROOTS COME FROM THE LIBRARY, derived after the flags, exactly as `wake-session.sh` does it. The first
# version kept its own copies of both path strings and never called these — so it read the notebook and NEVER
# THE ARCHIVE, which is the one root an ended entry moves into. The sweeper skipped precisely the population it
# exists for, and `--agents-dir` was an accepted no-op. One definition, or it is not one definition.
NOTEBOOK_DIR=$(notebook_dir_for "$AGENTS_DIR" "${NOTEBOOK_DIR:-$AGENTS_DIR/03.04 Records/Agent notebook}" "$NOTEBOOK_DIR_SET" "$AGENTS_DIR_SET")
[ "$NOTEBOOK_DIR_SET" = 1 ] || NOTEBOOK_DIR="$AGENTS_DIR/03.04 Records/Agent notebook"
ARCHIVE_DIR=$(archive_dir_for "$AGENTS_DIR" "$ARCHIVE_DIR" "$ARCHIVE_DIR_SET")

# Every entry, read once, indexed by the FULL id it carries. A short or junk id never reaches this index, so
# the sweep simply cannot see the 324 old entries — they are not refused, they are not candidates.
# THE NEWEST ENTRY DECIDES, through the library's own `roster_newest_entry_for_id`. The first version built an
# index and took the FIRST row matching an id, in oldest-filename order — so a session whose newest entry reads
# `draft/running` was swept on the strength of an older `archived/ended` one. 18 live ids carry more than one
# entry, which is why that function exists; not calling it was the bug.
roster_state_for_id() {  # $1 = full id; sets `roster_pick_state` and `roster_pick_entry`
  roster_pick_state=""; roster_pick_entry=""
  roster_newest_entry_for_id "$1" "$NOTEBOOK_DIR" "$NOTEBOOK_DIR_SET" "$ARCHIVE_DIR" "$ARCHIVE_DIR_SET"
  [ -n "$roster_entry" ] || return 0
  # AND IF THE LIBRARY COULD NOT ORDER THEM, NOTHING IS REMOVED. Two entries with the same stamp, or one whose
  # filename carries no stamp at all, leave "newest" undefined — and this script's whole authority to delete
  # rests on reading the newest entry. Undefined is not a reason to guess.
  [ "${roster_entry_ambiguous:-0}" = 0 ] || return 0
  # AND THE WINNER MUST BE OURS. The loose selection test is justified by one sentence — "a false positive only
  # costs a skip, because the winner still has to pass the caller's four-key test" — and that sentence was
  # true of the four-key test and FALSE of the id. `roster_id_is_full` accepts ANY full id, and nothing here
  # compared it to the one asked for. So `session-id: BBBB… # forked from AAAA…` competed for AAAA, won on its
  # stamp, read `archived/ended` with four good keys, and a session whose own newest record says running lost
  # its job to another session's entry. An invariant that lives only in a comment is not an invariant.
  [ "${roster_entry_unreadable:-0}" = 0 ] || return 0
  roster_read "$roster_entry"
  roster_id_is_full "$roster_id" || return 0
  [ -n "$roster_session" ] && [ -n "$roster_agent" ] && [ -n "$roster_cwd" ] || return 0
  session_status_of "$roster_entry"
  roster_pick_state="${sess_state:-absent}"
  roster_pick_entry="$roster_entry"
  return 0
}

# THE LISTING MUST BE READABLE AND MUST BE AN ARRAY, and a failure REFUSES rather than sweeping. Every failure
# mode used to resolve to "not running", which is the unsafe direction for a script that deletes: a `claude
# agents` that exited 1, a listing that was an object, or a live row carrying no `.status` all read as dead and
# the job was removed. `wake-session.sh` has guarded both since #50; this one deletes and had neither.
listing=$("$CLAUDE_BIN" agents --json --all 2>/dev/null) || die "\`$CLAUDE_BIN agents --json --all\` failed; refusing to sweep without knowing which sessions are alive"
# AN ARRAY OF OBJECTS, not just an array. `[1]`, `["x"]` and `[null]` passed a bare type check; the pid lookup
# then errored, the error was swallowed, and the job was removed — the unsafe direction again, one layer in.
printf '%s' "$listing" | jq -e 'type == "array" and all(type == "object")' >/dev/null 2>&1 || die "the session listing is not an array of objects; refusing to sweep on something this script cannot read"

# ALIVE IS A LIVE PID, not a status string — the same test `wake-session.sh` uses, because two readers of one
# listing disagreeing about who is alive is exactly how a live session gets swept. A row with a pid this
# machine still answers for is alive whatever its `.status` says or does not say.
# ANY LIVE ROW MAKES IT ALIVE. This took the FIRST row's pid, so two rows sharing a sessionId — a dead one
# first — would hide a live session and its job would be removed. One live pid anywhere under that id is
# enough to keep the job: the cost of keeping a dead job is a stale directory, and the cost of removing a live
# one is a session nobody can bring back.
session_is_alive() {  # $1 = full sessionId
  sia_found=1
  while IFS= read -r sia_pid; do
    [ -n "$sia_pid" ] || continue
    if kill -0 "$sia_pid" 2>/dev/null; then sia_found=0; break; fi
  done <<EOF
$(printf '%s' "$listing" | jq -r --arg s "$1" '.[] | select(.sessionId == $s) | .pid // empty' 2>/dev/null || true)
EOF
  return $sia_found
}

swept=0; skipped=0
for job in "$JOBS_DIR"/*; do
  [ -d "$job" ] || continue
  short=$(basename "$job")
  state="$job/state.json"
  full=$(jq -r '.sessionId // ""' "$state" 2>/dev/null || echo "")
  name=$(jq -r '.name // ""' "$state" 2>/dev/null || echo "")
  reason=""
  # BUILT AS THE CHECKS RUN, so the line cannot claim a check that did not happen. A verdict a reader cannot
  # re-derive is not evidence, and a week of these has to stand as the case for the delete path.
  evidence="id=${full:-none}"

  if [ -z "$full" ]; then
    reason="its state names no sessionId, so no entry can be matched to it"
  elif ! roster_id_is_full "$full"; then
    reason="its state names '$full', which is not a full sessionId"
  else
    ev_rows=$(printf '%s' "$listing" | jq -r --arg s "$full" '[.[] | select(.sessionId == $s)] | length' 2>/dev/null || echo "?")
    ev_pids=$(printf '%s' "$listing" | jq -r --arg s "$full" '[.[] | select(.sessionId == $s) | .pid // empty] | join(",")' 2>/dev/null || echo "?")
    evidence="$evidence listing-rows=$ev_rows pids=${ev_pids:-none}"
    if session_is_alive "$full"; then
      evidence="$evidence live-pid=yes"
      reason="the session is in the listing with a live pid"
    else
      evidence="$evidence live-pid=no"
      roster_state_for_id "$full"
      entry_path="$roster_pick_entry"
      evidence="$evidence entries-for-id=${roster_entry_count:-0} newest=${roster_entry:-none}"
      [ "${roster_entry_ambiguous:-0}" = 0 ] || evidence="$evidence order=UNDECIDABLE"
      if [ -z "$roster_pick_state" ]; then
        evidence="$evidence newest-status=unreadable-or-incomplete"
        reason="no notebook entry carries all four roster keys with that full id"
      else
        evidence="$evidence newest-status=$roster_pick_state"
        case "$roster_pick_state" in
          ended) ;;
          *) reason="its newest entry $entry_path reads '$roster_pick_state', not archived/ended" ;;
        esac
      fi
    fi
  fi

  # EVERY LINE CARRIES ITS EVIDENCE, because a week of these is the case the delete path will be judged on.
  # The verdict alone cannot be checked by a reader; the three facts under it can. `evidence` is built as the
  # checks run, so a line can never claim a check that did not happen.
  if [ -n "$reason" ]; then
    skipped=$((skipped + 1))
    printf 'SKIP  %s  %s — %s\n' "$short" "${name:-(unnamed)}" "$reason"
    printf '      evidence: %s\n' "$evidence"
    continue
  fi
  swept=$((swept + 1))
  printf 'WOULD REMOVE  %s  %s — its newest entry %s carries all four keys and reads ended\n' "$short" "${name:-(unnamed)}" "$entry_path"
  printf '      evidence: %s\n' "$evidence"
  continue
done

printf '\n%s job(s) WOULD be removed, %s skipped. NOTHING WAS REMOVED: this version has no delete path (issue #78).\n' "$swept" "$skipped"
exit 0
