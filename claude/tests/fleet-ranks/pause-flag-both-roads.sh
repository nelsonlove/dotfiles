#!/usr/bin/env bash
# The pause parser now lives once, at `claude/lib/pause-flag.sh`, and two callers at DIFFERENT DEPTHS find
# it by walking up to `.git`. This asserts the three things that can break that:
#
#   1. the shared file parses every note shape to the same state it did as two copies — the states are the
#      whole contract, and only `absent` and `clear` let anything proceed;
#   2. BOTH callers actually find and source it, from their own depths, and agree note by note;
#   3. a caller that CANNOT find it refuses in its own exit contract — exit 2 on the hook, exit 2 on the
#      gate rather than the 1 that tickle would read as a silent skip.
#
# It builds its own notes under a temp dir and never reads the fleet's real pause note, so it cannot pause
# or unpause anything. It runs the two callers with `--pause-note` / `PAUSE_NOTE` pointed at those temp
# files, and it never invokes a job.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
ROOT=$(cd "$HERE/../../.." && pwd -P)
LIB="$ROOT/claude/lib/pause-flag.sh"
HOOK="$ROOT/claude/hooks/pause-guard.sh"
GATE="$ROOT/tickle/scripts/_lib/pause-gate.sh"
TMP=$(mktemp -d -t pause-flag-test) || exit 1
trap 'rm -rf "$TMP"' EXIT
n=0; fails=0
eq() { n=$((n + 1)); if [ "$2" = "$3" ]; then printf 'PASS  %-54s %s\n' "$1" "$2"; else fails=$((fails + 1)); printf 'FAIL  %-54s got %s, want %s\n' "$1" "$2" "$3"; fi; }

note() {  # note <name> <content...>; prints the path
  printf '%s' "$2" > "$TMP/$1.md"
  printf '%s' "$TMP/$1.md"
}
PAUSED=$(note paused '---
paused: true
reason: Nelson said stop
---
body
')
CLEAR=$(note clear '---
paused: false
---
')
YES=$(note yes '---
paused: yes
---
')
NOKEY=$(note nokey '---
reason: no paused key here
---
')
UNCLOSED=$(note unclosed '---
paused: true
')
NOFENCE=$(note nofence 'not frontmatter
paused: true
')
JUNK=$(note junk '---
paused: maybe
---
')
COMMENT=$(note comment '---
paused: true  # with a trailing comment
---
')
QUOTED=$(note quoted '---
paused: "true"
---
')
CRLF="$TMP/crlf.md"; printf -- '---\r\npaused: true\r\n---\r\n' > "$CRLF"
ABSENT="$TMP/there-is-no-note.md"

echo "=== 1. the shared parser: every note shape to its state"
for pair in "$PAUSED:paused" "$CLEAR:clear" "$YES:paused" "$NOKEY:bad" "$UNCLOSED:bad" \
            "$NOFENCE:bad" "$JUNK:bad" "$COMMENT:paused" "$QUOTED:paused" "$CRLF:paused" "$ABSENT:absent"; do
  p=${pair%:*}; want=${pair##*:}
  got=$(PAUSE_NOTE="$p" bash -c '. "$1" && read_pause_flag && printf "%s" "$flag_state"' _ "$LIB")
  label="$(basename "$p") parses"
  eq "$label" "$got" "$want"
done

echo
# CAPTURE THE EXIT CODE ON ITS OWN LINE. `eq "on $(basename "$p")" "$?" "$want"` reads 0 every time,
# because the command substitution in the LABEL runs first and sets `$?` itself. That cost eight false
# failures here, and it is the same shape of mistake as a hand-quoted payload: a harness lying about the
# thing it measures.
echo "=== 2. both callers find it from their own depths, and agree"
# the hook: exit 0 allows, exit 2 blocks. A `bad` note must block, like a pause.
for pair in "$CLEAR:0" "$ABSENT:0" "$PAUSED:2" "$NOKEY:2" "$UNCLOSED:2" "$CRLF:2"; do
  p=${pair%:*}; want=${pair##*:}
  # a WRITE-shaped command: the hook lets reads through even during a pause (01.65 rule 10), so `echo hi`
  # would be allowed whatever the note says and asserting on it would prove nothing
  printf '%s' '{"tool_name":"Bash","tool_input":{"command":"printf x > /tmp/pause-flag-test-target"}}' | PAUSE_NOTE="$p" "$HOOK" >/dev/null 2>&1
  rc=$?
  label="hook on $(basename "$p")"
  eq "$label" "$rc" "$want"
done
# the gate: 0 runs the job, 1 skips it (only from the deliberate paused path), 2 is a failed check.
for pair in "$CLEAR:0" "$ABSENT:0" "$PAUSED:1" "$NOKEY:2" "$UNCLOSED:2" "$CRLF:1"; do
  p=${pair%:*}; want=${pair##*:}
  PAUSE_NOTE="$p" "$GATE" test-job >/dev/null 2>&1
  rc=$?
  label="gate on $(basename "$p")"
  eq "$label" "$rc" "$want"
done

echo
echo "=== 3. a caller that cannot find the parser refuses, in its own contract"
# Copy each caller to a directory with NO `.git` above it. The walk must fail and each must exit 2 —
# the gate especially, because tickle reads 1 as a skip and a skip here would be invisible.
ORPHAN="$TMP/orphan"; mkdir -p "$ORPHAN"
cp "$HOOK" "$ORPHAN/pause-guard.sh"; cp "$GATE" "$ORPHAN/pause-gate.sh"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"printf x > /tmp/pause-flag-test-target"}}' | PAUSE_NOTE="$CLEAR" "$ORPHAN/pause-guard.sh" >/dev/null 2>&1
rc=$?
eq "hook with no .git above it refuses" "$rc" 2
PAUSE_NOTE="$CLEAR" "$ORPHAN/pause-gate.sh" test-job >/dev/null 2>&1
rc=$?
eq "gate with no .git above it exits 2, not 1" "$rc" 2
msg=$(PAUSE_NOTE="$CLEAR" "$ORPHAN/pause-gate.sh" test-job 2>&1 >/dev/null | head -n 1)
case "$msg" in *"$ORPHAN"*) eq "the gate names the directory it searched from" yes yes ;; *) eq "the gate names the directory it searched from" "no: $msg" yes ;; esac

echo
echo "=== 4. read_frontmatter, the generalisation package 5 put into this SHIPPED file"
# `read_pause_flag` is now one caller of it and `claude/bin/notify-session.sh` is the other, which reads a
# queue note's `session:` key. Section 1 above can only see the states the pause road forwards, so these
# cases call the reader directly. Every one of them is about the SEAM rather than the block scanner: the
# block scanner is the same code section 1 already proves, note shape by note shape.
SESSNOTE=$(note session '---
title: a queue item
session: "[L0-FL] dotfiles"
verified: 2026-09-27T09:00
---
body
')
fm() {  # fm <note> [PAUSE_NOTE] -> "<state>|<count of session: lines in the block>"
  PAUSE_NOTE="${2:-$TMP/there-is-no-pause-note.md}" bash -c '
    set -u
    . "$1" || exit 9
    read_frontmatter "$2" || exit 8
    printf "%s|%s" "$flag_state" "$(printf "%s\n" "$flag_block" | grep -c "^session:" || true)"
  ' _ "$LIB" "$1"
}
eq "a good note reads, block carried out" "$(fm "$SESSNOTE")" "read|1"
eq "a missing path is absent" "$(fm "$TMP/no-such-note.md")" "absent|0"
eq "a directory is bad" "$(fm "$TMP")" "bad|0"
eq "no opening fence is bad" "$(fm "$NOFENCE")" "bad|0"
eq "an unclosed block is bad" "$(fm "$UNCLOSED")" "bad|0"
# IT MUST READ THE PATH IT IS GIVEN. The notifier reads queue notes while a Pause note exists, so a reader
# that quietly preferred $PAUSE_NOTE would hand back another note's frontmatter and the notifier would tell
# the wrong session. This is the one thing the generalisation could get wrong invisibly.
eq "it reads its argument, not PAUSE_NOTE" "$(fm "$SESSNOTE" "$PAUSED")" "read|1"
# AND IT MUST CLEAR WHAT THE LAST CALL LEFT: two calls in one shell, the second on a missing note. A block
# left over from the first would be read as the second note's frontmatter.
second=$(bash -c '
  set -u
  . "$1"
  read_frontmatter "$2"
  read_frontmatter "$3"
  printf "%s|%s" "$flag_state" "${flag_block:-empty}"
' _ "$LIB" "$SESSNOTE" "$TMP/no-such-note.md")
eq "a second call clears the first call's block" "$second" "absent|empty"
# THE PAUSE CONTRACT IS UNCHANGED BY THE SEAM: read_pause_flag still takes its note from PAUSE_NOTE, and an
# argument does not move it. Section 1 proves the states; this proves which file they came from.
got=$(PAUSE_NOTE="$PAUSED" bash -c '. "$1" && read_pause_flag "$2" && printf "%s" "$flag_state"' _ "$LIB" "$CLEAR")
eq "read_pause_flag still reads PAUSE_NOTE, not an argument" "$got" "paused"

printf '\n%s checks, %s failed\n' "$n" "$fails"
[ "$fails" = 0 ] || exit 1
