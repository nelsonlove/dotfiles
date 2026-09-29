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
# Every follower this suite started, whatever wrapped it: a subshell's PID is not the follower's (review 1 of #77).
killall_followers() { pkill -f "xlog-follow.sh --log $T" 2>/dev/null; true; }
trap 'stop; killall_followers; /usr/bin/trash "$T" 2>/dev/null || true' EXIT

LOG="$T/CROSS-SESSION.md"; OUT="$T/out"
seed() {  # a log with two old entries, the shape of the real one
  printf -- '---\naudience: fleet\n---\n\n# Cross-session log\n\n## 2026-09-01T10:00 · [L0-CC] old — claim\nOld one.\n\n## 2026-09-01T10:01 · [L0-CC] old — release\nOld two.\n' > "$LOG"
}
start() { : > "$OUT"; bash "$FOLLOW" --log "$LOG" "$@" > "$OUT" 2>"$T/err" & PID=$!; sleep 1.5; }
lines() { wc -l < "$OUT" | tr -d ' '; }
# Wait until the follower has printed at least N lines (up to 20 s), then one more second for any extra line.
# Fixed sleeps were too tight when the machine's load reached 45; a wait on the output is not.
waitfor() { local t=0; while [ "$(lines)" -lt "$1" ] && [ "$t" -lt 40 ]; do sleep 0.5; t=$((t + 1)); done; sleep 1; }
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
waitfor 1
eq "one line" "$(lines)" 1
eq "the line is the whole entry, newlines joined" "$(head -1 "$OUT")" "## 2026-09-29T05:00 · [L0-CC] test — claim ⏎ Line one. ⏎ Line two."
stop

echo "=== 3. two quick appends give two lines"
seed; start
entry "2026-09-29T05:01" "First."; entry "2026-09-29T05:02" "Second."
waitfor 2
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
waitfor 1
eq "an entry after the cut prints once" "$(lines)" 1
eq "and it is that entry" "$(head -1 "$OUT")" "## 2026-09-29T05:04 · [L0-CC] test — claim ⏎ After the cut."
stop

echo "=== 5. a partial entry waits for its end"
seed; start
printf '\n## 2026-09-29T05:05 · [L0-CC] test — claim\nHalf' >> "$LOG"
sleep 1.5
eq "a partial entry is not printed at once" "$(lines)" 0
printf ' and whole.\n' >> "$LOG"
waitfor 1
eq "after 3 s of quiet it is printed, whole" "$(head -1 "$OUT")" "## 2026-09-29T05:05 · [L0-CC] test — claim ⏎ Half and whole."
stop
seed; start
printf '\n## 2026-09-29T05:06 · [L0-CC] test — claim\nBody' >> "$LOG"
sleep 1.2
printf ' end.\n\n## 2026-09-29T05:07 · [L0-CC] test — claim\nNext' >> "$LOG"
# The first entry is closed by the heading; the second waits for 3 s of quiet. If the heading did not close
# the first, both would print in the same tick, after the quiet, and the count below would be 2.
t=0; while [ "$(lines)" -lt 1 ] && [ "$t" -lt 40 ]; do sleep 0.25; t=$((t + 1)); done
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
waitfor 1
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

echo "=== 9. review 1 of #77: split writes, headings, rewrites, resume, GNU stat"
# 9a. An append with no leading blank line, then another in the next poll: two entries, not one glued line.
seed; start
printf '## 2026-09-29T06:00 · [L0-CC] test — claim\nBody a.\n' >> "$LOG"; sleep 1.5
printf '## 2026-09-29T06:01 · [L0-CC] test — claim\nBody b.\n' >> "$LOG"; waitfor 2
eq "no leading blank line, two polls: two lines" "$(lines)" 2
eq "and the first is whole, not glued" "$(sed -n 1p "$OUT")" "## 2026-09-29T06:00 · [L0-CC] test — claim ⏎ Body a."
stop
# 9b. A body line that arrives a poll later keeps its line break.
seed; start
printf '\n## 2026-09-29T06:02 · [L0-CC] test — claim\nline1\n' >> "$LOG"; sleep 1.5
printf 'line2\n' >> "$LOG"; waitfor 1
eq "a body split across polls keeps its line break" "$(head -1 "$OUT")" "## 2026-09-29T06:02 · [L0-CC] test — claim ⏎ line1 ⏎ line2"
stop
# 9c. A `## ` line inside a body that is not a stamped heading does not split the entry.
seed; start
printf '\n## 2026-09-29T06:03 · [A0] rear admiral — ruling\nQuoted:\n## Decision\nText.\n' >> "$LOG"; waitfor 1
eq "a sub-heading in a body stays in its entry" "$(lines)|$(head -1 "$OUT")" "1|## 2026-09-29T06:03 · [A0] rear admiral — ruling ⏎ Quoted: ⏎ ## Decision ⏎ Text."
stop
# 9d. A truncate-then-rewrite in place, caught half written, is not read as an append.
seed; for i in $(seq 1 30); do entry "2026-09-28T0$((i % 10)):00" "Filler $i."; done
cp "$LOG" "$T/full"; start
: > "$LOG"; sleep 1.3                       # the poll sees the file at size 0
head -c 200 "$T/full" >> "$LOG"; sleep 1.3  # then part-written
tail -c +201 "$T/full" >> "$LOG"; sleep 5   # then whole again
eq "a slow rewrite in place prints nothing" "$(lines)" 0
entry "2026-09-29T06:04" "After the slow rewrite."; waitfor 1
eq "and the next append prints once" "$(lines)|$(head -1 "$OUT")" "1|## 2026-09-29T06:04 · [L0-CC] test — claim ⏎ After the slow rewrite."
stop
# 9e. A same-size rewrite near the end does not make the next real append look like a rewrite.
seed; start
python3 - "$LOG" <<'PYX'
import sys; p=sys.argv[1]; b=open(p,'rb').read(); open(p,'wb').write(b[:-5]+b'TWO.\n')
PYX
sleep 8     # past the two polls of settling, which the header documents (slow polls under load)
entry "2026-09-29T06:05" "After a same-size edit."; waitfor 1
eq "an append after a same-size edit still prints" "$(lines)|$(head -1 "$OUT")" "1|## 2026-09-29T06:05 · [L0-CC] test — claim ⏎ After a same-size edit."
stop
# 9f. --state: a re-armed follower resumes where the last one stopped, and prints what came in between.
seed; ST="$T/state"; start --state "$ST"; stop
entry "2026-09-29T06:06" "While nobody was watching."
start --state "$ST"; waitfor 1
eq "--state resumes and prints the gap" "$(lines)|$(head -1 "$OUT")" "1|## 2026-09-29T06:06 · [L0-CC] test — claim ⏎ While nobody was watching."
stop
# 9g. --state after a big gap prints one notice, never a flood.
for i in $(seq 1 90); do entry "2026-09-29T07:$((10 + i % 50))" "Gap $i $(printf '%0200d' 0)"; done   # about 23 KB, over the 16 KB cap
start --state "$ST"; waitfor 1; sleep 2
eq "a big gap gives one notice line" "$(lines)" 1
case "$(head -1 "$OUT")" in *"read the log"*) r=notice ;; *) r="$(head -1 "$OUT")" ;; esac
eq "and the line says to read the log" "$r" notice
stop
# 9i. Review 2 of #77: an entry still pending when the run ends is printed by the next run, not lost.
seed; ST2="$T/state2"; start --state "$ST2"
printf '\n## 2026-09-29T06:08 · [L0-CC] test — claim\nPending at the end.\n' >> "$LOG"; sleep 1.3
stop
start --state "$ST2"; waitfor 1
eq "a pending entry at the end of a run is printed by the next" "$(lines)|$(head -1 "$OUT")" "1|## 2026-09-29T06:08 · [L0-CC] test — claim ⏎ Pending at the end."
stop
# 9j. A state file that no longer fits the log (rewritten between runs) prints one notice, not silence.
seed; ST3="$T/state3"; start --state "$ST3"; stop
printf -- '---\naudience: fleet\n---\n\n# Cleared\n\n## 2026-09-29T06:09 · [L0-CC] test — claim\nAfter a clear-out.\n' > "$LOG"
start --state "$ST3"; waitfor 1
case "$(head -1 "$OUT")" in *"read the log"*) r=notice ;; *) r="$(head -1 "$OUT")" ;; esac
eq "an unusable state file gives one notice" "$(lines)|$r" "1|notice"
stop
# 9k. A rewrite that stalls longer than the settling window, then writes many entries at once: one notice line,
# never a replay (review 2 of #77 replayed 29 old entries this way).
seed; for i in $(seq 1 60); do entry "2026-09-28T0$((i % 10)):00" "Filler $i $(printf '%0100d' 0)."; done
cp "$LOG" "$T/full2"; start
: > "$LOG"; head -c 1000 "$T/full2" >> "$LOG"; sleep 4.5
tail -c +1001 "$T/full2" >> "$LOG"; waitfor 1; sleep 3
case "$(head -1 "$OUT")" in *"read the log"*) r=notice ;; *) r="$(head -1 "$OUT")" ;; esac
eq "a stalled rewrite gives at most one notice line" "$(lines)|$r" "1|notice"
stop

# 9l. Review 3 of #77: a small resume gap with many short entries prints them all; the per-tick cap is for
# rewrites, not for a gap that --state has already checked.
seed; ST4="$T/state4"; start --state "$ST4"; stop
for i in $(seq 10 21); do entry "2026-09-29T08:$i" "Short $i."; done
start --state "$ST4"; waitfor 12
eq "a checked resume gap of 12 short entries prints all 12" "$(lines)" 12
stop
# 9m. An entry printed after quiet is saved as printed: a kill -9 then does not print it again.
seed; ST5="$T/state5"; start --state "$ST5"
entry "2026-09-29T08:30" "Once."; waitfor 1; sleep 1
kill -KILL "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; PID=""
start --state "$ST5"; sleep 4
eq "after kill -9, the printed entry is not printed again" "$(lines)" 0
stop

# 9n. Review 4 of #77: a quiet re-arm (a resume with no gap) does not switch off the cap for a later stalled
# rewrite.
seed; for i in $(seq 1 30); do entry "2026-09-28T0$((i % 10)):11" "Filler $i."; done
ST6="$T/state6"; start --state "$ST6"; sleep 4; stop
cp "$LOG" "$T/full3"; start --state "$ST6"
: > "$LOG"; head -c 300 "$T/full3" >> "$LOG"; sleep 4.5
tail -c +301 "$T/full3" >> "$LOG"; waitfor 1; sleep 3
case "$(head -1 "$OUT")" in *"read the log"*) r=notice ;; *) r="$(head -1 "$OUT")" ;; esac
eq "a quiet re-arm, then a stalled rewrite: one notice" "$(lines)|$r" "1|notice"
stop

# 9o. Follow-ups of #83. --help is the header and nothing else.
h=$(bash "$FOLLOW" --help 2>&1); hrc=$?
case "$h" in *"USAGE"*) r=has-usage ;; *) r=no-usage ;; esac
case "$h" in *"LC_ALL=C"*|*"set -u"*) r="$r+code" ;; esac
eq "--help prints the header, and no code" "$hrc|$r" "0|has-usage"
# 9p. --state must be a file: a directory, or a path ending in / (an empty CLAUDE_CODE_SESSION_ID gives one), is refused.
mkdir -p "$T/statedir"
# Bounded: a follower that does NOT refuse runs forever, so each runs in the background and counts as "running" if it is still alive after 10 s (a first version of this case ran it in the foreground and hung the suite).
bounded_rc() { bash "$FOLLOW" --log "$LOG" --state "$1" >/dev/null 2>&1 & local p=$! t=0; while kill -0 "$p" 2>/dev/null && [ "$t" -lt 20 ]; do sleep 0.5; t=$((t + 1)); done; if kill -0 "$p" 2>/dev/null; then kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; echo running; else wait "$p"; echo $?; fi; }
r1=$(bounded_rc "$T/statedir"); r2=$(bounded_rc "$T/nosuch/")
eq "--state refuses a directory and a path ending in /" "$r1|$r2" "2|2"
# 9q. A notice whose pipe is closed still moves the saved place, so the next run does not repeat it.
seed; ST7="$T/state7"
( bash "$FOLLOW" --log "$LOG" --state "$ST7" | true ) & HP=$!
sleep 1.5
# The burst is ONE append, so one poll sees all of it (entry by entry it took over a second, the first poll saw part of it, and the rest correctly gave the next run a gap notice).
for i in $(seq 1 90); do printf '\n## 2026-09-29T09:%s · [L0-CC] test — claim\nBurst %s %s\n' "$((10 + i % 50))" "$i" "$(printf '%0200d' 0)"; done > "$T/burst"
cat "$T/burst" >> "$LOG"
sleep 4; killall_followers; wait "$HP" 2>/dev/null
start --state "$ST7"; sleep 4
eq "a notice lost to a closed pipe is not printed again" "$(lines)" 0
stop

# 9h. GNU stat: with a GNU `stat` first on PATH, it still follows (tested with gstat where it exists).
if command -v gstat >/dev/null 2>&1; then
  mkdir -p "$T/gnu"; ln -sf "$(command -v gstat)" "$T/gnu/stat"
  seed; : > "$OUT"; PATH="$T/gnu:$PATH" bash "$FOLLOW" --log "$LOG" > "$OUT" 2>"$T/err" & PID=$!; sleep 1.5
  entry "2026-09-29T06:07" "Under GNU stat."; waitfor 1
  eq "GNU stat: one append, one line" "$(lines)|$(head -1 "$OUT")" "1|## 2026-09-29T06:07 · [L0-CC] test — claim ⏎ Under GNU stat."
  stop
else
  eq "GNU stat: one append, one line" "skipped: no gstat on this host" "skipped: no gstat on this host"; printf '      (counted as a pass only because gstat is missing; install coreutils to run it)\n'
fi

echo "=== 8. it stops cleanly"
seed; start
kill -TERM "$PID"; sleep 1.5
if kill -0 "$PID" 2>/dev/null; then eq "SIGTERM ends it" alive gone; else eq "SIGTERM ends it" gone gone; fi
wait "$PID" 2>/dev/null; PID=""
seed; ( bash "$FOLLOW" --log "$LOG" | head -1 >/dev/null ) & HP=$!
sleep 1.5; entry "2026-09-29T05:12" "One."; entry "2026-09-29T05:13" "Two."
sleep 5
if kill -0 "$HP" 2>/dev/null; then eq "a closed pipe ends it" alive gone; killall_followers; else eq "a closed pipe ends it" gone gone; fi
left=$(pgrep -f "xlog-follow.sh --log $LOG" | wc -l | tr -d ' ')
eq "no follower is left running" "$left" 0

EXPECTED=40
printf '\n%s checks (expected %s), %s failed\n' "$n" "$EXPECTED" "$fails"
[ "$n" = "$EXPECTED" ] || { echo "FAIL  the check count is $n, expected $EXPECTED"; exit 1; }
[ "$fails" = 0 ] || exit 1
