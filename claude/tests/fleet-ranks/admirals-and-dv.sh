#!/usr/bin/env bash
# The two admirals and the DV guard, on Nelson's areas ruling (log 2026-09-29T03:35): "a single admiral
# bringing me decisions from the rest of the vault, with a captain for each area from 10-19 through 80-89",
# then "A, A". Two A0 sessions, matched by FULL NAME, not by the bare code:
#
#   `[A0] rear admiral`   reaches CC OB HS MA and FL, and their lower ranks;
#   `[A0] areas admiral`  reaches the eight area ships, minus DV;
#   neither reaches the other's ships, and any other `[A0] …` name is refused.
#
# DV (80-89 Divorce) is guarded: its captain starts only when Nelson starts it, so both scripts refuse EVERY
# caller that would wake or promote a session on DV or into DV. The only way into DV is Nelson.
#
# WHAT THIS DOES NOT PROVE, said here so no green is read as more than it is: `--by` is self-declared, so the
# scripts bind honest callers only; a SendMessage to a stopped session wakes it with no script; and a bare
# `claude --bg --name "[C0-DV] …"` starts one with no script. The tripwire hook in claude/hooks/ is the only
# guard on the bare command line, and nothing guards SendMessage.
#
# NOTHING HERE READS THE MACHINE OR THE FLEET. HOME is a temp dir holding stub rank definitions, `claude` is
# a stub on PATH that prints a fixture listing, the target id is all zeros, every run is --dry-run, and
# --jobs-dir, --log and the notebook roots point into the temp dir. `jq` is the one real dependency.
#
# THE WAKE CASES ARE PENDING until wake-session.sh calls `ship_refusal`. It sits in open PR #71, which goes
# first, so this branch may not edit it yet. Until then its cases are counted as pending in the summary line
# and never as passes; the day the script calls the function, they run.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
BIN="$HERE/../../bin"
. "$BIN/_fleet-ranks.sh" || { echo "FAIL: the table could not be sourced"; exit 1; }
n=0; fails=0; pending=0
eq() {  # eq <label> <got> <want>
  n=$((n + 1))
  if [ "$2" = "$3" ]; then printf 'PASS  %-60s %s\n' "$1" "$2"
  else fails=$((fails + 1)); printf 'FAIL  %-60s got %s, want %s\n' "$1" "$2" "$3"; fi
}
has() {  # has <label> <got> <want-substring>
  n=$((n + 1))
  case "$2" in *"$3"*) printf 'PASS  %s\n' "$1" ;;
    *) fails=$((fails + 1)); printf 'FAIL  %s\n      got:  %s\n      want: …%s…\n' "$1" "$2" "$3" ;; esac
}

REFUSE_UNKNOWN="is not one of the two admirals"
REFUSE_REACH="does not reach ship"
REFUSE_DV="ship DV is guarded"

echo "=== the table"
# FIRST, that the functions exist: a missing `ship_refusal` prints nothing, which is exactly what every
# admitted case below expects, so without this check those cases would pass on a table that has no rule.
for fn in ship_refusal ship_is_guarded; do
  eq "the table defines $fn" "$(command -v "$fn" >/dev/null 2>&1 && echo yes)" yes
done
eq "REAR_ADMIRAL"              "${REAR_ADMIRAL-}"               "[A0] rear admiral"
eq "AREAS_ADMIRAL"             "${AREAS_ADMIRAL-}"              "[A0] areas admiral"
eq "the rear admiral's ships"  "${REAR_ADMIRAL_SHIPS-}"         "CC OB HS MA FL"
eq "the areas admiral's ships" "${AREAS_ADMIRAL_SHIPS-}"        "PE PP HH FN ED WK HB DV"
eq "the guarded ships"         "${GUARDED_SHIPS-}"              "DV"
eq "DV is guarded"             "$(ship_is_guarded DV && echo yes)" yes
eq "PE is not"                 "$(ship_is_guarded PE || echo no)"  no
eq "an empty ship is not"      "$(ship_is_guarded '' || echo no)"  no
# Every known ship belongs to exactly one admiral: a ship added to KNOWN_SHIPS and to neither list would be
# unreachable by both, and one in both lists would be reachable by each; either is a drift this catches.
for s in $KNOWN_SHIPS; do
  c=0
  case " ${REAR_ADMIRAL_SHIPS-} " in *" $s "*) c=$((c + 1)) ;; esac
  case " ${AREAS_ADMIRAL_SHIPS-} " in *" $s "*) c=$((c + 1)) ;; esac
  eq "$s belongs to exactly one admiral" "$c" 1
done
for s in ${REAR_ADMIRAL_SHIPS-} ${AREAS_ADMIRAL_SHIPS-}; do
  eq "$s in an admiral's list is a known ship" "$(ship_is_known "$s" && echo yes)" yes
done

echo
echo "=== ship_refusal <by> <by-rank> <ship>: the one sentence both scripts print"
eq "rear admiral on CC"             "$(ship_refusal '[A0] rear admiral' -1 CC)"   ""
eq "rear admiral on FL"             "$(ship_refusal '[A0] rear admiral' -1 FL)"   ""
eq "rear admiral on a bare name"    "$(ship_refusal '[A0] rear admiral' -1 '')"   ""
eq "areas admiral on PE"            "$(ship_refusal '[A0] areas admiral' -1 PE)"  ""
eq "areas admiral on HB"            "$(ship_refusal '[A0] areas admiral' -1 HB)"  ""
has "rear admiral on PE is refused"  "$(ship_refusal '[A0] rear admiral' -1 PE)"   "$REFUSE_REACH PE"
has "areas admiral on CC is refused" "$(ship_refusal '[A0] areas admiral' -1 CC)"  "$REFUSE_REACH CC"
has "areas admiral on FL is refused" "$(ship_refusal '[A0] areas admiral' -1 FL)"  "$REFUSE_REACH FL"
# A bare-named session predates the ship codes, and every one of them is on the rear admiral's side.
has "areas admiral on a bare name is refused" "$(ship_refusal '[A0] areas admiral' -1 '')" "carries no ship code"
has "an unknown [A0] name is refused"      "$(ship_refusal '[A0] vice admiral' -1 CC)"  "$REFUSE_UNKNOWN"
has "a padded admiral name is refused"     "$(ship_refusal '[A0] rear admiral ' -1 CC)" "$REFUSE_UNKNOWN"
has "a case-changed admiral name is refused" "$(ship_refusal '[A0] Rear Admiral' -1 CC)" "$REFUSE_UNKNOWN"
has "an unknown [A0] with no ship is refused" "$(ship_refusal '[A0] x' -1 '')"          "$REFUSE_UNKNOWN"
has "DV: the rear admiral is refused"      "$(ship_refusal '[A0] rear admiral' -1 DV)"  "$REFUSE_DV"
has "DV: the areas admiral is refused"     "$(ship_refusal '[A0] areas admiral' -1 DV)" "$REFUSE_DV"
has "DV: a DV captain is refused"          "$(ship_refusal '[C0-DV] divorce' 0 DV)"     "$REFUSE_DV"
has "DV: Nelson's verb path is refused"    "$(ship_refusal 'human:nelson' -2 DV)"       "$REFUSE_DV"
eq "a captain on its own ship: no word here" "$(ship_refusal '[C0-CC] claude code' 0 CC)" ""

# --- the fixture: a temp HOME, a stub claude, a Pause note set to not paused, and one listing per case --
# Every target row is a lieutenant (tests/README.md section 4): an admiral's reach is by ship, not by rank.
command -v jq >/dev/null 2>&1 || { echo "STOP  jq is not installed, and both scripts need it"; exit 1; }
T=$(mktemp -d "${TMPDIR:-/tmp}/admirals-and-dv.XXXXXX") || exit 1
trap 'trash "$T" 2>/dev/null || rm -rf "$T"' EXIT
ZERO=00000000-0000-0000-0000-000000000000
mkdir -p "$T/home/.claude/agents" "$T/stubbin" "$T/cwd" "$T/jobs" "$T/agents/Agent notebook/2026-09" "$T/archive"
for d in captain commander lieutenant-commander lieutenant; do : > "$T/home/.claude/agents/$d.md"; done
printf -- '---\npaused: false\n---\n' > "$T/pause.md"
printf '#!/bin/sh\ncat "$STUB_LISTING"\n' > "$T/stubbin/claude"; chmod +x "$T/stubbin/claude"
listing() {  # listing <target name>: the one row the stub prints
  printf '[{"id":"zz000000","sessionId":"%s","name":"%s","cwd":"%s","status":"stopped"}]\n' "$ZERO" "$1" "$T/cwd" > "$T/listing.json"
}
run_promote() {  # run_promote <target name> <promote args…>
  listing "$1"; shift
  STUB_LISTING="$T/listing.json" HOME="$T/home" PATH="$T/stubbin:$PATH" \
    bash "$BIN/promote-session.sh" --session $ZERO --why x --jobs-dir "$T/jobs" --log "$T/log.md" --pause-note "$T/pause.md" --dry-run "$@" 2>&1
}
# A pass is the dry run reaching its end: any refusal stops it earlier.
passes() { case "$2" in *"dry run: nothing touched"*) eq "$1" passed passed ;; *) eq "$1" "$2" passed ;; esac; }

echo
echo "=== promote-session.sh"
out=$(run_promote "[L0-CC] t" --to lieutenant-commander --name "[C2-CC] t" --by "[A0] vice admiral")
has "an unknown [A0] name is refused" "$out" "$REFUSE_UNKNOWN"
out=$(run_promote "[L0-PE] t" --to lieutenant-commander --name "[C2-PE] t" --by "[A0] rear admiral")
has "the rear admiral does not reach PE" "$out" "$REFUSE_REACH PE"
out=$(run_promote "[L0-CC] t" --to lieutenant-commander --name "[C2-CC] t" --by "[A0] areas admiral")
has "the areas admiral does not reach CC" "$out" "$REFUSE_REACH CC"
out=$(run_promote "[L0] t" --to lieutenant-commander --name "[C2-PE] t" --by "[A0] areas admiral" --ship PE)
has "the areas admiral does not reach a bare-named session" "$out" "carries no ship code"
out=$(run_promote "[L0-CC] t" --to lieutenant-commander --name "[C2-PE] t" --by "[A0] areas admiral" --ship PE)
has "the areas admiral cannot pull a CC session onto PE" "$out" "$REFUSE_REACH CC"
out=$(run_promote "[L0-PE] t" --to lieutenant-commander --name "[C2-PE] t" --by "[A0] areas admiral")
passes "the areas admiral promotes on PE" "$out"
out=$(run_promote "[L0-CC] t" --to lieutenant-commander --name "[C2-CC] t" --by "[A0] rear admiral")
passes "the rear admiral promotes on CC" "$out"
out=$(run_promote "[L0] t" --to lieutenant-commander --name "[C2-CC] t" --by "[A0] rear admiral" --ship CC)
passes "the rear admiral still reaches a bare-named session" "$out"
out=$(run_promote "[L0-DV] t" --to lieutenant-commander --name "[C2-DV] t" --by "[C0-DV] divorce")
has "DV: its own captain is refused" "$out" "$REFUSE_DV"
out=$(run_promote "[L0-DV] t" --to lieutenant-commander --name "[C2-DV] t" --by "[A0] areas admiral")
has "DV: the areas admiral is refused" "$out" "$REFUSE_DV"
out=$(run_promote "[L0] t" --to lieutenant-commander --name "[C2-DV] t" --by "[A0] rear admiral" --ship DV)
has "DV: nothing is promoted INTO DV" "$out" "$REFUSE_DV"
out=$(run_promote "[L0-DV] t" --to lieutenant-commander --name "[C2-FL] t" --by "[A0] rear admiral" --ship FL)
has "DV: nothing is moved OUT of DV either" "$out" "$REFUSE_DV"

echo
echo "=== wake-session.sh"
run_wake() {  # run_wake <target name> <by>
  listing "$1"
  STUB_LISTING="$T/listing.json" HOME="$T/home" PATH="$T/stubbin:$PATH" \
    bash "$BIN/wake-session.sh" --session $ZERO --by "$2" --why x --jobs-dir "$T/jobs" --log "$T/log.md" \
      --pause-note "$T/pause.md" --agents-dir "$T/agents" --notebook-dir "$T/agents/Agent notebook" --archive-dir "$T/archive" --dry-run 2>&1
}
WAKE_CASES=(
  "[L0-CC] t|[A0] vice admiral|$REFUSE_UNKNOWN"
  "[L0-PE] t|[A0] rear admiral|$REFUSE_REACH PE"
  "[L0-CC] t|[A0] areas admiral|$REFUSE_REACH CC"
  "[L0] t|[A0] areas admiral|carries no ship code"
  "[L0-DV] t|[A0] areas admiral|$REFUSE_DV"
  "[L0-DV] t|[A0] rear admiral|$REFUSE_DV"
  "[L0-DV] t|[C0-DV] divorce|$REFUSE_DV"
  "[L0-DV] t|human:nelson|$REFUSE_DV"
)
if grep -q 'ship_refusal' "$BIN/wake-session.sh"; then
  for c in "${WAKE_CASES[@]}"; do
    IFS='|' read -r tgt by want <<<"$c"
    out=$(run_wake "$tgt" "$by")
    has "wake: $by on \`$tgt\` is refused" "$out" "$want"
  done
  # The admitted directions: the gate lets these through. Whether the target is then woken or sent a
  # message is the rest of the script's business, so the assertion is only that no ship refusal fired.
  for c in "[L0-PE] t|[A0] areas admiral" "[L0-CC] t|[A0] rear admiral"; do
    IFS='|' read -r tgt by <<<"$c"
    out=$(run_wake "$tgt" "$by")
    case "$out" in *"$REFUSE_UNKNOWN"*|*"$REFUSE_REACH"*|*"$REFUSE_DV"*) r="$out" ;; *) r=admitted ;; esac
    eq "wake: $by on \`$tgt\` passes the ship gate" "$r" admitted
  done
else
  pending=$(( ${#WAKE_CASES[@]} + 2 ))
  printf 'PENDING  %s wake cases: wake-session.sh does not call ship_refusal yet (it waits on PR #71)\n' "$pending"
fi

# The count is asserted and is part of the summary line (tests/README.md rule 1). Pending cases count
# toward it, so the total is the same before and after wake-session.sh is edited.
EXPECTED=76
[ $((n + pending)) = "$EXPECTED" ] || { fails=$((fails + 1)); echo "FAIL  the check count is $((n + pending)), expected $EXPECTED: a line was lost or added without updating EXPECTED"; }
printf '\n%s checks (expected %s), %s pending, %s failed\n' "$n" "$EXPECTED" "$pending" "$fails"
[ "$fails" = 0 ] || exit 1
