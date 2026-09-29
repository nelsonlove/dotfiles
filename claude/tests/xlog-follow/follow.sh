#!/usr/bin/env bash
# Tests for claude/bin/xlog-follow.sh, the cross-session log follower whose every stdout line is one whole entry,
# so that under Monitor the event IS the entry (Nelson, relayed by [C0-CC] claude code, 2026-09-29).
#
# ONLY A TEMP LOG. Each case starts the follower on a fixture log in a temp dir, writes to that log, waits a
# bounded time, reads what the follower printed, and kills it. The real log is never opened.
#
# Run: bash claude/tests/xlog-follow/follow.sh   (prints the check count; exits non-zero on any failure)
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
FOLLOW="$HERE/../../bin/xlog-follow.sh"
n=0; fails=0
eq() {  # eq <label> <got> <want>
  n=$((n + 1))
  if [ "$2" = "$3" ]; then printf 'PASS  %s\n' "$1"
  else fails=$((fails + 1)); printf 'FAIL  %s\n      got:  %s\n      want: %s\n' "$1" "$2" "$3"; fi
}

T=$(mktemp -d "${TMPDIR:-/tmp}/xlog-follow-test.XXXXXX") || exit 1
PID=""
stop() { [ -n "$PID" ] && { kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; }; PID=""; }
trap 'stop; /usr/bin/trash "$T" 2>/dev/null || true' EXIT

LOG="$T/CROSS-SESSION.md"; OUT="$T/out"
seed() {  # a log with two old entries, the shape of the real one
  printf -- '---\naudience: fleet\n---\n\n# Cross-session log\n\n## 2026-09-01T10:00 · [L0-CC] old — claim\nOld one.\n\n## 2026-09-01T10:01 · [L0-CC] old — release\nOld two.\n' > "$LOG"
}
start() { : > "$OUT"; bash "$FOLLOW" --log "$LOG" > "$OUT" 2>"$T/err" & PID=$!; sleep 1.5; }
lines() { wc -l < "$OUT" | tr -d ' '; }
entry() {  # entry <stamp> <text>: append one whole entry, the way the fleet appends
  printf '\n## %s · [L0-CC] test — claim\n%s\n' "$1" "$2" >> "$LOG"
}

echo "=== 1. no replay on start"
seed; start; sleep 4
eq "nothing is printed for the entries already there" "$(lines)" 0
stop

echo "=== 2. one append gives one line, the whole entry"
seed; start
entry "2026-09-29T05:00" $'Line one.\nLine two.'
sleep 5
eq "one line" "$(lines)" 1
eq "the line is the whole entry, newlines joined" "$(head -1 "$OUT")" "## 2026-09-29T05:00 · [L0-CC] test — claim ⏎ Line one. ⏎ Line two."
stop

echo "=== 3. two quick appends give two lines"
seed; start
entry "2026-09-29T05:01" "First."; entry "2026-09-29T05:02" "Second."
sleep 5
eq "two lines" "$(lines)" 2
eq "in order, first" "$(sed -n 1p "$OUT")" "## 2026-09-29T05:01 · [L0-CC] test — claim ⏎ First."
eq "in order, second" "$(sed -n 2p "$OUT")" "## 2026-09-29T05:02 · [L0-CC] test — claim ⏎ Second."
stop

echo "=== 4. a cut does not flood"
seed; for i in $(seq 1 40); do entry "2026-09-28T0$((i % 10)):00" "Filler $i."; done
start
# The same file, rewritten shorter in place (the inode stays): the size goes down.
printf -- '---\naudience: fleet\n---\n\n# Cross-session log\n\n## 2026-09-29T05:03 · [L0-CC] kept — ruling\nKept.\n' > "$LOG"
sleep 5
eq "the cut prints nothing" "$(lines)" 0
entry "2026-09-29T05:04" "After the cut."
sleep 5
eq "an entry after the cut prints once" "$(lines)" 1
eq "and it is that entry" "$(head -1 "$OUT")" "## 2026-09-29T05:04 · [L0-CC] test — claim ⏎ After the cut."
stop

echo "=== 5. a partial entry waits for its end"
seed; start
printf '\n## 2026-09-29T05:05 · [L0-CC] test — claim\nHalf' >> "$LOG"
sleep 1.5
eq "a partial entry is not printed at once" "$(lines)" 0
printf ' and whole.\n' >> "$LOG"
sleep 5
eq "after 3 s of quiet it is printed, whole" "$(head -1 "$OUT")" "## 2026-09-29T05:05 · [L0-CC] test — claim ⏎ Half and whole."
stop
seed; start
printf '\n## 2026-09-29T05:06 · [L0-CC] test — claim\nBody' >> "$LOG"
sleep 1.2
printf ' end.\n\n## 2026-09-29T05:07 · [L0-CC] test — claim\nNext' >> "$LOG"
sleep 1.5
eq "the next heading completes the first entry at once" "$(head -1 "$OUT")" "## 2026-09-29T05:06 · [L0-CC] test — claim ⏎ Body end."
eq "and the second still waits" "$(lines)" 1
stop

echo "=== 6. an atomic rename re-syncs with no replay"
seed; start
cp "$LOG" "$T/new"
printf '\n## 2026-09-29T05:09 · [L0-CC] test — claim\nWritten by a save.\n' >> "$T/new"
mv "$T/new" "$LOG"
sleep 5
eq "a rename that grows the file prints nothing" "$(lines)" 0
entry "2026-09-29T05:10" "After the rename."
sleep 5
eq "an entry after the rename prints once" "$(lines)" 1
eq "and it is that entry" "$(head -1 "$OUT")" "## 2026-09-29T05:10 · [L0-CC] test — claim ⏎ After the rename."
stop

echo "=== 7. a rewrite in place that grows the file is not read as an append"
seed; start
# Same inode, bigger size, but the bytes before the old end are different: a rewrite, not an append. The new
# text holds several whole entries past the old end, so a follower that read it as an append WOULD print them
# (a first version of this case wrote no heading past the old end, and it passed with the check removed).
{ printf -- '---\naudience: fleet\n---\n\n# Rewritten\n'
  for i in 1 2 3 4 5 6; do printf '\n## 2026-09-29T05:1%s · [L0-CC] test — claim\nRewritten entry %s, long enough to reach past the old end of the file.\n' "$i" "$i"; done
} > "$LOG.tmp"; cat "$LOG.tmp" > "$LOG"; /usr/bin/trash "$LOG.tmp" 2>/dev/null || mv "$LOG.tmp" "$T/gone.tmp"
sleep 5
eq "the rewrite prints nothing" "$(lines)" 0
stop

echo "=== 8. it stops cleanly"
seed; start
kill -TERM "$PID"; sleep 1.5
if kill -0 "$PID" 2>/dev/null; then eq "SIGTERM ends it" alive gone; else eq "SIGTERM ends it" gone gone; fi
wait "$PID" 2>/dev/null; PID=""
seed; ( bash "$FOLLOW" --log "$LOG" | head -1 >/dev/null ) & HP=$!
sleep 1.5; entry "2026-09-29T05:12" "One."; entry "2026-09-29T05:13" "Two."
sleep 5
if kill -0 "$HP" 2>/dev/null; then eq "a closed pipe ends it" alive gone; kill "$HP" 2>/dev/null; else eq "a closed pipe ends it" gone gone; fi
left=$(pgrep -f "xlog-follow.sh --log $LOG" | wc -l | tr -d ' ')
eq "no follower is left running" "$left" 0

EXPECTED=20
printf '\n%s checks (expected %s), %s failed\n' "$n" "$EXPECTED" "$fails"
[ "$n" = "$EXPECTED" ] || { echo "FAIL  the check count is $n, expected $EXPECTED"; exit 1; }
[ "$fails" = 0 ] || exit 1
