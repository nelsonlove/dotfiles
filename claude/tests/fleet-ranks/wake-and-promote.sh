#!/usr/bin/env bash
# The wake and promote rank gates, end to end, against ONE THROWAWAY SESSION YOU DISPATCH YOURSELF.
#
# WHY IT IS IN THE REPO. It was a `/tmp` harness for three packages, which means nothing committed guarded
# the two scripts that decide who may wake and promote whom — the review of #61 pointed that out, and it
# was right. It needs a live fixture, so it cannot run unattended; that is a reason to document the
# requirement, not a reason to leave the paths untested.
#
# HOW TO RUN IT. Dispatch one throwaway of your own, then pass its id:
#
#     cd /tmp
#     claude --bg --agent lieutenant --name "[L0-FL] wake-and-promote battery target" \
#            "[test artifact — safe to delete] Do nothing. Reply standing-by and stop."
#     bash claude/tests/fleet-ranks/wake-and-promote.sh <id>
#     claude stop <id>; claude rm <id>      # afterwards, and check the listing after
#
# NEVER A LIVE FLEET ID, AND NEVER A FIXTURE NAMED AS A RANK ABOVE A LIEUTENANT. An earlier version used a
# live id, expecting the alive path — that session was stopped, so the script took the stopped path and WOKE
# IT FOR REAL, handing a real session a test brief. A later version dispatched `[C0-CC] battery captain` to
# get a captain-ranked target, and it appeared in the fleet view as a captain nobody had claimed; the
# captain stopped it and the fixture rule was widened on 2026-09-27: a throwaway is named for what it TESTS,
# as a lieutenant on its ship, never as a captain or a commander, and it is dispatched `--agent lieutenant`.
#
# SO WHERE DOES A CAPTAIN-RANKED TARGET COME FROM? Not from a name. Both scripts read a target's rank from
# CLAUDE CODE'S JOB STATE — `~/.claude/jobs/<id>/state.json`, key `template`, through the rank definitions —
# and fall back to the display name only when that says `bg` or nothing. So a fixture dispatched `--agent
# lieutenant` is rank 3 whatever its name says, and the only session that reads as 0 is one dispatched
# `--agent captain`, which is a captain in the fleet view and is exactly what we will not start. This
# battery therefore passes `--jobs-dir`, the test-only flag both scripts carry beside `--notebook-dir`: the
# ROW comes from the real listing, the RANK from a stub this script writes. One live throwaway, no rank in
# its name, and the captain gate is exercised on the value the script actually reads.
#
# AND THE CAPTAIN CASES USED TO PASS FOR THE WRONG REASON. Before the stub, the "captain" fixture read as a
# lieutenant, so the captain gate never fired: every one of those cases refused on the REPORTING LINE
# instead (the throwaway's line did not reach the caller), and a case that asserts only `rc=2` cannot tell
# those apart. That is why the gate cases below assert on the SENTENCE the refusal gives, through
# `refused_because`. A test that cannot say which rail stopped it is not evidence about either rail.
#
# GATE-PASSED CASES assert that the rank gate let the caller through — the exit is not 2 and the output
# carries no "refused:" — rather than a fixed exit code, because whether a target is alive or stopped is
# not ours to control and decides 3 against 0.
set -u
W="${2:-$(cd "$(dirname "$0")/../../bin" && pwd -P)/wake-session.sh}"
P="${3:-$(cd "$(dirname "$0")/../../bin" && pwd -P)/promote-session.sh}"
LT="${1:?usage: wake-and-promote.sh <throwaway-id> [wake-session.sh] [promote-session.sh]; never a live fleet id, and never a fixture named as a rank above a lieutenant}"
TMP=$(mktemp -d -t wake-promote-battery) || exit 1
trap 'rm -rf "$TMP"' EXIT
NB="$TMP/notebook"
LOG="$TMP/log.md"
: > "$LOG"
n=0; fails=0

# THE TWO JOB-STATE STUBS. `JOBSNULL` is empty, so every row's rank falls back to its display name, which is
# what an ordinary case wants. `JOBSCAP` says the ONE throwaway is a captain, which is the only way to reach
# the captain gate without dispatching a captain. Nothing under `~/.claude/jobs` is read or written.
JOBSNULL="$TMP/jobs-empty"; mkdir -p "$JOBSNULL"
JOBSCAP="$TMP/jobs-captain"; mkdir -p "$JOBSCAP/$LT"
printf '{"template":"captain"}\n' > "$JOBSCAP/$LT/state.json"

pass() { n=$((n + 1)); printf 'PASS  [%s]\n' "$1"; }
fail() { n=$((n + 1)); fails=$((fails + 1)); printf 'FAIL  [%s]  %s\n' "$1" "${2:-}"; }
refused() {  # refused <label> -- cmd...   (any refusal; for a case with only one rail it can hit)
  label="$1"; shift 2
  out=$("$@" 2>&1); rc=$?
  if [ "$rc" = 2 ]; then pass "$label"; else fail "$label" "rc=$rc, wanted a refusal"; fi
}
refused_because() {  # refused_because <label> <text the refusal must carry> -- cmd...
  label="$1"; want="$2"; shift 3
  out=$("$@" 2>&1); rc=$?
  if [ "$rc" != 2 ]; then fail "$label" "rc=$rc, wanted a refusal"; return; fi
  case "$out" in
    *"$want"*) pass "$label" ;;
    *) fail "$label" "refused, but on another rail: $(printf '%s' "$out" | grep -m 1 'refused:')" ;;
  esac
}
allowed() {  # allowed <label> [wanted text] -- cmd...   (the gate let it through; a dry run touches nothing)
  # RC 0 OR 3, AND NOTHING ELSE. This used to accept any exit but 2, so a script that DIED — rc 1 from a
  # syntax error, an unbound variable, a missing library — counted as a pass. #69's review found it in
  # `wake-two-roots.sh`; the same helper lived here. The two allowed codes are the script's own contract:
  # 0 done, 3 the target is alive so SendMessage it. Anything else is a crash wearing a pass.
  label="$1"; shift
  want=""
  if [ "${1:-}" != "--" ]; then want="$1"; shift; fi
  shift   # the `--`
  out=$("$@" 2>&1); rc=$?
  case "$rc" in
    0|3) ;;
    *) fail "$label" "rc=$rc (only 0 or 3 are this script's success codes); $(printf '%s' "$out" | head -n 1)"; return ;;
  esac
  if printf '%s' "$out" | grep -q 'refused:'; then
    fail "$label" "rc=$rc but the output refuses: $(printf '%s' "$out" | grep -m 1 'refused:')"; return
  fi
  if [ -n "$want" ]; then
    case "$out" in
      *"$want"*) ;;
      *) fail "$label" "rc=$rc and nothing refused, but the output does not carry '$want'"; return ;;
    esac
  fi
  pass "$label"
}

# THE REPORTING LINE, in a temp notebook. The chain names are RECORDS, not sessions: nothing is dispatched
# under them, so none of them reaches the fleet view. The throwaway's line runs up to the rear admiral,
# which is what an A0 case needs, and every hop is a file this script wrote.
mkdir -p "$NB/2026-09"
mk() { printf -- '---\ntitle: %s\nsession: "%s"\nsession-status: %s\nreports-to: "%s"\n---\n\n[test artifact — safe to delete]\n' "$1" "$2" "$3" "$4" > "$NB/2026-09/$1.md"; }
TARGET="[L0-FL] wake-and-promote battery target"
HOP="[C1-CC] battery line hop"
TOP="[C0-CC] battery line top"
mk "Agent session 2026-09-27T0101" "$TARGET" ended "$HOP"
mk "Agent session 2026-09-27T0102" "$HOP"    running "$TOP"
mk "Agent session 2026-09-27T0103" "$TOP"    running "[A0] rear admiral"
# The listing's name for the throwaway must match the line's first entry, or every case refuses on a missing
# record and none of them measures a gate. Said out loud, and checked, rather than discovered case by case.
# THE SHORT ID, AND ONLY THE SHORT ID. This battery writes its captain stub at `jobs/<the id you pass>/
# state.json`, and the script reads that stub by the SHORT id — so a full 36-character id produces four
# silent failures with nothing to say why. It cost the commander exactly that on #69, so it is a STOP rather
# than a comment. `claude stop` takes the short form too; `--resume` is the one that needs the full id.
case "$LT" in
  ????????-????-????-????-????????????)
    printf 'STOP  %s is a FULL sessionId; this battery needs the SHORT job id (its first 8 characters),\n' "$LT"
    printf '      because it writes its job stub at jobs/<id>/state.json and the script reads it by the short id.\n'
    printf '      Try: %s\n' "$(printf '%s' "$LT" | cut -c1-8)"
    exit 1 ;;
esac

listed=$(claude agents --json --all 2>/dev/null | jq -r --arg i "$LT" '.[] | select(.id == $i or .sessionId == $i) | .name' | head -n 1)
if [ "$listed" != "$TARGET" ]; then
  printf 'STOP  the throwaway %s is listed as "%s", and this battery writes its reporting line under "%s".\n' "$LT" "${listed:-(not listed at all)}" "$TARGET"
  printf '      Dispatch it under that name, or change TARGET here to match. Nothing was run.\n'
  exit 1
fi

printf -- '=== wake-session: the A0 caller is read at all (it used to die on the rank code)\n'
allowed "A0 reaches a lieutenant in its line" -- \
  "$W" --session $LT --by "[A0] rear admiral" --why "A0 test" --notebook-dir "$NB" --jobs-dir "$JOBSNULL" --log "$LOG" --dry-run
refused "a name with no rank code is still refused" -- \
  "$W" --session $LT --by "rear admiral" --why x --notebook-dir "$NB" --jobs-dir "$JOBSNULL" --log "$LOG" --dry-run

printf -- '=== wake-session: a captain-ranked target is reachable by A0 and by nobody below it\n'
# The rank here comes from JOBSCAP, not from the name: same id, same display name, different rank.
allowed "A0 reaches a captain" -- \
  "$W" --session $LT --by "[A0] rear admiral" --why "A0 test" --notebook-dir "$NB" --jobs-dir "$JOBSCAP" --log "$LOG" --dry-run
refused_because "a commander may not reach a captain" "is a captain" -- \
  "$W" --session $LT --by "$HOP" --why x --notebook-dir "$NB" --jobs-dir "$JOBSCAP" --log "$LOG" --dry-run
refused_because "a captain may not reach a captain" "is a captain" -- \
  "$W" --session $LT --by "$TOP" --why x --notebook-dir "$NB" --jobs-dir "$JOBSCAP" --log "$LOG" --dry-run
refused_because "a lieutenant may not reach a captain" "is a captain" -- \
  "$W" --session $LT --by "[L0-CC] battery peer" --why x --notebook-dir "$NB" --jobs-dir "$JOBSCAP" --log "$LOG" --dry-run
# THE PAIR THAT PROVES WHERE THE RANK COMES FROM. One id, one display name, two job states: the commander is
# refused under the captain stub and allowed under the empty one. If either script ever went back to reading
# the rank off the display name, this pair would fail rather than quietly agree.
allowed "the same target, rank from the name instead, is reachable by its commander" -- \
  "$W" --session $LT --by "$HOP" --why "rank source test" --notebook-dir "$NB" --jobs-dir "$JOBSNULL" --log "$LOG" --dry-run

printf -- '=== wake-session: the survey reads A0 and names its rank\n'
out=$("$W" --all --by "[A0] rear admiral" --notebook-dir "$NB" --jobs-dir "$JOBSNULL" --log "$LOG" 2>&1)
printf '%s' "$out" | grep -q 'rear admiral' && pass "survey names the rear admiral as the caller" || fail "survey names the rear admiral as the caller"
printf '%s' "$out" | grep -q 'SHIP\|NO SHIP CODE' && pass "survey still groups by ship for an A0 caller" || fail "survey still groups by ship for an A0 caller"
# The survey hides a captain-ranked row from a caller below A0, and shows it to A0. Same stub, two callers.
out=$("$W" --all --by "$HOP" --notebook-dir "$NB" --jobs-dir "$JOBSCAP" --log "$LOG" 2>&1)
if printf '%s' "$out" | grep -q "$LT"; then fail "the survey hides a captain-ranked row from a commander" "it is listed"; else pass "the survey hides a captain-ranked row from a commander"; fi
out=$("$W" --all --by "[A0] rear admiral" --notebook-dir "$NB" --jobs-dir "$JOBSCAP" --log "$LOG" 2>&1)
if printf '%s' "$out" | grep -q "$LT"; then pass "and shows it to A0"; else fail "and shows it to A0" "it is missing"; fi

printf -- '=== wake-session: the accept verbs write path, `human:nelson` (rank -2, package 5)\n'
# TWO GATES, NOT ONE, and package 5 only widened the first. The rank gate lets a caller above a captain
# through; the reporting-line gate asks whether the target is in that caller's line. `human:nelson` is not a
# session, so no entry can ever name it as a superior, and with only the rank gate widened the notifier's
# wake refused every target it had. These cases hold both halves: the reach, and the line it still needs.
allowed "human:nelson reaches a captain" -- \
  "$W" --session $LT --by human:nelson --why "verb path test" --notebook-dir "$NB" --jobs-dir "$JOBSCAP" --log "$LOG" --dry-run
allowed "human:nelson reaches a lieutenant three hops down" -- \
  "$W" --session $LT --by human:nelson --why "verb path test" --notebook-dir "$NB" --jobs-dir "$JOBSNULL" --log "$LOG" --dry-run
for bad in "human:nelsons" "human:someone" "Human:Nelson" "human:" "human:nelson " "nelson"; do
  refused "'$bad' is not the write path (the arm is exact)" -- \
    "$W" --session $LT --by "$bad" --why x --notebook-dir "$NB" --jobs-dir "$JOBSNULL" --log "$LOG" --dry-run
done
# THE EXEMPTION IS NOT A BYPASS. A line that cannot be followed is still refused for this caller too — that
# is the property the whole check exists for, so it gets its own case rather than a sentence in a header.
mk "Agent session 2026-09-27T0101" "$TARGET" ended "[C2-CC] no such session"
refused_because "an unfollowable line is refused for the write path as well" "reporting line" -- \
  "$W" --session $LT --by human:nelson --why x --notebook-dir "$NB" --jobs-dir "$JOBSNULL" --log "$LOG" --dry-run
mk "Agent session 2026-09-27T0101" "$TARGET" ended "$HOP"
allowed "and the same target passes again once its line is whole" -- \
  "$W" --session $LT --by human:nelson --why x --notebook-dir "$NB" --jobs-dir "$JOBSNULL" --log "$LOG" --dry-run

printf -- '=== promote-session: A0 as the promoter\n'
allowed "A0 demotes a captain, ship taken from the target" -- \
  "$P" --session $LT --to commander --name "[C1-FL] battery target" --by "[A0] rear admiral" --why "A0 test" --jobs-dir "$JOBSCAP" --log "$LOG" --dry-run
allowed "A0 with --ship given explicitly" -- \
  "$P" --session $LT --to commander --name "[C1-CC] battery target" --by "[A0] rear admiral" --ship CC --why "A0 test" --jobs-dir "$JOBSCAP" --log "$LOG" --dry-run
refused "A0 with a --name on a different ship from the target" -- \
  "$P" --session $LT --to commander --name "[C1-OB] battery target" --by "[A0] rear admiral" --why x --jobs-dir "$JOBSCAP" --log "$LOG" --dry-run
refused "--name never carries A0" -- \
  "$P" --session $LT --to commander --name "[A0] rear admiral" --by "[A0] rear admiral" --why x --jobs-dir "$JOBSNULL" --log "$LOG" --dry-run
refused "--to captain stays refused, A0 included" -- \
  "$P" --session $LT --to captain --name "[C0-CC] x" --by "[A0] rear admiral" --why x --jobs-dir "$JOBSNULL" --log "$LOG" --dry-run
# This passes `--to commander` with a `[C1-CC]` caller, which is the caller's OWN rank, not `--to captain` —
# that rail is a different one and is already covered at line 166 ("--to captain stays refused, A0 included").
# So what this proves is narrower: a commander may not promote a peer up to its own rank, on the "not below"
# rail rather than the captain rail.
refused_because "a commander may not promote a peer to its own rank" "not below" -- \
  "$P" --session $LT --to commander --name "[C1-CC] x" --by "$HOP" --why x --jobs-dir "$JOBSCAP" --log "$LOG" --dry-run

printf -- '=== promote-session: the old rails still hold\n'
refused "bare --by with no --ship (non-A0)" -- \
  "$P" --session $LT --to lieutenant-commander --name "[C2-CC] x" --by "[C0] claude code" --why x --jobs-dir "$JOBSNULL" --log "$LOG" --dry-run
refused "--ship naming another captain's ship" -- \
  "$P" --session $LT --to lieutenant-commander --name "[C2-OB] x" --by "[C0-CC] claude code" --ship OB --why x --jobs-dir "$JOBSNULL" --log "$LOG" --dry-run
allowed "an ordinary FL promotion still works" -- \
  "$P" --session $LT --to lieutenant-commander --name "[C2-FL] battery target" --by "[C0-CC] claude code" --ship FL --why x --jobs-dir "$JOBSNULL" --log "$LOG" --dry-run

printf -- '=== promote-session: the write path notifies, it does not promote (package 5)\n'
# The seam `rank_of_caller` is shared with wake-session.sh, so the -2 arm reaches this script too. Nothing
# ruled that the verb path may change a rank, and its refusal must say that rather than ask for a --ship.
refused_because "the write path may not promote" "does not promote" -- \
  "$P" --session $LT --to lieutenant-commander --name "[C2-FL] x" --by human:nelson --why x --jobs-dir "$JOBSNULL" --log "$LOG" --dry-run

printf -- '=== a ship-coded A0 is NOT the rear admiral (reviewer finding on PR #56)\n'
for bad in "[A0-CC] impostor" "[A0-] noship-empty" "[A0-CC-extra] weird" "[A0x] y" "[a0] z"; do
  refused "wake: '$bad' carries no rank code" -- \
    "$W" --session "$LT" --by "$bad" --why x --notebook-dir "$NB" --jobs-dir "$JOBSNULL" --log "$LOG" --dry-run
  refused "promote: '$bad' carries no rank code" -- \
    "$P" --session "$LT" --to lieutenant-commander --name "[C2-CC] x" --by "$bad" --why x --jobs-dir "$JOBSNULL" --log "$LOG" --dry-run
done
refused "promote: --name '[A0-CC] x' is refused (its code matches no --to)" -- \
  "$P" --session "$LT" --to lieutenant-commander --name "[A0-CC] x" --by "[A0] rear admiral" --why x --jobs-dir "$JOBSNULL" --log "$LOG" --dry-run

printf -- '=== wake-session: the write path tells ONE session, and never surveys or resumes the fleet\n'
# THE WORST OF THE REVIEW'S FINDINGS, and it was invisible from the feature's own side. Rank -2 sits above
# every rank, so the two widened gates also opened `--all`: the survey stopped skipping captains, every row
# was "below" the caller including the rear admiral's own, and the new reporting-line exemption passed any
# target whose chain ends at the top — which is every correctly-recorded session. `--all --resume-stopped
# --by human:nelson` would have resumed the whole fleet in one command, from a string nothing authenticates.
# Both forms are refused now, and the refusal says which road it is closing rather than "not below".
refused_because "the write path may not survey the fleet" "tells one session at a time" -- \
  "$W" --all --by human:nelson --notebook-dir "$NB" --jobs-dir "$JOBSNULL" --log "$LOG"
refused_because "the write path may not mass-resume the fleet" "tells one session at a time" -- \
  "$W" --all --resume-stopped --by human:nelson --why x --notebook-dir "$NB" --jobs-dir "$JOBSNULL" --log "$LOG"
# AND THE RANKS KEEP IT. The refusal is keyed on the caller being BELOW -1, so the rear admiral's own survey
# must still work — a fix that closed the road for everyone would be its own outage.
allowed "and A0 still surveys, as it always did" -- \
  "$W" --all --by "[A0] rear admiral" --notebook-dir "$NB" --jobs-dir "$JOBSNULL" --log "$LOG"
# The single-target road is what the verb actually uses, and it is untouched by the refusal above.
allowed "while the write path still reaches one named session" -- \
  "$W" --session $LT --by human:nelson --why "one at a time" --notebook-dir "$NB" --jobs-dir "$JOBSNULL" --log "$LOG" --dry-run

printf -- '=== the leash on --jobs-dir (captain, 2026-09-27)\n'
# BOTH WAYS, in both scripts. A temp path is accepted — every case above proves that, since they all pass one
# — and a path outside /tmp or the system temp dir is refused with its own sentence. The refusal must name
# the flag rather than fail later on a missing state.json, because a flag that silently ignores its argument
# is worse than one that refuses it. `$HOME/.claude/jobs` is the real one, and it is the exact path a caller
# would reach for to make this flag do something in a real run.
refused_because "wake: --jobs-dir outside a temp dir is refused" "must be under /tmp" -- \
  "$W" --session $LT --by "[A0] rear admiral" --why x --notebook-dir "$NB" --jobs-dir "$HOME/.claude/jobs" --log "$LOG" --dry-run
refused_because "promote: --jobs-dir outside a temp dir is refused" "must be under /tmp" -- \
  "$P" --session $LT --to lieutenant-commander --name "[C2-FL] x" --by "[A0] rear admiral" --why x --jobs-dir "$HOME/.claude/jobs" --log "$LOG" --dry-run
refused_because "wake: --jobs-dir must exist" "directory that exists" -- \
  "$W" --session $LT --by "[A0] rear admiral" --why x --notebook-dir "$NB" --jobs-dir "$TMP/no-such-jobs-dir" --log "$LOG" --dry-run
# A SYMLINK IS RESOLVED BEFORE IT IS JUDGED, so a temp-looking path pointing at the real jobs dir is refused
# too. Without `pwd -P` the case-glob would have passed it, and the leash would have been decoration.
ln -s "$HOME/.claude/jobs" "$TMP/looks-like-temp" 2>/dev/null || true
if [ -d "$HOME/.claude/jobs" ]; then
  refused_because "wake: a temp symlink to the real jobs dir is refused" "must be under /tmp" -- \
    "$W" --session $LT --by "[A0] rear admiral" --why x --notebook-dir "$NB" --jobs-dir "$TMP/looks-like-temp" --log "$LOG" --dry-run
else
  printf 'SKIP  a temp symlink to the real jobs dir is refused (there is no %s to point at)\n' "$HOME/.claude/jobs"
fi
allowed "and a real temp path is still accepted" -- \
  "$W" --session $LT --by "[A0] rear admiral" --why x --notebook-dir "$NB" --jobs-dir "$JOBSNULL" --log "$LOG" --dry-run

printf -- '=== wake-session: every listed rank code is accepted, not the numbers it maps to\n'
# THIS ASSERTS ONLY THAT THE CODE PARSES. Each code below reaches the "--by" check as a valid rank code and
# gets past it, so the run dies on the unknown session instead of on an unrecognized caller — that is the one
# thing this loop measures. It says nothing about which NUMBER a code maps to; the "want" alongside each pair
# is documentation of the intended value, carried into the label for a human reading the output, not
# something this loop compares against anything. The numbers themselves are asserted in
# claude/tests/fleet-ranks/table-agrees.sh — read that file for evidence about the rank values.
for pair in "A0:-1" "C0:0" "C1:1" "C2:2" "L0:3" "L1:3"; do
  code=${pair%%:*}; want=${pair##*:}
  got=$(printf '%s' "$("$W" --session nosuch --by "[$code] x" --why x --notebook-dir "$NB" --jobs-dir "$JOBSNULL" --dry-run 2>&1)")
  # a valid code gets past the --by check and dies on the unknown session instead
  if printf '%s' "$got" | grep -q 'no background session'; then pass "[$code] is accepted as a rank code (rank $want, per table-agrees.sh)"
  else fail "[$code] is accepted as a rank code (rank $want, per table-agrees.sh)" "$(printf '%s' "$got" | head -n 1)"; fi
done

# THIS MUST BE A REAL CASE, counted through pass/fail like every other one above — it used to be printed and
# never compared, which is the same disease this file's own header describes for the captain cases: a check
# that cannot fail is not a check. Every case above was a dry run or a refusal, so no case should ever have
# appended a "## " entry to the log; assert that instead of only announcing the number, while still printing
# the number in the label, because it is the first thing worth reading when it is not 0.
lines=$(grep -c '^## ' "$LOG" 2>/dev/null) || lines=0
if [ "$lines" = 0 ]; then pass "no case wrote a log line (log lines written: $lines)"
else fail "no case wrote a log line (log lines written: $lines)" "every case was a dry run or a refusal"; fi
printf '%s cases, %s failed\n' "$n" "$fails"
[ "$fails" = 0 ] || exit 1
