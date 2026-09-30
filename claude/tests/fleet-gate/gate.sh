#!/usr/bin/env bash
# claude/bin/fleet-gate, and the two scripts that start sessions behind it (Nelson's "a", log 2026-09-30T05:32).
#
# NOTHING HERE READS THE MACHINE OR THE FLEET: `sysctl` and `claude` are stubs on PATH. The stub sysctl prints the file $STUB_LOAD (or fails when it holds FAIL); the stub claude prints the file $STUB_LISTING for `claude agents …` (or fails when it holds FAIL) and, for any other call, records its arguments in $STUB_CALLS and exits 0, so a start that got past the gate would show in that file and nothing real would run.
#
# Run: bash claude/tests/fleet-gate/gate.sh   (prints the check count; exits non-zero on any failure)
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
BIN="$HERE/../../bin"
GATE="$BIN/fleet-gate"
n=0; fails=0
pass() { n=$((n + 1)); printf 'PASS  %s\n' "$1"; }
fail() { n=$((n + 1)); fails=$((fails + 1)); printf 'FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; }
eq()  { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "got '$2', want '$3'"; fi; }
has() { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "missing '$3' in: $(printf '%s' "$2" | head -c 300)" ;; esac; }
command -v jq >/dev/null 2>&1 || { echo "STOP  jq is not installed, and the gate needs it"; exit 1; }

T=$(mktemp -d "${TMPDIR:-/tmp}/fleet-gate-test.XXXXXX") || exit 1
trap '/usr/bin/trash "$T" 2>/dev/null || true' EXIT
mkdir -p "$T/stubbin"
cat > "$T/stubbin/sysctl" <<'EOF'
#!/bin/sh
[ "$(cat "$STUB_LOAD")" = FAIL ] && exit 1
cat "$STUB_LOAD"
EOF
cat > "$T/stubbin/claude" <<'EOF'
#!/bin/sh
if [ "$1" = agents ]; then
  [ -z "${STUB_EAT_STDIN:-}" ] || cat >/dev/null
  [ "$(cat "$STUB_LISTING")" = FAIL ] && exit 1
  cat "$STUB_LISTING"; exit 0
fi
printf '%s\n' "$*" >> "$STUB_CALLS"
exit 0
EOF
chmod +x "$T/stubbin/sysctl" "$T/stubbin/claude"
export STUB_LOAD="$T/load" STUB_LISTING="$T/listing.json" STUB_CALLS="$T/calls"
load() { printf '{ %s %s %s }\n' "$1" "$2" "$3" > "$T/load"; }
sessions() {  # sessions <n>: a listing of n rows
  local i=0; { printf '['; while [ "$i" -lt "$1" ]; do [ "$i" = 0 ] || printf ','; printf '{"id":"s%07d"}' "$i"; i=$((i + 1)); done; printf ']\n'; } > "$T/listing.json"
}
gate() {  # gate [args…]: sets $out (stdout and stderr) and $rc
  out=$(PATH="$T/stubbin:$PATH" bash "$GATE" "$@" 2>&1); rc=$?
}
[ -f "$GATE" ] || fail "the gate exists at claude/bin/fleet-gate" "none"

echo "=== 1. the limits"
load 1.00 3.50 2.00; sessions 5; gate
eq "both under: open (exit 0)" "$rc" 0
eq "an open gate says nothing" "$out" ""
load 1.00 8.54 2.00; sessions 5; gate
eq "5-min load 8.54: holding (exit 1)" "$rc" 1
eq "the holding line, word for word" "$out" "fleet-gate: 5-min load 8.54 (limit 8), 5 live sessions (limit 20); holding"
load 1.00 8.00 2.00; sessions 5; gate
eq "5-min load exactly 8: holding (under means under)" "$rc" 1
load 1.00 7.99 2.00; sessions 5; gate
eq "5-min load 7.99: open" "$rc" 0
load 1.00 10.50 2.00; sessions 5; gate
eq "5-min load 10.50 is compared as a number, not a string: holding" "$rc" 1
load 30.00 2.00 30.00; sessions 5; gate
eq "only the SECOND number is the 5-min load: open with 1-min and 15-min high" "$rc" 0
load 1.00 2.00 2.00; sessions 20; gate
eq "20 live sessions: holding" "$rc" 1
has "the session count is in the line" "$out" "20 live sessions (limit 20); holding"
load 1.00 2.00 2.00; sessions 19; gate
eq "19 live sessions: open" "$rc" 0
load 1.00 9.00 2.00; sessions 25; gate
eq "both over: holding" "$rc" 1

echo
echo "=== 2. it fails closed"
load 1.00 2.00 2.00; echo FAIL > "$T/listing.json"; gate
eq "a listing that fails: holding" "$rc" 1
has "and it says the listing failed" "$out" "the session listing could not be read"
load 1.00 2.00 2.00; echo 'not json at all' > "$T/listing.json"; gate
eq "a listing that is not JSON: holding" "$rc" 1
has "and it says so" "$out" "not a JSON array"
load 1.00 2.00 2.00; echo '{"id":"x"}' > "$T/listing.json"; gate
eq "a listing that is JSON but not an array: holding" "$rc" 1
sessions 5; echo 'garbage' > "$T/load"; gate
eq "a load line that cannot be parsed: holding" "$rc" 1
has "and it says the load failed" "$out" "the load line could not be parsed"
sessions 5; echo '{ 1.00 }' > "$T/load"; gate
eq "a load line with one number: holding" "$rc" 1
sessions 5; echo FAIL > "$T/load"; gate
eq "sysctl that fails: holding" "$rc" 1
has "and it says the load could not be read" "$out" "the load could not be read"
load 1.00 2.00 2.00; sessions 5; gate --bogus
eq "an unknown argument: holding" "$rc" 1

echo
echo "=== 3. the env overrides"
load 1.00 10.00 2.00; sessions 5; out=$(FLEET_GATE_LOAD5=12 PATH="$T/stubbin:$PATH" bash "$GATE" 2>&1); rc=$?
eq "FLEET_GATE_LOAD5=12 opens at load 10" "$rc" 0
load 1.00 2.00 2.00; sessions 6; out=$(FLEET_GATE_SESSIONS=5 PATH="$T/stubbin:$PATH" bash "$GATE" 2>&1); rc=$?
eq "FLEET_GATE_SESSIONS=5 holds at 6 sessions" "$rc" 1
has "and the line names the new limit" "$out" "(limit 5); holding"
load 1.00 2.00 2.00; sessions 5; out=$(FLEET_GATE_LOAD5=abc PATH="$T/stubbin:$PATH" bash "$GATE" 2>&1); rc=$?
eq "a load limit that is not a number: holding" "$rc" 1
load 1.00 2.00 2.00; sessions 5; out=$(FLEET_GATE_SESSIONS=2.5 PATH="$T/stubbin:$PATH" bash "$GATE" 2>&1); rc=$?
eq "a session limit that is not a whole number: holding" "$rc" 1

echo
echo "=== 4. --wait"
load 1.00 9.00 2.00; sessions 5
( sleep 2; printf '{ 1.00 3.00 2.00 }\n' > "$T/load" ) &
t0=$(date +%s); out=$(FLEET_GATE_POLL=1 PATH="$T/stubbin:$PATH" bash "$GATE" --wait 20 2>&1); rc=$?; t1=$(date +%s)
wait
eq "--wait opens when the load falls (exit 0)" "$rc" 0
if [ $((t1 - t0)) -le 10 ]; then pass "--wait opened within a few polls ($((t1 - t0)) s)"; else fail "--wait opened within a few polls" "$((t1 - t0)) s"; fi
has "--wait said once why it held" "$out" "5-min load 9.00 (limit 8)"
load 1.00 9.00 2.00; sessions 5
t0=$(date +%s); out=$(FLEET_GATE_POLL=1 PATH="$T/stubbin:$PATH" bash "$GATE" --wait 2 2>&1); rc=$?; t1=$(date +%s)
eq "--wait times out (exit 2)" "$rc" 2
has "and says it waited" "$out" "waited 2 s and the gate is still closed"
if [ $((t1 - t0)) -le 6 ]; then pass "--wait 2 gave up on time ($((t1 - t0)) s)"; else fail "--wait 2 gave up on time" "$((t1 - t0)) s"; fi
lines=$(printf '%s\n' "$out" | grep -c '^fleet-gate: 5-min load' || true)
eq "--wait prints the holding line once, not once per poll" "$lines" 1
echo FAIL > "$T/listing.json"; out=$(FLEET_GATE_POLL=1 PATH="$T/stubbin:$PATH" bash "$GATE" --wait 1 2>&1); rc=$?
eq "--wait on a failing listing never opens (exit 2)" "$rc" 2
load 1.00 2.00 2.00; sessions 5; gate --wait x
eq "--wait with a bad number: holding" "$rc" 1
load 1.00 9.00 2.00; sessions 5; gate --wait ""
eq "--wait with an empty number: holding at once, not a single check" "$rc" 1
has "and it names the bad value" "$out" "--wait takes a whole number"
# The numbers move on every poll; the line is printed once per change of what holds the gate.
load 1.00 9.00 2.00; sessions 5
( for v in 9.10 9.20 9.30 9.40 9.50 9.60; do sleep 0.5; printf '{ 1.00 %s 2.00 }\n' "$v" > "$T/load"; done ) &
out=$(FLEET_GATE_POLL=1 PATH="$T/stubbin:$PATH" bash "$GATE" --wait 3 2>&1); rc=$?
wait
lines=$(printf '%s\n' "$out" | grep -c '^fleet-gate: 5-min load' || true)
eq "--wait prints once while only the load NUMBER changes" "$lines" 1
load 1.00 9.00 2.00; sessions 5
( sleep 2; sessions 25 ) &
out=$(FLEET_GATE_POLL=1 PATH="$T/stubbin:$PATH" bash "$GATE" --wait 4 2>&1); rc=$?
wait
lines=$(printf '%s\n' "$out" | grep -c '^fleet-gate: 5-min load' || true)
eq "--wait prints again when the sessions start to hold too" "$lines" 2
# A leading zero is base 10: bash arithmetic would crash on "08".
load 1.00 9.00 2.00; sessions 5
( sleep 2; printf '{ 1.00 3.00 2.00 }\n' > "$T/load" ) &
out=$(FLEET_GATE_POLL=1 PATH="$T/stubbin:$PATH" bash "$GATE" --wait 08 2>&1); rc=$?
wait
eq "--wait 08 is eight seconds, not a bad octal (it opens: exit 0)" "$rc" 0

echo
echo "=== 5. the two scripts that start sessions stop at a closed gate"
# The fixture of claude/tests/fleet-ranks/admirals-and-dv.sh, plus one notebook entry that puts the target in the caller's reporting line (wake-session.sh refuses a target outside it): a temp HOME with stub rank definitions, a Pause note set to not paused, and one stopped target row. The gate is held by the load alone.
ZERO=00000000-0000-0000-0000-000000000000
mkdir -p "$T/home/.claude/agents" "$T/cwd" "$T/jobs" "$T/agents/Agent notebook/2026-09" "$T/archive"
for d in captain commander lieutenant-commander lieutenant; do : > "$T/home/.claude/agents/$d.md"; done
printf -- '---\npaused: false\n---\n' > "$T/pause.md"
printf -- '---\ntitle: Agent session 2026-09-30T0001\nsession: "[L0-CC] t"\nstatus: archived/ended\nreports-to: "[C0-CC] claude code"\n---\n\n[test artifact — safe to delete]\n' > "$T/agents/Agent notebook/2026-09/Agent session 2026-09-30T0001.md"
printf '[{"id":"zz000000","sessionId":"%s","name":"[L0-CC] t","cwd":"%s","status":"stopped"}]\n' "$ZERO" "$T/cwd" > "$T/listing.json"
run_promote() {
  HOME="$T/home" PATH="$T/stubbin:$PATH" bash "$BIN/promote-session.sh" --session $ZERO --why x --jobs-dir "$T/jobs" --log "$T/log.md" --pause-note "$T/pause.md" \
    --to lieutenant-commander --name "[C2-CC] t" --by "[C0-CC] claude code" "$@" 2>&1
}
run_wake() {
  HOME="$T/home" PATH="$T/stubbin:$PATH" bash "$BIN/wake-session.sh" --session $ZERO --by "[C0-CC] claude code" --why x --jobs-dir "$T/jobs" --log "$T/log.md" \
    --pause-note "$T/pause.md" --agents-dir "$T/agents" --notebook-dir "$T/agents/Agent notebook" --archive-dir "$T/archive" "$@" 2>&1
}
load 1.00 9.00 2.00; : > "$T/calls"
out=$(run_promote); rc=$?
has "promote: a live start at a closed gate is refused" "$out" "held by the fleet gate"
has "promote: the refusal carries the gate's own line" "$out" "5-min load 9.00 (limit 8)"
eq  "promote: nothing was stopped or started" "$(cat "$T/calls")" ""
if [ "$rc" != 0 ]; then pass "promote: the refusal exits non-zero ($rc)"; else fail "promote: the refusal exits non-zero" "exit 0"; fi
out=$(run_promote --dry-run)
has "promote: a dry run is not gated" "$out" "dry run: nothing touched"
: > "$T/calls"
out=$(run_wake); rc=$?
has "wake: a live resume at a closed gate is refused" "$out" "held by the fleet gate"
eq  "wake: nothing was resumed" "$(cat "$T/calls")" ""
if [ "$rc" != 0 ]; then pass "wake: the refusal exits non-zero ($rc)"; else fail "wake: the refusal exits non-zero" "exit 0"; fi
out=$(run_wake --dry-run)
has "wake: a dry run is not gated" "$out" "dry run: nothing touched"

# A LIVE target: the gate must hold before promote stops it. The row's pid is a live sleep of this test's own.
sleep 120 & LIVE=$!
printf '[{"id":"zz000000","sessionId":"%s","name":"[L0-CC] t","cwd":"%s","status":"idle","pid":%s}]\n' "$ZERO" "$T/cwd" "$LIVE" > "$T/listing.json"
: > "$T/calls"
out=$(run_promote)
has "promote: a LIVE target at a closed gate is refused" "$out" "held by the fleet gate"
eq  "promote: the live target was NOT stopped (the gate comes before the stop)" "$(cat "$T/calls")" ""
if kill -0 "$LIVE" 2>/dev/null; then pass "promote: the live target's process is still running"; else fail "promote: the live target's process is still running" "gone"; fi
kill "$LIVE" 2>/dev/null; wait "$LIVE" 2>/dev/null
# A STALE pid (its process is gone) earns no allowance: at 20 live sessions the gate holds, although the load is low. $LIVE is dead now.
load 1.00 2.00 2.00
{ printf '[{"id":"zz000000","sessionId":"%s","name":"[L0-CC] t","cwd":"%s","status":"idle","pid":%s}' "$ZERO" "$T/cwd" "$LIVE"
  i=1; while [ "$i" -lt 20 ]; do printf ',{"id":"s%07d"}' "$i"; i=$((i + 1)); done; printf ']\n'; } > "$T/listing.json"
: > "$T/calls"
out=$(run_promote)
has "promote: a target with a stale pid gets no allowance (20 live: held)" "$out" "20 live sessions (limit 20); holding"
eq  "promote: and nothing was started" "$(cat "$T/calls")" ""
load 1.00 9.00 2.00
printf '[{"id":"zz000000","sessionId":"%s","name":"[L0-CC] t","cwd":"%s","status":"stopped"}]\n' "$ZERO" "$T/cwd" > "$T/listing.json"

# The sweep: a gate that holds stops it, and it says what it resumed before (none here) and what it did not.
: > "$T/calls"
out=$(HOME="$T/home" PATH="$T/stubbin:$PATH" bash "$BIN/wake-session.sh" --all --resume-stopped --by "[C0-CC] claude code" --why x --jobs-dir "$T/jobs" --log "$T/log.md" \
  --pause-note "$T/pause.md" --agents-dir "$T/agents" --notebook-dir "$T/agents/Agent notebook" --archive-dir "$T/archive" 2>&1)
has "wake --all: the sweep stops at a closed gate and names where" "$out" "the sweep stopped at zz000000"
has "wake --all: it says what was resumed before it" "$out" "Resumed and logged before it: none"
eq  "wake --all: nothing was resumed" "$(cat "$T/calls")" ""

echo
echo "=== 6. claude/lib/fleet-gate.sh"
LIBF="$HERE/../../lib/fleet-gate.sh"
libcheck() {  # libcheck <extra>: rc of fleet_gate_check
  PATH="$T/stubbin:$PATH" bash -c '. "$1"; fleet_gate_check "$2"' _ "$LIBF" "$1" >/dev/null 2>&1; echo $?
}
load 1.00 2.00 2.00; sessions 20
eq "the lib holds at 20 live sessions with no allowance" "$(libcheck 0)" 1
eq "the lib opens at 20 with an allowance of one (a live promote target)" "$(libcheck 1)" 0
sessions 21
eq "an allowance of one does not open 21" "$(libcheck 1)" 1
got=$(FLEET_GATE_SESSIONS=abc PATH="$T/stubbin:$PATH" bash -c '. "$1"; fleet_gate_check 1; echo "rc=$?"' _ "$LIBF" 2>&1)
has "a bad limit with an allowance still holds" "$got" "rc=1"
# The gate reads no stdin: a loop fed by a heredoc keeps every line even when `claude agents` would eat stdin.
sessions 5
got=$(STUB_EAT_STDIN=1 PATH="$T/stubbin:$PATH" bash -c '. "$1"; n=0; while read -r x; do fleet_gate_check; n=$((n + 1)); done <<EOF
a
b
c
EOF
echo "$n"' _ "$LIBF" 2>&1)
eq "the gate does not eat a loop's heredoc" "$got" 3

out=$(bash "$GATE" --help 2>&1)
case "$out" in *"set -u"*) fail "--help prints the header only" "it printed code" ;; *"FAIL CLOSED"*) pass "--help prints the header only" ;; *) fail "--help prints the header only" "no header" ;; esac

EXPECTED=65
[ "$n" = "$EXPECTED" ] || { fails=$((fails + 1)); echo "FAIL  the check count is $n, expected $EXPECTED"; }
printf '\n%s checks (expected %s), %s failed\n' "$n" "$EXPECTED" "$fails"
[ "$fails" = 0 ] || exit 1
