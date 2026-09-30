#!/usr/bin/env bash
# The notifier's dedupe and audience (Nelson, 2026-09-30, "a", all four picks, on `01.65 Operator's console/Tell the filing session
# when Nelson verifies, answers or asks for a revision.md`), end to end, WITHOUT NOTIFYING ANYTHING REAL.
#
# Everything is a fixture: a stub `claude` that prints a listing this file writes, a fake wake script that only records its
# arguments, fixture notes, a fixture notebook root (`NOTIFY_AGENTS_DIR`), a temp state directory (`NOTIFY_STATE_DIR`) and a
# temp fleet log (`NOTIFY_FLEET_LOG`). No live session id is used, no session is woken, and the real state file is never read.
#
# Covered: a first notify; a repeat is a no-op; two concurrent calls give one notice; a failed send is not recorded; the revise
# and for-agent keys; an ended L0 goes to its dispatcher; a free-text session with a caller-named captain, and without one; old
# callers with no uid; a list-form `session:`.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
ROOT=$(cd "$HERE/../../.." && pwd -P)
NOTIFY="$ROOT/claude/bin/notify-session.sh"
TMP=$(mktemp -d -t notify-dedupe) || exit 1
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
export NOTIFY_NOTICES_DIR="$TMP/notices"
export NOTIFY_FLEET_LOG="$TMP/log.md"
export NOTIFY_WAKE_SCRIPT="$TMP/fake-wake.sh"
export NOTIFY_STATE_DIR="$TMP/state"
export NOTIFY_AGENTS_DIR="$TMP/agents"
NB="$NOTIFY_AGENTS_DIR/03.04 Records/Agent notebook/2026-09"
AR="$NOTIFY_AGENTS_DIR/03.09 Archive/Agent notebook/2026-09"
mkdir -p "$NOTIFY_NOTICES_DIR" "$NB" "$AR"
: > "$NOTIFY_FLEET_LOG"
cat > "$NOTIFY_WAKE_SCRIPT" <<'FAKE'
#!/usr/bin/env bash
# [test artifact] records that it was called, and with what; wakes nothing.
printf '%s\n' "$*" >> "$(dirname "$0")/wake-calls.log"
exit 0
FAKE
chmod +x "$NOTIFY_WAKE_SCRIPT"
: > "$TMP/wake-calls.log"

n=0; fails=0
pass() { n=$((n + 1)); printf 'PASS  %s\n' "$1"; }
fail() { n=$((n + 1)); fails=$((fails + 1)); printf 'FAIL  %-66s %s\n' "$1" "${2:-}"; }
check() {  # check <label> <command...>: pass when the command succeeds
  local label="$1"; shift
  if "$@"; then pass "$label"; else fail "$label"; fi
}

STUBBIN="$TMP/stubbin"; mkdir -p "$STUBBIN"
cat > "$STUBBIN/claude" <<'STUB'
#!/usr/bin/env bash
# [test artifact — safe to delete] a fake `claude` that only answers `agents --json --all`.
case "$*" in
  *agents*) cat "$(dirname "$0")/../listing.json" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$STUBBIN/claude"
listing() { printf '%s' "$1" > "$TMP/listing.json"; }
run() { PATH="$STUBBIN:$PATH" "$NOTIFY" "$@" 2>&1; }

qnote() {  # qnote <file> <uid-or-empty> <session line(s), raw YAML>
  local f="$TMP/$1.md"
  {
    printf -- '---\ntype: Task/Decision\n'
    [ -z "$2" ] || printf 'uid: %s\n' "$2"
    printf '%s\n' "$3"
    printf 'status: draft/proposed\n---\n\n# %s\n' "$1"
  } > "$f"
  printf '%s' "$f"
}
entry() {  # entry <file stamp> <root> <session> <session-id> <status> <reports-to>
  cat > "$2/Agent session $1 fixture.md" <<EOF
---
type: Event/AgentNotebookEntry
session: "$3"
status: $5
session-id: $4
agent: lieutenant
cwd: /tmp
reports-to: "$6"
---

# fixture entry
EOF
}
lines() { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }
log_entries() { grep -c '^## ' "$NOTIFY_FLEET_LOG" 2>/dev/null || true; }
last_heading() { grep '^## ' "$NOTIFY_FLEET_LOG" | tail -n 1; }
log_tail() { awk '/^## /{buf=$0; next} {buf=buf" "$0} END{print buf}' "$NOTIFY_FLEET_LOG" 2>/dev/null; }
SENT="$NOTIFY_STATE_DIR/sent.jsonl"

SID_RUN="aaaaaaaa-1111-2222-3333-444444444444"
SID_END="bbbbbbbb-1111-2222-3333-444444444444"
SID_C1="cccccccc-1111-2222-3333-444444444444"
SID_CAP="dddddddd-1111-2222-3333-444444444444"
SID_RA="eeeeeeee-1111-2222-3333-444444444444"
SID_RUNL0="ffffffff-1111-2222-3333-444444444444"
SID_FREE="99999999-1111-2222-3333-444444444444"
UID1="f89960cb-026a-4bf9-89d7-4b99c069ba04"
UID2="6aec4ec7-48f9-4370-b7cd-9df7b5125ccd"
UID3="11111111-2222-3333-4444-555555555555"
UID4="22222222-2222-3333-4444-555555555555"
UID5="33333333-2222-3333-4444-555555555555"

BASE_LISTING="[
 {\"id\":\"run1\",\"sessionId\":\"$SID_RUN\",\"name\":\"[C1-CC] running one\",\"status\":\"idle\"},
 {\"id\":\"end1\",\"sessionId\":\"$SID_END\",\"name\":\"[L0-CC] ended one\",\"status\":null},
 {\"id\":\"runl0\",\"sessionId\":\"$SID_RUNL0\",\"name\":\"[L0-CC] live one\",\"status\":null},
 {\"id\":\"c1\",\"sessionId\":\"$SID_C1\",\"name\":\"[C1-CC] plugins\",\"status\":\"idle\"},
 {\"id\":\"cap\",\"sessionId\":\"$SID_CAP\",\"name\":\"[C0-OB] obsidian\",\"status\":\"idle\"},
 {\"id\":\"ra\",\"sessionId\":\"$SID_RA\",\"name\":\"[A0] rear admiral\",\"status\":\"idle\"},
 {\"id\":\"free\",\"sessionId\":\"$SID_FREE\",\"name\":\"fileclass schema\",\"status\":\"idle\"}
]"
listing "$BASE_LISTING"

echo "=== a first notify, and a repeat that does nothing"
N1=$(qnote first "$UID1" 'session:
  - "[C1-CC] running one"
  - "[C0-CC] claude code"')
out=$(run --note "$N1" --uid "$UID1" --event verified --at 2026-09-30T06:00:55-04:00 --words "looks right")
if [ "$(lines "$NOTIFY_NOTICES_DIR/$SID_RUN.md")" = 1 ]; then pass "first notify: one notice for the FIRST session: entry of a list"
else fail "first notify: one notice for the FIRST session: entry of a list" "$out"; fi
check "first notify: the key uid|event|at is recorded" grep -qF "\"key\":\"$UID1|verified|2026-09-30T06:00:55-04:00\"" "$SENT"
case "$(last_heading)" in
  *" — ruling · for: [C1-CC] running one") pass "first notify: the heading ends '· for: <filer label>' (the #106 grammar)" ;;
  *) fail "first notify: the heading ends '· for: <filer label>' (the #106 grammar)" "$(last_heading)" ;;
esac
before_n=$(lines "$NOTIFY_NOTICES_DIR/$SID_RUN.md"); before_l=$(lines "$NOTIFY_FLEET_LOG"); before_w=$(lines "$TMP/wake-calls.log"); before_s=$(lines "$SENT")
out=$(run --note "$N1" --uid "$UID1" --event verified --at 2026-09-30T06:00:55-04:00 --words "looks right"); rc=$?
check "repeat: exits 0" [ "$rc" = 0 ]
case "$out" in *"already notified"*) pass "repeat: says 'already notified'" ;; *) fail "repeat: says 'already notified'" "$out" ;; esac
check "repeat: no second notice" [ "$(lines "$NOTIFY_NOTICES_DIR/$SID_RUN.md")" = "$before_n" ]
check "repeat: no log line" [ "$(lines "$NOTIFY_FLEET_LOG")" = "$before_l" ]
check "repeat: no wake" [ "$(lines "$TMP/wake-calls.log")" = "$before_w" ]
check "repeat: no second key" [ "$(lines "$SENT")" = "$before_s" ]
# The listing is unreadable now: a repeat must still exit 0 without touching it, because it does nothing else.
listing ""
out=$(run --note "$N1" --uid "$UID1" --event verified --at 2026-09-30T06:00:55-04:00); rc=$?
check "repeat: needs no listing at all (exit 0 with the listing broken)" [ "$rc" = 0 ]
listing "$BASE_LISTING"
# A different `at` on the same note is a new act.
run --note "$N1" --uid "$UID1" --event verified --at 2026-09-30T07:00:00-04:00 >/dev/null
check "a new 'at' on the same note is a new notice" [ "$(lines "$NOTIFY_NOTICES_DIR/$SID_RUN.md")" = 2 ]
run --note "$N1" --uid "$UID1" --event answered --at 2026-09-30T07:00:00-04:00 >/dev/null
check "a new event with the same 'at' is a new notice" [ "$(lines "$NOTIFY_NOTICES_DIR/$SID_RUN.md")" = 3 ]

echo
echo "=== two concurrent calls give ONE notice"
round=0; good=0
while [ $round -lt 8 ]; do
  round=$((round + 1))
  at="2026-09-30T08:00:0${round}-04:00"
  b=$(lines "$NOTIFY_NOTICES_DIR/$SID_RUN.md"); bl=$(log_entries)
  run --note "$N1" --uid "$UID1" --event verified --at "$at" >/dev/null &
  p1=$!
  run --note "$N1" --uid "$UID1" --event verified --at "$at" >/dev/null &
  p2=$!
  run --note "$N1" --uid "$UID1" --event verified --at "$at" >/dev/null &
  p3=$!
  wait $p1 $p2 $p3
  a=$(lines "$NOTIFY_NOTICES_DIR/$SID_RUN.md"); al=$(log_entries)
  keys=$(grep -cF "\"key\":\"$UID1|verified|$at\"" "$SENT" || true)
  if [ $((a - b)) = 1 ] && [ $((al - bl)) = 1 ] && [ "$keys" = 1 ]; then good=$((good + 1)); fi
done
if [ "$good" = 8 ]; then pass "three racing calls, eight rounds: one notice, one log entry, one key each time"
else fail "three racing calls, eight rounds: one notice, one log entry, one key each time" "$good of 8 rounds were clean"; fi
# A lock left behind by a dead process is broken, not waited on forever.
# A pid that is certainly dead: a child that has exited and been reaped (a fixed number could be a live process).
sh -c 'exit 0' & deadpid=$!; wait "$deadpid"
mkdir -p "$NOTIFY_STATE_DIR/sent.lock"; printf '%s\n' "$deadpid" > "$NOTIFY_STATE_DIR/sent.lock/pid"
b=$(lines "$NOTIFY_NOTICES_DIR/$SID_RUN.md")
start=$(date +%s)
run --note "$N1" --uid "$UID1" --event verified --at 2026-09-30T09:00:00-04:00 >/dev/null
took=$(( $(date +%s) - start ))
check "a stale lock (dead pid) is broken: the notice is written" [ "$(lines "$NOTIFY_NOTICES_DIR/$SID_RUN.md")" = $((b + 1)) ]
check "and quickly (under 5 s)" [ "$took" -lt 5 ]

# A STALE LOCK THAT CANNOT BE REMOVED (re-review of #110) must not spin: after the wait limit the notice goes out anyway.
RO="$TMP/rostate"; mkdir -p "$RO/sent.lock"; printf '%s\n' "$deadpid" > "$RO/sent.lock/pid"; chmod 555 "$RO"
b=$(lines "$NOTIFY_NOTICES_DIR/$SID_RUN.md")
NOTIFY_STATE_DIR="$RO" NOTIFY_LOCK_TRIES=20 PATH="$STUBBIN:$PATH" "$NOTIFY" --note "$N1" --uid "$UID1" --event verified --at 2026-09-30T09:30:00-04:00 >/dev/null 2>&1 &
spin=$!
waited=0
while kill -0 "$spin" 2>/dev/null && [ "$waited" -lt 100 ]; do sleep 0.1; waited=$((waited + 1)); done
if kill -0 "$spin" 2>/dev/null; then kill -9 "$spin" 2>/dev/null; fail "an unremovable stale lock does not spin forever" "still running after 10 s"
else pass "an unremovable stale lock does not spin forever"; fi
check "and the notice is sent without the check" [ "$(lines "$NOTIFY_NOTICES_DIR/$SID_RUN.md")" = $((b + 1)) ]
case "$(log_tail)" in *"could not be taken"*) pass "and the log says the lock could not be taken" ;; *) fail "and the log says the lock could not be taken" "$(log_tail | cut -c1-200)" ;; esac
chmod 755 "$RO"

echo
echo "=== a failed send is NOT recorded, so a retry sends it"
UNW="$TMP/unwritable"; mkdir -p "$UNW"; chmod 500 "$UNW"
N2=$(qnote failed "$UID2" 'session: "[C1-CC] running one"')
NOTIFY_NOTICES_DIR="$UNW/notices" PATH="$STUBBIN:$PATH" "$NOTIFY" --note "$N2" --uid "$UID2" --event verified --at 2026-09-30T06:49:34-04:00 >/dev/null 2>&1
if grep -qF "$UID2" "$SENT" 2>/dev/null; then fail "an unwritable notices dir: no key is recorded" "$(grep -F "$UID2" "$SENT")"
else pass "an unwritable notices dir: no key is recorded"; fi
case "$(log_tail)" in *"NO NOTICE COULD BE WRITTEN"*) pass "and the log says no notice was written" ;; *) fail "and the log says no notice was written" "$(log_tail | cut -c1-200)" ;; esac
chmod 700 "$UNW"
b=$(lines "$NOTIFY_NOTICES_DIR/$SID_RUN.md")
out=$(run --note "$N2" --uid "$UID2" --event verified --at 2026-09-30T06:49:34-04:00)
check "the retry writes the notice" [ "$(lines "$NOTIFY_NOTICES_DIR/$SID_RUN.md")" = $((b + 1)) ]
check "and records the key only then" grep -qF "\"key\":\"$UID2|verified|2026-09-30T06:49:34-04:00\"" "$SENT"

echo
echo "=== revise and for-agent: the key is a hash of the signal"
N3=$(qnote revise "$UID3" 'session: "[C1-CC] running one"')
out=$(run --note "$N3" --event revise --signal "x" --words w); rc=$?
check "revise without --uid is refused" [ "$rc" != 0 ]
out=$(run --note "$N3" --uid "$UID3" --event revise --words w); rc=$?
check "revise without --signal is refused" [ "$rc" != 0 ]
b=$(lines "$NOTIFY_NOTICES_DIR/$SID_RUN.md")
out=$(run --note "$N3" --uid "$UID3" --event revise --signal "> [!revise] Fix the title.
> Then the lead." --words "fix the title"); rc=$?
check "revise with no --at is accepted" [ "$rc" = 0 ]
check "revise: a notice is written" [ "$(lines "$NOTIFY_NOTICES_DIR/$SID_RUN.md")" = $((b + 1)) ]
hash=$(printf '%s' "[!revise] Fix the title.
Then the lead." | shasum -a 256 | cut -c1-64)
check "revise: the key is uid|revise|sha256 of the normalised callout" grep -qF "\"key\":\"$UID3|revise|$hash\"" "$SENT"
out=$(run --note "$N3" --uid "$UID3" --event revise --signal "[!revise]   Fix the title.

  Then the lead.  " --words "fix the title")
case "$out" in *"already notified"*) pass "revise: the same callout without quote marks or extra spaces is a repeat" ;; *) fail "revise: the same callout without quote marks or extra spaces is a repeat" "$out" ;; esac
run --note "$N3" --uid "$UID3" --event revise --signal "> [!revise] Something else." >/dev/null
check "revise: a different callout is a new notice" [ "$(lines "$NOTIFY_NOTICES_DIR/$SID_RUN.md")" = $((b + 2)) ]
case "$(log_tail)" in *"asked for a revision"*) pass "revise: the log says he asked for a revision" ;; *) fail "revise: the log says he asked for a revision" "$(log_tail | cut -c1-200)" ;; esac
b=$(lines "$NOTIFY_NOTICES_DIR/$SID_RUN.md")
run --note "$N3" --uid "$UID3" --event for-agent --signal "#for-agent/review" --at 2026-09-30T06:10 >/dev/null
check "for-agent: a notice is written" [ "$(lines "$NOTIFY_NOTICES_DIR/$SID_RUN.md")" = $((b + 1)) ]
thash=$(printf '%s' "for-agent/review" | shasum -a 256 | cut -c1-64)
check "for-agent: the key is uid|for-agent|sha256 of the tag without '#'" grep -qF "\"key\":\"$UID3|for-agent|$thash\"" "$SENT"
out=$(run --note "$N3" --uid "$UID3" --event for-agent --signal "for-agent/review" --at 2026-09-30T06:30)
case "$out" in *"already notified"*) pass "for-agent: the same tag (with or without '#', another 'at') is a repeat" ;; *) fail "for-agent: the same tag (with or without '#', another 'at') is a repeat" "$out" ;; esac
run --note "$N3" --uid "$UID3" --event for-agent --signal "for-agent/fix" >/dev/null
check "for-agent: another tag is a new notice" [ "$(lines "$NOTIFY_NOTICES_DIR/$SID_RUN.md")" = $((b + 2)) ]

echo
echo "=== an ended lieutenant is not woken: its dispatcher is told"
entry 2026-09-30T0500 "$AR" "[L0-CC] ended one" "$SID_END" archived/ended "[C1-CC] plugins"
entry 2026-09-30T0400 "$NB" "[L0-CC] ended one" "$SID_END" draft/running "[C1-CC] somebody older"
N4=$(qnote ended "$UID4" 'session:
  - "[L0-CC] ended one"')
: > "$TMP/wake-calls.log"
bc=$(lines "$NOTIFY_NOTICES_DIR/$SID_C1.md")
run --note "$N4" --uid "$UID4" --event verified --at 2026-09-30T06:20 --words "good" >/dev/null
check "ended L0: no notice for the L0" [ ! -e "$NOTIFY_NOTICES_DIR/$SID_END.md" ]
if grep -q "$SID_END" "$TMP/wake-calls.log"; then fail "ended L0: the L0 is NOT woken" "$(cat "$TMP/wake-calls.log")"; else pass "ended L0: the L0 is NOT woken"; fi
check "ended L0: its NEWEST entry's reports-to is told" [ "$(lines "$NOTIFY_NOTICES_DIR/$SID_C1.md")" = $((bc + 1)) ]
check "ended L0: the dispatcher's notice names the filer" grep -qF "[L0-CC] ended one" "$NOTIFY_NOTICES_DIR/$SID_C1.md"
case "$(last_heading)" in *"· for: [L0-CC] ended one") pass "ended L0: the heading is still for the filer, so its chain gets it" ;; *) fail "ended L0: the heading is still for the filer" "$(last_heading)" ;; esac
case "$(log_tail)" in *"archived/ended"*"[C1-CC] plugins"*) pass "ended L0: the log says why the dispatcher was told" ;; *) fail "ended L0: the log says why the dispatcher was told" "$(log_tail | cut -c1-240)" ;; esac
# The same L0 with NO row in the listing (its job was removed): found by its label in the notebook.
listing "$(printf '%s' "$BASE_LISTING" | jq -c '[.[] | select(.name != "[L0-CC] ended one")]')"
bc=$(lines "$NOTIFY_NOTICES_DIR/$SID_C1.md")
run --note "$N4" --uid "$UID4" --event answered --at 2026-09-30T06:21 >/dev/null
check "ended L0 with no listing row: found by label, the dispatcher is told" [ "$(lines "$NOTIFY_NOTICES_DIR/$SID_C1.md")" = $((bc + 1)) ]
listing "$BASE_LISTING"
# A lieutenant whose newest entry is RUNNING and whose row is stopped is woken, as today.
entry 2026-09-30T0600 "$NB" "[L0-CC] live one" "$SID_RUNL0" draft/running "[C1-CC] plugins"
N5=$(qnote live "$UID5" 'session: "[L0-CC] live one"')
: > "$TMP/wake-calls.log"
run --note "$N5" --uid "$UID5" --event verified --at 2026-09-30T06:22 >/dev/null
check "running L0 (stopped row): the notice goes to it" [ -s "$NOTIFY_NOTICES_DIR/$SID_RUNL0.md" ]
check "running L0 (stopped row): it is woken through the wake script, as today" grep -q "$SID_RUNL0" "$TMP/wake-calls.log"

echo
echo "=== a free-text session: the caller's captain, else the rear admiral; never looked up"
N6=$(qnote freetext "" 'session: "fileclass schema"')
bf=$(lines "$NOTIFY_NOTICES_DIR/$SID_FREE.md"); bc=$(lines "$NOTIFY_NOTICES_DIR/$SID_CAP.md")
out=$(run --note "$N6" --event verified --at 2026-09-30T06:23 --captain "[C0-OB] obsidian")
check "free text + --captain (the caller read the ship from the path): the captain is told" [ "$(lines "$NOTIFY_NOTICES_DIR/$SID_CAP.md")" = $((bc + 1)) ]
check "free text: a row that happens to carry that text is NOT told" [ "$(lines "$NOTIFY_NOTICES_DIR/$SID_FREE.md")" = "$bf" ]
case "$(last_heading)" in *"· for: [C0-OB] obsidian") pass "free text: the heading is for the captain told" ;; *) fail "free text: the heading is for the captain told" "$(last_heading)" ;; esac
case "$(log_tail)" in *"not a session label"*) pass "free text: the log says the session was free text" ;; *) fail "free text: the log says the session was free text" "$(log_tail | cut -c1-200)" ;; esac
br=$(lines "$NOTIFY_NOTICES_DIR/$SID_RA.md")
out=$(run --note "$N6" --event verified --at 2026-09-30T06:24)
check "free text, no ship known: the rear admiral is told" [ "$(lines "$NOTIFY_NOTICES_DIR/$SID_RA.md")" = $((br + 1)) ]
case "$(last_heading)" in *"· for: [A0] rear admiral") pass "free text, no ship: the heading is for the rear admiral" ;; *) fail "free text, no ship: the heading is for the rear admiral" "$(last_heading)" ;; esac

echo
echo "=== review of #110: a trailing comment, and an unstamped entry beside an ended one"
NC=$(qnote comment "" 'session: "[C1-CC] running one"  # filer')
b=$(lines "$NOTIFY_NOTICES_DIR/$SID_RUN.md")
run --note "$NC" --event verified --at 2026-09-30T06:40 >/dev/null
check "a scalar label with a trailing # comment is the filer" [ "$(lines "$NOTIFY_NOTICES_DIR/$SID_RUN.md")" = $((b + 1)) ]
NC2=$(qnote comment2 "" 'session:
  - "[C1-CC] running one" # filer')
run --note "$NC2" --event verified --at 2026-09-30T06:41 >/dev/null
check "a list item with a trailing # comment is the filer" [ "$(lines "$NOTIFY_NOTICES_DIR/$SID_RUN.md")" = $((b + 2)) ]
cat > "$NB/Agent session resumed copy.md" <<EOF
---
session: "[L0-CC] gone"
status: draft/running
session-id: 12345678-1111-2222-3333-444444444444
reports-to: "[C1-CC] plugins"
---
EOF
entry 2026-09-30T0500 "$AR" "[L0-CC] gone" "12345678-1111-2222-3333-444444444444" archived/ended "[C1-CC] plugins"
NG=$(qnote gone "" 'session: "[L0-CC] gone"')
bc=$(lines "$NOTIFY_NOTICES_DIR/$SID_C1.md")
run --note "$NG" --event verified --at 2026-09-30T06:42 >/dev/null
check "an unstamped entry beside an ended one leaves it unknown: the dispatcher is NOT told as for an ended L0" [ "$(lines "$NOTIFY_NOTICES_DIR/$SID_C1.md")" = "$bc" ]
case "$(log_tail)" in *"archived/ended"*) fail "and the log does not claim the entry ended" "$(log_tail | cut -c1-200)" ;; *) pass "and the log does not claim the entry ended" ;; esac

echo
echo "=== old callers with no --uid: as today, and the log says it cannot dedupe"
N7=$(qnote olduid "" 'session: "[C1-CC] running one"')
rm -f "$SENT"
b=$(lines "$NOTIFY_NOTICES_DIR/$SID_RUN.md")
run --note "$N7" --event verified --at 2026-09-27T14:05 --words "old" >/dev/null
check "no uid: the notice is written" [ "$(lines "$NOTIFY_NOTICES_DIR/$SID_RUN.md")" = $((b + 1)) ]
case "$(log_tail)" in *"could not be deduplicated"*) pass "no uid: the log says it could not be deduplicated" ;; *) fail "no uid: the log says it could not be deduplicated" "$(log_tail | cut -c1-200)" ;; esac
check "no uid: nothing is recorded" [ ! -s "$SENT" ]
run --note "$N7" --event verified --at 2026-09-27T14:05 --words "old" >/dev/null
check "no uid: a second identical call notifies again (it cannot know)" [ "$(lines "$NOTIFY_NOTICES_DIR/$SID_RUN.md")" = $((b + 2)) ]

echo
echo "=== the interface"
out=$(run --note "$N1" --uid "not-the-notes-uid" --event verified --at 2026-09-30T06:00); rc=$?
check "a --uid that differs from the note's own uid is refused" [ "$rc" != 0 ]
out=$(run --note "$N1" --uid 'bad"uid' --event verified --at 2026-09-30T06:00); rc=$?
check "a --uid with a quote in it is refused" [ "$rc" != 0 ]
out=$("$NOTIFY" --help 2>&1)
case "$out" in *"--uid"*"--signal"*) pass "--help documents --uid and --signal" ;; *) fail "--help documents --uid and --signal" ;; esac

printf '\n%s cases, %s failed\n' "$n" "$fails"
[ "$fails" = 0 ] || exit 1
