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
# THE ONE JUDGEMENT IN IT: the notice is cleared AFTER it is printed, and if the clear fails the notice is
# printed again next turn. Losing a ruling of his is worse than repeating one, so the failure falls that way
# deliberately rather than by accident.
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

[ -n "$sid" ] || exit 0
case "$event" in
  UserPromptSubmit) ;;
  SessionStart)
    [ "$source_reason" = "resume" ] || exit 0 ;;
  *) exit 0 ;;
esac

notice="$NOTICES_DIR/$sid.md"
[ -f "$notice" ] || exit 0
[ -r "$notice" ] || exit 0
[ -s "$notice" ] || { rm -f "$notice" 2>/dev/null || true; exit 0; }

body=$(cat "$notice" 2>/dev/null || true)
[ -n "$body" ] || exit 0

printf 'A queue item you are named on has been ruled on by Nelson. This is the notice, and it has been cleared:\n\n'
printf '%s\n' "$body"
printf '\nRead the note in full before acting on it — this notice is the summons, not the ruling.\n'

# Cleared last, and a failure here repeats the notice rather than losing it. See the header.
rm -f "$notice" 2>/dev/null || true
exit 0
