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
# preference: of 351 historical entries carrying that key, **324 hold a short or junk value** — 8-character
# ids, plus literal `vaultbridge` and `.inf` — because that is what the key meant before the ruling. A sweeper
# that refused on them would refuse 324 records that are simply old. The resume path refuses, because there it
# concerns the one session being woken; here it skips. Do not tighten this without re-measuring the population.
#
# IT RUNS ON NELSON'S WORD AND NEVER ON A SCHEDULE. There is no tickle job for this and there must not be:
# a sweep is a deletion, and a deletion that runs while nobody is watching is how a fleet loses a session it
# meant to keep. `--dry-run` is the default; `--go` is the only thing that removes anything, and every removal
# writes one release line to the cross-session log.
#
# Usage:
#   sweep-jobs.sh [--go] [--by "<your session name>"] [--jobs-dir <path>] [--notebook-dir <path>]
#                 [--archive-dir <path>] [--log <path>] [--claude-bin <path>]
#
#   --go          actually remove. Without it nothing is removed and every decision is printed.
#   --by          who is sweeping, for the log line. Required with --go.
#   --jobs-dir    where the jobs live (default `~/.claude/jobs`). For testing only.
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
NOTEBOOK_DIR="$AGENTS_DIR/03.04 Records/Agent notebook"
NOTEBOOK_DIR_SET=0
ARCHIVE_DIR=""
ARCHIVE_DIR_SET=0
FLEET_LOG="$HOME/obsidian/00-09 System/03 Agents/03.16 Cross-session log/CROSS-SESSION.md"
CLAUDE_BIN="claude"
go=0
by=""

die() { printf '%s: %s\n' "$PROG" "$*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --go) go=1; shift ;;
    --by) [ $# -ge 2 ] && [ -n "$2" ] || die "--by needs a session name"; by="$2"; shift 2 ;;
    --jobs-dir) [ $# -ge 2 ] && [ -n "$2" ] || die "--jobs-dir needs a path"; JOBS_DIR="$2"; shift 2 ;;
    --notebook-dir) [ $# -ge 2 ] && [ -n "$2" ] || die "--notebook-dir needs a path"; NOTEBOOK_DIR="$2"; NOTEBOOK_DIR_SET=1; shift 2 ;;
    --archive-dir) [ $# -ge 2 ] && [ -n "$2" ] || die "--archive-dir needs a path"; ARCHIVE_DIR="$2"; ARCHIVE_DIR_SET=1; shift 2 ;;
    --log) [ $# -ge 2 ] && [ -n "$2" ] || die "--log needs a path"; FLEET_LOG="$2"; shift 2 ;;
    --claude-bin) [ $# -ge 2 ] && [ -n "$2" ] || die "--claude-bin needs a path"; CLAUDE_BIN="$2"; shift 2 ;;
    --agents-dir) [ $# -ge 2 ] && [ -n "$2" ] || die "--agents-dir needs a path"; AGENTS_DIR="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^set -u$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument '$1'" ;;
  esac
done

[ "$go" = 0 ] || [ -n "$by" ] || die "--go needs --by \"<your session name>\": a removal is an act, and an act is attributed"

script_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || script_dir=""
for lib in notebook-roots session-status session-roster; do
  path="$script_dir/../lib/$lib.sh"
  [ -r "$path" ] || die "the $lib library is missing or unreadable at $path"
  bash -n "$path" 2>/dev/null || die "the $lib library at $path does not parse; refusing rather than sweeping on half a rule"
  # shellcheck disable=SC1090
  . "$path" || die "the $lib library at $path could not be sourced"
done
command -v notebook_entry_files_of >/dev/null 2>&1 || die "the notebook-roots library defined no entry lister; refusing"
command -v session_status_of >/dev/null 2>&1      || die "the session-status library defined no reader; refusing"
command -v roster_read >/dev/null 2>&1            || die "the session-roster library defined no reader; refusing"
command -v jq >/dev/null 2>&1 || die "jq is required"

# Every entry, read once, indexed by the FULL id it carries. A short or junk id never reaches this index, so
# the sweep simply cannot see the 324 old entries — they are not refused, they are not candidates.
roster_index=""
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  roster_read "$entry"
  roster_id_is_full "$roster_id" || continue
  [ -n "$roster_session" ] && [ -n "$roster_agent" ] && [ -n "$roster_cwd" ] || continue
  session_status_of "$entry"
  printf '%s\t%s\t%s\n' "$roster_id" "${sess_state:-absent}" "$entry"
done <<EOF
$(notebook_entry_files_of "$NOTEBOOK_DIR" "$NOTEBOOK_DIR_SET" "$ARCHIVE_DIR" "$ARCHIVE_DIR_SET" "$AGENTS_DIR")
EOF
roster_index=$(cat)

# The live listing, so a job whose session is alive is never touched whatever its entry says.
listing=$("$CLAUDE_BIN" agents --json --all 2>/dev/null || true)

swept=0; skipped=0
for job in "$JOBS_DIR"/*; do
  [ -d "$job" ] || continue
  short=$(basename "$job")
  state="$job/state.json"
  full=$(jq -r '.sessionId // ""' "$state" 2>/dev/null || echo "")
  name=$(jq -r '.name // ""' "$state" 2>/dev/null || echo "")
  reason=""

  if [ -z "$full" ]; then
    reason="its state names no sessionId, so no entry can be matched to it"
  elif printf '%s' "$listing" | jq -e --arg s "$full" 'map(select(.sessionId == $s and (.status // "") != "")) | length > 0' >/dev/null 2>&1; then
    reason="the session is in the listing as running"
  else
    line=$(printf '%s\n' "$roster_index" | awk -F '\t' -v id="$full" '$1 == id { print; exit }')
    if [ -z "$line" ]; then
      reason="no notebook entry carries all four roster keys with that full id"
    else
      state_word=$(printf '%s' "$line" | cut -f2)
      entry_path=$(printf '%s' "$line" | cut -f3)
      case "$state_word" in
        ended) ;;
        *) reason="its entry $entry_path reads '$state_word', not archived/ended" ;;
      esac
    fi
  fi

  if [ -n "$reason" ]; then
    skipped=$((skipped + 1))
    printf 'SKIP  %s  %s — %s\n' "$short" "${name:-(unnamed)}" "$reason"
    continue
  fi

  swept=$((swept + 1))
  if [ "$go" = 0 ]; then
    printf 'WOULD REMOVE  %s  %s — its entry %s carries all four keys and reads ended\n' "$short" "${name:-(unnamed)}" "$entry_path"
    continue
  fi
  if "$CLAUDE_BIN" rm "$short" >/dev/null 2>&1; then
    printf 'REMOVED  %s  %s\n' "$short" "${name:-(unnamed)}"
    stamp=$(date '+%Y-%m-%dT%H:%M')
    cat <<EOF >> "$FLEET_LOG" 2>/dev/null || printf '%s: the release line could not be written to %s\n' "$PROG" "$FLEET_LOG" >&2

## $stamp · $by — release
Swept the job \`$short\` of \`${name:-(unnamed)}\` (\`$full\`): its entry \`$entry_path\` carries all four roster keys and reads ended, and the session was not in the listing. The transcript is untouched and a resume by full id still reaches it.
EOF
  else
    printf 'FAILED   %s  %s — claude rm refused or failed; nothing was logged\n' "$short" "${name:-(unnamed)}"
  fi
done

printf '\n%s job(s) would be removed, %s skipped%s\n' "$swept" "$skipped" "$([ "$go" = 1 ] && printf ' (--go: removals are real)' || printf ' (dry run; --go removes)')"
exit 0
