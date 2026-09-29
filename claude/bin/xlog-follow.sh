#!/usr/bin/env bash
# xlog-follow.sh — follow the fleet's cross-session log and print each NEW entry as ONE line.
#
# Nelson, relayed by [C0-CC] claude code (2026-09-29): "the areas admiral is running a shell command after every
# cross-session log monitor event. are other agents doing that too? can we change the monitor event so agents
# don't have to run those shell commands?" Under Monitor, every stdout line of this script is one event, and each
# line is one whole entry: its `## ` heading and its body, with the entry's newlines joined by " ⏎ ". So the
# event IS the entry, and a session reads it without running anything.
#
# THE MONITOR COMMAND a session uses (Monitor lasts at most 30 minutes; re-arm it when it expires):
#
#     Monitor({ command: "bash ~/.claude/bin/xlog-follow.sh",
#               description: "new cross-session log entries",
#               timeout_ms: 1800000 })
#
# WHAT IT DOES
#   * It starts AT THE END of the log and never replays the entries already there.
#   * An entry is printed only when it is complete: when the next `## ` heading arrives, or after 3 seconds with
#     no new bytes. Text that arrives after an entry was printed, with no heading of its own, is dropped.
#   * If the log is cut or rewritten, it re-syncs to the new end and prints nothing for that change: the size went
#     down, the inode changed (an atomic save by rename), or the bytes just before the old end are no longer the
#     same (a rewrite in place that grew the file). Only entries appended after that are printed.
#   * It polls once a second. It uses no network and no API. Its memory is one pending entry at most. Every child
#     it starts (stat, tail, head, cksum, sleep) ends before the next tick. It exits on SIGTERM, SIGINT and
#     SIGHUP, and when its output pipe is closed.
#
# USAGE   xlog-follow.sh [--log <path>]      (--log is for tests; the default is the fleet log, found by name
#                                            under ~/obsidian the way claude/hooks/cross-session-inject.py finds it)
#
# Plain bash (3.2 is enough) and the BSD tools of macOS; GNU `stat` is used where BSD `stat` is missing.

set -u
LC_ALL=C; export LC_ALL   # byte counts, not characters: the offsets below are bytes

log=""
while [ $# -gt 0 ]; do
  case "$1" in
    --log) [ $# -ge 2 ] || { echo "xlog-follow: --log needs a path" >&2; exit 2; }; log="$2"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "xlog-follow: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

if [ -z "$log" ]; then
  # The fleet log's home since 2026-08-18; if it has moved, find it by name the way the start hook does
  # (the first CROSS-SESSION.md under ~/obsidian, sorted, outside .trash).
  log="$HOME/obsidian/00-09 System/03 Agents/03.16 Cross-session log/CROSS-SESSION.md"
  if [ ! -f "$log" ]; then
    log=$(find "$HOME/obsidian" -name CROSS-SESSION.md -not -path '*/.trash/*' 2>/dev/null | sort | head -n 1)
  fi
fi
[ -n "$log" ] && [ -f "$log" ] || { echo "xlog-follow: no cross-session log found" >&2; exit 1; }

trap 'exit 0' TERM INT HUP
trap 'exit 0' PIPE

# inode and size, BSD first, GNU as the fallback; empty when the file is missing for a moment (mid-rename).
fstat() { stat -f '%i %z' "$1" 2>/dev/null || stat -c '%i %s' "$1" 2>/dev/null; }
# the bytes [from, from+count) of the file, byte-exact (a sentinel keeps trailing newlines)
slice() { local s; s=$(tail -c +"$(( $2 + 1 ))" "$1" 2>/dev/null | head -c "$3"; printf x); printf '%s' "${s%x}"; }
FP=64   # how many bytes before the old end must still match for growth to count as an append
fingerprint() { [ "$2" -gt 0 ] || { echo 0; return; }; local from=$(( $2 > FP ? $2 - FP : 0 )); tail -c +"$(( from + 1 ))" "$1" 2>/dev/null | head -c "$(( $2 - from ))" | cksum; }

NL=$'\n'
emit() {  # print one entry as one line, trailing blank lines trimmed; exit if nobody is reading any more
  local e="$1"
  while [ "${e%"$NL"}" != "$e" ]; do e="${e%"$NL"}"; done
  e="${e//$NL/ ⏎ }"
  [ -n "$e" ] || return 0
  printf '%s\n' "$e" || exit 0
}

read -r inode size <<< "$(fstat "$log")"
offset=${size:-0}
fp=$(fingerprint "$log" "$offset")
buf=""          # the entry being collected: empty, or text that starts with "## "
last_new=$SECONDS

while :; do
  sleep 1
  st=$(fstat "$log")
  if [ -z "$st" ]; then continue; fi          # missing for a moment, as during an atomic save
  read -r n_inode n_size <<< "$st"

  if [ "$n_inode" != "$inode" ] || [ "$n_size" -lt "$offset" ]; then
    # Cut or replaced: re-sync to the new end, print nothing for it.
    inode=$n_inode; offset=$n_size; fp=$(fingerprint "$log" "$offset"); buf=""; continue
  fi

  if [ "$n_size" -gt "$offset" ]; then
    if [ "$(fingerprint "$log" "$offset")" != "$fp" ]; then
      # Grown, but the bytes before the old end changed: a rewrite in place, not an append.
      offset=$n_size; fp=$(fingerprint "$log" "$offset"); buf=""; continue
    fi
    buf="$buf$(slice "$log" "$offset" "$(( n_size - offset ))")"
    offset=$n_size; fp=$(fingerprint "$log" "$offset"); last_new=$SECONDS

    # Anything before the first heading belongs to no entry we print (the gap between entries, or the tail of
    # an entry already printed). Keep only an unfinished last line, which may be a heading being written.
    if [ "${buf#"## "}" = "$buf" ]; then
      case "$buf" in
        *"$NL## "*) buf="## ${buf#*"$NL## "}" ;;
        *"$NL"*) buf="${buf##*"$NL"}" ;;
      esac
    fi
    # Every heading after the first closes the entry before it.
    while [ "${buf#"## "}" != "$buf" ]; do
      case "$buf" in
        *"$NL## "*)
          emit "${buf%%"$NL## "*}"
          buf="## ${buf#*"$NL## "}" ;;
        *) break ;;
      esac
    done
  fi

  # Quiet for 3 seconds: the pending entry is complete.
  if [ -n "$buf" ] && [ $(( SECONDS - last_new )) -ge 3 ]; then
    if [ "${buf#"## "}" != "$buf" ]; then emit "$buf"; fi
    buf=""
  fi
done
