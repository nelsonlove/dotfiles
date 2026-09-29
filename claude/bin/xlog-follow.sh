#!/usr/bin/env bash
# xlog-follow.sh — follow the fleet's cross-session log and print each NEW entry as ONE line.
#
# Nelson, relayed by [C0-CC] claude code (2026-09-29): "the areas admiral is running a shell command after every
# cross-session log monitor event. are other agents doing that too? can we change the monitor event so agents
# don't have to run those shell commands?" Under Monitor, every stdout line of this script is one event, and each
# line is one whole entry: its `## ` heading and its body, with the entry's newlines joined by " ⏎ ". So the
# event IS the entry, and a session reads it without running anything.
#
# THE MONITOR COMMAND a session uses (Monitor lasts at most 30 minutes; re-arm it with the SAME command when
# it expires, and --state makes the new run print what arrived in between):
#
#     Monitor({ command: "bash ~/.claude/bin/xlog-follow.sh --state ~/.local/state/xlog-follow/$CLAUDE_CODE_SESSION_ID",
#               description: "new cross-session log entries",
#               timeout_ms: 1800000 })
#
# WHAT IT DOES
#   * It starts AT THE END of the log and never replays the entries already there. With --state <file> it saves
#     where it is (the start of any entry still pending), and a later run on the same file resumes from there. A
#     gap over 16 KB, or a state file that no longer fits the log, prints one notice line instead.
#   * One tick's growth over 16 KB or with more than 10 entries is not read as appends: one notice line.
#   * An entry starts at a stamped heading, `## YYYY-...`; a plain `## x` line in a body is part of the body.
#     An entry is printed only when it is complete: at the next stamped heading, or after 3 seconds with no new
#     bytes. Text that arrives after an entry was printed, with no heading of its own, is dropped.
#   * If the log is cut or rewritten, it re-syncs and prints nothing for that change: the size went down, the
#     inode changed (an atomic save by rename), or the bytes before the known end changed (a rewrite in place,
#     of any size). It then waits until the file has not changed for two polls, so a save caught half written
#     is not read as an append, and takes that end as its new start. An entry pending at that moment is printed
#     first. Entries appended in the two seconds of settling are not printed.
#   * It polls once a second. It uses no network and no API. Its memory is one pending entry at most. Every child
#     it starts (stat, tail, head, cksum, sleep, mv) ends before the next tick. It exits on SIGTERM, SIGINT and
#     SIGHUP, and when its output pipe is closed.
#
# USAGE   xlog-follow.sh [--log <path>] [--state <file>]
#         --log is for tests; the default is the fleet log, found by name under ~/obsidian exactly the way
#         claude/hooks/cross-session-inject.py finds it. --state is where a run saves its place for the next one.
#
# Plain bash (3.2 is enough), with the BSD tools of macOS or the GNU ones; the `stat` form is picked once.

set -u
LC_ALL=C; export LC_ALL   # byte counts, not characters: the offsets below are bytes

log=""; state=""
while [ $# -gt 0 ]; do
  case "$1" in
    --log) [ $# -ge 2 ] || { echo "xlog-follow: --log needs a path" >&2; exit 2; }; log="$2"; shift 2 ;;
    --state) [ $# -ge 2 ] || { echo "xlog-follow: --state needs a path" >&2; exit 2; }; state="$2"; shift 2 ;;
    -h|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "xlog-follow: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

if [ -z "$log" ]; then
  # The same lookup as claude/hooks/cross-session-inject.py's find_log(): the first CROSS-SESSION.md under
  # ~/obsidian, sorted by path, outside .trash. Never a hardcoded path, so the two tools always agree on which
  # file is the fleet log (review 1 of #77).
  log=$(find "$HOME/obsidian" -name CROSS-SESSION.md -not -path '*/.trash/*' 2>/dev/null | sort | head -n 1)
fi
[ -n "$log" ] && [ -f "$log" ] || { echo "xlog-follow: no cross-session log found" >&2; exit 1; }

trap 'save_state; exit 0' TERM INT HUP
trap 'save_state; exit 0' PIPE

# inode, size and mtime. The form is chosen ONCE: GNU `stat -f` means --file-system and prints junk, so an
# `a || b` fallback is wrong on Linux (review 1 of #77). GNU first, because BSD `stat` rejects -c outright.
if stat -c '%i %s %Y' "$log" >/dev/null 2>&1; then
  fstat() { stat -c '%i %s %Y' "$1" 2>/dev/null; }
else
  fstat() { stat -f '%i %z %m' "$1" 2>/dev/null; }
fi
FP=64   # how many bytes before the known end must still match for growth to count as an append
fingerprint() { [ "$2" -gt 0 ] || { echo 0; return; }; local from=$(( $2 > FP ? $2 - FP : 0 )); tail -c +"$(( from + 1 ))" "$1" 2>/dev/null | head -c "$(( $2 - from ))" | cksum; }

NL=$'\n'
HEAD_GLOB='## [0-9][0-9][0-9][0-9]-'   # the fleet's entry heading: `## YYYY-...`; a plain `## x` in a body is text
emit() {  # print one entry as one line, trailing blank lines trimmed; exit if nobody is reading any more
  local e="$1"
  while [ "${e%"$NL"}" != "$e" ]; do e="${e%"$NL"}"; done
  e="${e//$NL/ ⏎ }"
  [ -n "$e" ] || return 0
  printf '%s\n' "$e" || { save_state; exit 0; }
}
is_entry() { case "$1" in $HEAD_GLOB*) return 0 ;; *) return 1 ;; esac; }

inode=""; offset=0; mtime=""; fp=0
# The saved place is the START of any entry still pending, not the end of what was read, so an entry read but
# not yet printed when a run ends is read again by the next run (review 2 of #77). buf is always a suffix of
# the bytes read, and LC_ALL=C makes ${#buf} a byte count.
save_state() {
  [ -n "$state" ] && [ -n "$inode" ] && [ "$settle" = 0 ] || return 0
  local so=$(( offset - ${#buf} )) sfp=$fp
  [ "$so" = "$offset" ] || sfp=$(fingerprint "$log" "$so")
  mkdir -p "$(dirname "$state")" 2>/dev/null
  printf '%s %s %s\n' "$inode" "$so" "$sfp" > "$state.tmp" && mv -f "$state.tmp" "$state"
  return 0
}
notice() { printf 'xlog-follow: %s; read the log from your last-read stamp: %s\n' "$1" "$log" || exit 0; }
settle=0        # >0 while waiting for a cut or rewrite to finish: polls with no change still needed
buf=""          # the entry being collected: empty, or text that starts with a stamped heading
last_new=$SECONDS
resumed=0
RESUME_MAX=16384   # a resume gap, or one tick's growth, bigger than this prints one notice instead of the entries
MAX_HEADS=10       # more stamped headings than this in one tick's growth is a notice too

read -r inode size mtime <<< "$(fstat "$log")"
offset=${size:-0}; fp=$(fingerprint "$log" "$offset")
if [ -n "$state" ] && [ -f "$state" ]; then
  # Resume where the last run stopped (a Monitor lasts 30 minutes and is re-armed), if it is the same file
  # and the bytes before the saved end are unchanged. Otherwise start at the end, as without --state.
  read -r s_inode s_offset s_fp < "$state"
  if [ "$s_inode" = "$inode" ] && [ "${s_offset:-x}" -le "$offset" ] 2>/dev/null && [ "$(fingerprint "$log" "$s_offset")" = "$s_fp" ]; then
    if [ $(( offset - s_offset )) -gt "$RESUME_MAX" ]; then
      notice "$(( offset - s_offset )) bytes of new entries arrived since the last run, too many to print here"
    else
      offset=$s_offset; fp=$s_fp   # the loop reads the gap on its first tick
      resumed=1                    # that gap passed the fingerprint and size checks: no per-tick heading cap on it
    fi
  else
    # The log was replaced, cut or rewritten since the last run: what came in between cannot be told apart from
    # what was there, so say so rather than start at the end in silence (review 2 of #77).
    notice "the log changed since the last run (rewritten or replaced), so entries that came in between cannot be printed"
  fi
fi
save_state

while :; do
  sleep 1
  st=$(fstat "$log")
  if [ -z "$st" ]; then continue; fi          # missing for a moment, as during an atomic save
  read -r n_inode n_size n_mtime <<< "$st"

  if [ "$settle" -gt 0 ]; then
    # After a cut or rewrite, wait until the file stops changing, then take its end as the new start. A save
    # that truncates and rewrites in place can be caught empty or half written; its remaining bytes are not
    # an append (review 1 of #77).
    if [ "$n_inode" = "$inode" ] && [ "$n_size" = "$offset" ] && [ "$n_mtime" = "$mtime" ]; then
      settle=$(( settle - 1 ))
      if [ "$settle" = 0 ]; then fp=$(fingerprint "$log" "$offset"); save_state; fi
    else
      inode=$n_inode; offset=$n_size; mtime=$n_mtime; settle=2
    fi
    continue
  fi

  resync=0
  if [ "$n_inode" != "$inode" ] || [ "$n_size" -lt "$offset" ]; then
    resync=1                                   # replaced, or cut
  elif [ "$n_mtime" != "$mtime" ] && [ "$(fingerprint "$log" "$offset")" != "$fp" ]; then
    resync=1                                   # the bytes before the known end changed: a rewrite, whatever the size
  fi
  if [ "$resync" = 1 ]; then
    # A pending entry was appended before this change; print it rather than lose it (review 1 of #77).
    if is_entry "$buf"; then emit "$buf"; fi
    buf=""; inode=$n_inode; offset=$n_size; mtime=$n_mtime; settle=2
    continue
  fi
  mtime=$n_mtime

  if [ "$n_size" -gt "$offset" ]; then
    # Read the new bytes with a sentinel, IN THIS SHELL: a `$( )` around a helper would strip the chunk's
    # trailing newlines and glue the next chunk to it (review 1 of #77).
    chunk=$(tail -c +"$(( offset + 1 ))" "$log" 2>/dev/null | head -c "$(( n_size - offset ))"; printf x)
    chunk=${chunk%x}
    # One tick's growth that is too big to be appends (a rewrite that stalled past the settling window, or a
    # paste of old entries) prints one notice, never a replay (review 2 of #77).
    heads=0; rest_c="$NL$chunk"
    while case "$rest_c" in *"$NL"$HEAD_GLOB*) true ;; *) false ;; esac; do
      heads=$(( heads + 1 )); rest_c="${rest_c#*"$NL"$HEAD_GLOB}"; [ "$heads" -le "$MAX_HEADS" ] || break
    done
    # The heading cap does not apply to the first read after a good resume: that gap came in over time, and
    # --state already checked it (review 3 of #77).
    [ "$resumed" = 1 ] && heads=0
    resumed=0
    if [ $(( n_size - offset )) -gt "$RESUME_MAX" ] || [ "$heads" -gt "$MAX_HEADS" ]; then
      if is_entry "$buf"; then emit "$buf"; fi
      if [ "$heads" -gt "$MAX_HEADS" ]; then
        notice "more than $MAX_HEADS entries arrived at once, too many to be appends"
      else
        notice "$(( n_size - offset )) bytes arrived at once, too many to be appends"
      fi
      buf=""; offset=$n_size; fp=$(fingerprint "$log" "$offset"); last_new=$SECONDS; save_state
      continue
    fi
    buf="$buf$chunk"
    offset=$n_size; fp=$(fingerprint "$log" "$offset"); last_new=$SECONDS; save_state

    # Anything before the first stamped heading belongs to no entry we print (the gap between entries, or the
    # tail of an entry already printed). Keep only an unfinished last line, which may be a heading being written.
    if ! is_entry "$buf"; then
      case "$buf" in
        *"$NL"$HEAD_GLOB*) buf="${buf#*"$NL"}"; while ! is_entry "$buf"; do buf="${buf#*"$NL"}"; done ;;
        *"$NL"*) buf="${buf##*"$NL"}" ;;
      esac
    fi
    # Every stamped heading after the first closes the entry before it.
    while is_entry "$buf"; do
      rest="${buf#*"$NL"}"
      [ "$rest" != "$buf" ] || break
      # find the next line that is a stamped heading
      head="${buf%%"$NL"*}"; body=""; found=0
      while [ -n "$rest" ]; do
        if is_entry "$rest"; then found=1; break; fi
        line="${rest%%"$NL"*}"
        if [ "$line" = "$rest" ]; then break; fi   # an unfinished last line
        body="$body$NL$line"; rest="${rest#*"$NL"}"
      done
      [ "$found" = 1 ] || break
      emit "$head$body"
      buf="$rest"
    done
    save_state   # printed entries are saved as printed (review 3 of #77: a kill -9 printed one twice)
  fi

  # Quiet for 3 seconds: the pending entry is complete.
  if [ -n "$buf" ] && [ $(( SECONDS - last_new )) -ge 3 ]; then
    if is_entry "$buf"; then emit "$buf"; fi
    buf=""
    save_state
  fi
done
