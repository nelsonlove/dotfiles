#!/usr/bin/env bash
# The wake and promote rank gates, end to end, against TWO THROWAWAY SESSIONS YOU DISPATCH YOURSELF.
#
# WHY IT IS IN THE REPO. It was a `/tmp` harness for three packages, which means nothing committed guarded
# the two scripts that decide who may wake and promote whom — the review of #61 pointed that out, and it
# was right. It needs live fixtures, so it cannot run unattended; that is a reason to document the
# requirement, not a reason to leave the paths untested.
#
# HOW TO RUN IT. Dispatch two throwaways of your own, then pass their ids:
#
#     cd /tmp
#     claude --bg --agent lieutenant --name "[C0-CC] battery captain"    "do nothing; reply standing-by and stop"
#     claude --bg --agent lieutenant --name "[L0-FL] battery lieutenant" "do nothing; reply standing-by and stop"
#     bash claude/tests/fleet-ranks/wake-and-promote.sh <captain-id> <lieutenant-id>
#     claude stop <id>; claude rm <id>      # for each, afterwards
#
# NEVER A LIVE FLEET ID. An earlier version of this battery used one, expecting the alive path — that
# session was stopped, so the script took the stopped path and WOKE IT FOR REAL, handing a real session a
# test brief. Every wake or promote test dispatches its own throwaways, and every case passes `--dry-run`
# and `--log` to a temp file. Nothing here touches the fleet log, the notebook, or any session but yours.
#
# GATE CASES assert that the RANK GATE let the caller through — the exit is not 2 and the output carries no
# "refused:" — rather than a fixed exit code, because whether a target is alive or stopped is not ours to
# control and decides 3 against 0.
set -u
W="${3:-$(cd "$(dirname "$0")/../../bin" && pwd -P)/wake-session.sh}"
P="${4:-$(cd "$(dirname "$0")/../../bin" && pwd -P)/promote-session.sh}"
CAP="${1:?usage: wake-and-promote.sh <captain-throwaway-id> <lieutenant-throwaway-id> [wake-session.sh] [promote-session.sh]}"
LT="${2:?both throwaway ids are required; never pass a live fleet id}"
TMP=$(mktemp -d -t wake-promote-battery) || exit 1
trap 'rm -rf "$TMP"' EXIT
NB="$TMP/notebook"
LOG="$TMP/log.md"
: > "$LOG"
n=0; fails=0

pass() { n=$((n + 1)); printf 'PASS  [%s]\n' "$1"; }
fail() { n=$((n + 1)); fails=$((fails + 1)); printf 'FAIL  [%s]  %s\n' "$1" "${2:-}"; }
refused() {  # refused <label> -- cmd...
  label="$1"; shift 2
  out=$("$@" 2>&1); rc=$?
  if [ "$rc" = 2 ]; then pass "$label"; else fail "$label" "rc=$rc, wanted a refusal"; fi
}
allowed() {  # allowed <label> -- cmd...   (the gate let it through; nothing was touched, it is a dry run)
  label="$1"; shift 2
  out=$("$@" 2>&1); rc=$?
  if [ "$rc" != 2 ] && ! printf '%s' "$out" | grep -q 'refused:'; then pass "$label"
  else fail "$label" "rc=$rc; $(printf '%s' "$out" | grep -m1 'refused:')"; fi
}

mkdir -p "$NB/2026-09"
mk() { printf -- '---\ntitle: %s\nsession: "%s"\nsession-status: %s\nreports-to: "%s"\n---\n\n[test artifact — safe to delete]\n' "$1" "$2" "$3" "$4" > "$NB/2026-09/$1.md"; }
mk "Agent session 2026-09-27T0101" "[C0-CC] battery captain" ended "[A0] rear admiral"
mk "Agent session 2026-09-27T0102" "[L0-FL] battery lieutenant" running "[C1-CC] plugins"
mk "Agent session 2026-09-27T0103" "[C1-CC] plugins" running "[C0-CC] battery captain"

printf -- '=== wake-session: the A0 caller is read at all (it used to die on the rank code)\n'
allowed "A0 reaches a lieutenant in its line (throwaway)" -- \
  "$W" --session $LT --by "[A0] rear admiral" --why "A0 test" --notebook-dir "$NB" --log "$LOG" --dry-run
refused "a name with no rank code is still refused" -- \
  "$W" --session $LT --by "rear admiral" --why x --notebook-dir "$NB" --log "$LOG" --dry-run

printf -- '=== wake-session: a captain is reachable by A0 and by nobody else\n'
allowed "A0 reaches a captain" -- \
  "$W" --session $CAP --by "[A0] rear admiral" --why "A0 test" --notebook-dir "$NB" --log "$LOG" --dry-run
refused "a commander may not reach a captain" -- \
  "$W" --session $CAP --by "[C1-CC] plugins" --why x --notebook-dir "$NB" --log "$LOG" --dry-run
refused "a captain may not reach a captain" -- \
  "$W" --session $CAP --by "[C0-CC] claude code" --why x --notebook-dir "$NB" --log "$LOG" --dry-run
refused "a lieutenant may not reach a captain" -- \
  "$W" --session $CAP --by "[L0-FL] battery lieutenant" --why x --notebook-dir "$NB" --log "$LOG" --dry-run

printf -- '=== wake-session: the survey reads A0 and names its rank\n'
out=$("$W" --all --by "[A0] rear admiral" --notebook-dir "$NB" --log "$LOG" 2>&1)
printf '%s' "$out" | grep -q 'rear admiral' && pass "survey names the rear admiral as the caller" || fail "survey names the rear admiral as the caller"
printf '%s' "$out" | grep -q 'SHIP\|NO SHIP CODE' && pass "survey still groups by ship for an A0 caller" || fail "survey still groups by ship for an A0 caller"

printf -- '=== promote-session: A0 as the promoter\n'
allowed "A0 demotes a captain, ship taken from the target" -- \
  "$P" --session $CAP --to commander --name "[C1-CC] battery captain" --by "[A0] rear admiral" --why "A0 test" --log "$LOG" --dry-run
allowed "A0 with --ship given explicitly" -- \
  "$P" --session $CAP --to commander --name "[C1-CC] battery captain" --by "[A0] rear admiral" --ship CC --why "A0 test" --log "$LOG" --dry-run
refused "A0 with a --name on a different ship from the target" -- \
  "$P" --session $CAP --to commander --name "[C1-OB] battery captain" --by "[A0] rear admiral" --why x --log "$LOG" --dry-run
refused "--name never carries A0" -- \
  "$P" --session $LT --to commander --name "[A0] rear admiral" --by "[A0] rear admiral" --why x --log "$LOG" --dry-run
refused "--to captain stays refused, A0 included" -- \
  "$P" --session $LT --to captain --name "[C0-CC] x" --by "[A0] rear admiral" --why x --log "$LOG" --dry-run
refused "a commander still may not promote a captain" -- \
  "$P" --session $CAP --to commander --name "[C1-CC] x" --by "[C1-CC] plugins" --why x --log "$LOG" --dry-run

printf -- '=== promote-session: the old rails still hold\n'
refused "bare --by with no --ship (non-A0)" -- \
  "$P" --session $LT --to lieutenant-commander --name "[C2-CC] x" --by "[C0] claude code" --why x --log "$LOG" --dry-run
refused "--ship naming another captain's ship" -- \
  "$P" --session $LT --to lieutenant-commander --name "[C2-OB] x" --by "[C0-CC] claude code" --ship OB --why x --log "$LOG" --dry-run
allowed "an ordinary CC promotion still works" -- \
  "$P" --session $LT --to lieutenant-commander --name "[C2-FL] battery lieutenant" --by "[C0-CC] claude code" --ship FL --why x --log "$LOG" --dry-run

printf -- '=== a ship-coded A0 is NOT the rear admiral (reviewer finding on PR #56)\n'
for bad in "[A0-CC] impostor" "[A0-] noship-empty" "[A0-CC-extra] weird" "[A0x] y" "[a0] z"; do
  refused "wake: '$bad' carries no rank code" -- \
    "$W" --session "$CAP" --by "$bad" --why x --notebook-dir "$NB" --log "$LOG" --dry-run
  refused "promote: '$bad' carries no rank code" -- \
    "$P" --session "$LT" --to lieutenant-commander --name "[C2-CC] x" --by "$bad" --why x --log "$LOG" --dry-run
done
refused "promote: --name '[A0-CC] x' is refused (its code matches no --to)" -- \
  "$P" --session "$LT" --to lieutenant-commander --name "[A0-CC] x" --by "[A0] rear admiral" --why x --log "$LOG" --dry-run

printf -- '=== the rank tables themselves\n'
for pair in "A0:-1" "C0:0" "C1:1" "C2:2" "L0:3" "L1:3"; do
  code=${pair%%:*}; want=${pair##*:}
  got=$(printf '%s' "$("$W" --session nosuch --by "[$code] x" --why x --notebook-dir "$NB" --dry-run 2>&1)")
  # a valid code gets past the --by check and dies on the unknown session instead
  if printf '%s' "$got" | grep -q 'no background session'; then pass "[$code] is a known rank code (rank $want)"
  else fail "[$code] is a known rank code (rank $want)" "$(printf '%s' "$got" | head -n 1)"; fi
done

lines=$(grep -c '^## ' "$LOG" 2>/dev/null) || lines=0
printf '\nlog lines written: %s (must be 0 — every case was a dry run or a refusal)\n' "$lines"
printf '%s cases, %s failed\n' "$n" "$fails"
