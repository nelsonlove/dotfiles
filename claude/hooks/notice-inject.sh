#!/usr/bin/env bash
# notice-inject.sh — put a waiting notice into a session's context, and clear it.
#
# The other half of `claude/bin/notify-session.sh`. That script writes a notice at
# `~/.claude/notices/<sessionId>.md` when Nelson verifies or answers a queue item; this reads the one
# addressed to THIS session and prints it, which is how it reaches the model's context.
#
# REGISTERED ON `UserPromptSubmit` AND ON `SessionStart` WITH REASON `resume`, the same timing as
# `notebook-name-sync.sh` beside it, and for the same reason: those are the two moments a session is about
# to think. A fresh start has nothing waiting for it under its own id, and a clear or a compact is not a new
# turn. Ruled with the rest of the notifier in the queue note "Rule the two calls in the verified-item
# notifier before it is built".
#
# IT REFUSES NOTHING, so it needs no soak — the rule for a fleet-wide hook that can refuse does not reach
# one that cannot. What it must never do is BLOCK A TURN, so every path exits 0, including every failure:
# no jq, no session id, an unreadable notice, a notice that cannot be cleared. A notifier that can stop
# Nelson's session from thinking is worse than a notice that never arrives.
#
# THE ONE JUDGEMENT IN IT: a notice is never lost in preference to never being repeated. The review of #63
# found the first version losing one anyway, in a window it had not thought about — it read the file, printed
# it, then deleted it, so a notice APPENDED between the read and the delete was deleted unread, which is
# exactly the case the notifier's append-never-overwrite design exists for. So the file is now MOVED ASIDE
# FIRST, under a name carrying this process's pid, and only then read and printed and removed: after the
# move, an append by the notifier creates a fresh file that the next turn picks up, and nothing can be
# written into the file being deleted. If this process dies between the move and the print, the moved file
# stays on disk as `<sid>.md.reading.<pid>`, and the next run prints any of those it finds before the current
# notice — so the crash window repeats a notice rather than losing it, which is the way the whole hook falls.
#
# THE SESSION ID IS VALIDATED BEFORE IT BECOMES A PATH. `session_id` comes from Claude Code, so a hostile
# value is not reachable today, but the hook DELETES what it prints: a `../` in that field would have printed
# an arbitrary file into the model's context and then removed it. It must be a full 36-character id and
# nothing else, which is the same shape `wake-session.sh` insists on for the same kind of reason.
#
# `session_id` in the hook payload is the sessionId, which is exactly the key the notifier writes under — so
# no lookup is needed here, and this hook never reads the session registry or the fleet log.
#
# Works under /bin/bash 3.2 (macOS). Needs jq.

set -u

NOTICES_DIR="${NOTIFY_NOTICES_DIR:-$HOME/.claude/notices}"

input=$(cat 2>/dev/null || true)
[ -n "$input" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

event=$(printf '%s' "$input" | jq -r '.hook_event_name // ""' 2>/dev/null || echo "")
sid=$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null || echo "")
source_reason=$(printf '%s' "$input" | jq -r '.source // .reason // ""' 2>/dev/null || echo "")

# A full sessionId, or nothing happens. No slashes, no dots, no traversal — see the header.
case "$sid" in
  ????????-????-????-????-????????????) ;;
  *) exit 0 ;;
esac
case "$sid" in
  *[!0-9a-fA-F-]*) exit 0 ;;
esac

case "$event" in
  UserPromptSubmit) ;;
  SessionStart)
    [ "$source_reason" = "resume" ] || exit 0 ;;
  *) exit 0 ;;
esac

notice="$NOTICES_DIR/$sid.md"
reading="$notice.reading.$$"

# Anything a previous run moved aside and did not finish printing comes first, so a notice is delivered even
# across a crash. An array rather than a newline-joined string, and no pipeline: a `while read` on the far
# side of a `|` runs in a subshell, where the flag saying whether anything was printed cannot come back.
files=()
for f in "$notice".reading.*; do
  [ -e "$f" ] || continue
  [ "$f" = "$reading" ] && continue
  files+=("$f")
done

if [ -f "$notice" ] && [ -r "$notice" ]; then
  if [ -s "$notice" ]; then
    # Moved aside BEFORE it is read: an append that arrives now lands in a fresh file for the next turn.
    if mv "$notice" "$reading" 2>/dev/null; then files+=("$reading"); fi
  else
    rm -f "$notice" 2>/dev/null || true
  fi
fi

printed_any=0
if [ "${#files[@]}" -gt 0 ]; then
  for f in "${files[@]}"; do
    if [ ! -s "$f" ]; then rm -f "$f" 2>/dev/null || true; continue; fi
    if [ "$printed_any" = 0 ]; then
      printf 'A queue item you are named on has been ruled on by Nelson. This is the notice, and it has been cleared:\n\n'
      printed_any=1
    fi
    cat "$f" 2>/dev/null || true
    # Removed only after it has been printed. A failure here repeats the notice next turn, which is the way
    # this hook falls on purpose.
    rm -f "$f" 2>/dev/null || true
  done
fi

if [ "$printed_any" = 1 ]; then
  printf '\nRead the note in full before acting on it — this notice is the summons, not the ruling.\n'
fi

exit 0
