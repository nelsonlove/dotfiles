#!/usr/bin/env bash
# Tests for `xlog-follow.sh --once`: print the entries since the saved place, save the new place, and EXIT 0.
#
# The defect it fixes (2026-10-02): the fleet's rule says "run it once on wake", but the script had no once form, so each such run started a follower that never exited; [A0] rear admiral killed four orphans, one 15 hours old.
#
# ONLY A TEMP LOG AND A TEMP STATE FILE under a mktemp dir. The real log is never opened. Every run is bounded by a timeout, and a run that does not exit is a failure, not a hang.
#
# Run: bash claude/tests/xlog-follow/once.sh   (prints the check count; exits non-zero on any failure)
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
FOLLOW="$HERE/../../bin/xlog-follow.sh"
n=0; fails=0
eq() {  # eq <label> <got> <want>
  n=$((n + 1))
  if [ "$2" = "$3" ]; then printf 'PASS  %s\n' "$1"
  else fails=$((fails + 1)); printf 'FAIL  %s\n      got:  %s\n      want: %s\n' "$1" "$2" "$3"; fi
}

T=$(mktemp -d "${TMPDIR:-/tmp}/xlog-follow-once-test.XXXXXX") || exit 1
trap 'pkill -f "xlog-follow.sh --log $T" 2>/dev/null; /usr/bin/trash "$T" 2>/dev/null || true' EXIT
LOG="$T/CROSS-SESSION.md"; ST="$T/state/once"; OUT="$T/out"
seed() { printf -- '---\naudience: fleet\n---\n\n# Cross-session log\n\n## 2026-09-01T10:00 · [L0-CC] old — claim\nOld one.\n' > "$LOG"; }
entry() { printf '\n## %s · [L0-CC] test — claim\n%s\n' "$1" "$2" >> "$LOG"; }

# once [args]: run it with a 10 s limit; sets rc (124 = it did not exit) and the output in $OUT.
once() {
  bash "$FOLLOW" --log "$LOG" "$@" > "$OUT" 2>"$T/err" & local p=$! t=0
  while kill -0 "$p" 2>/dev/null && [ "$t" -lt 20 ]; do sleep 0.5; t=$((t + 1)); done
  if kill -0 "$p" 2>/dev/null; then kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; rc=124; else wait "$p"; rc=$?; fi
}
lines() { wc -l < "$OUT" | tr -d ' '; }

echo "=== 1. no saved place yet"
seed; once --once --state "$ST"
eq "a first run exits 0" "$rc" 0
eq "it prints one line" "$(lines)" 1
case "$(head -1 "$OUT")" in *"no saved place"*"no entries are printed"*) r=note ;; *) r="$(head -1 "$OUT")" ;; esac
eq "and that line says there was no saved place" "$r" note
eq "it saves the end of the log as the place" "$(test -s "$ST" && echo saved)" saved

echo "=== 2. what came since the place, then nothing"
entry "2026-10-02T08:00" "First new."; entry "2026-10-02T08:01" "Second new."
once --once --state "$ST"
eq "a second run exits 0" "$rc" 0
eq "it prints both new entries, the last one too" "$(lines)" 2
eq "first line is the first entry" "$(head -1 "$OUT")" "## 2026-10-02T08:00 · [L0-CC] test — claim ⏎ First new."
eq "second line is the last entry" "$(sed -n 2p "$OUT")" "## 2026-10-02T08:01 · [L0-CC] test — claim ⏎ Second new."
once --once --state "$ST"
eq "a third run with nothing new prints nothing" "$rc|$(lines)" "0|0"
entry "2026-10-02T08:02" "Third new."
once --once --state "$ST"
eq "a later run prints only what is new" "$rc|$(lines)|$(head -1 "$OUT")" "0|1|## 2026-10-02T08:02 · [L0-CC] test — claim ⏎ Third new."

echo "=== 3. a log rewritten since the last run"
seed; entry "2026-10-02T09:00" "After the rewrite."
once --once --state "$ST"
case "$(head -1 "$OUT")" in *"log changed since the last run"*) r=notice ;; *) r="$(head -1 "$OUT")" ;; esac
eq "one notice, exit 0" "$rc|$(lines)|$r" "0|1|notice"
entry "2026-10-02T09:01" "Next."
once --once --state "$ST"
eq "and the run after it reads on from the end it saved" "$rc|$(lines)|$(head -1 "$OUT")" "0|1|## 2026-10-02T09:01 · [L0-CC] test — claim ⏎ Next."

echo "=== 4. arguments"
once --once
eq "--once without --state is refused (exit 2)" "$rc" 2
case "$(cat "$T/err")" in *"--once needs --state"*) r=named ;; *) r="$(cat "$T/err")" ;; esac
eq "and it says why" "$r" named
eq "the help names the once form" "$(bash "$FOLLOW" --help | grep -c -- '--once --state')" 1

left=$(pgrep -f "xlog-follow.sh --log $T" | wc -l | tr -d ' ')
eq "no follower is left running" "$left" 0

EXPECTED=16
printf '\n%s checks (expected %s), %s failed\n' "$n" "$EXPECTED" "$fails"
[ "$n" = "$EXPECTED" ] || { echo "FAIL  the check count is $n, expected $EXPECTED"; exit 1; }
[ "$fails" = 0 ] || exit 1
