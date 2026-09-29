#!/usr/bin/env bash
# The CONSTRUCTION TEST for `claude/bin/_fleet-ranks.sh`: does the one table answer exactly what the two
# copies answered before they were extracted, and does neither consumer still carry a copy?
#
# WHY IT IS SHAPED THIS WAY. An extraction is a refactor, and the only thing a refactor has to prove is
# that nothing moved. So the expected answers below are written out as literals rather than computed from
# the table — a test that asks the table what the table says would pass on any table. They were taken from
# the two copies as they stood at the merge base, and the rank numbers among them are the whole
# machine-readable part of rule 19: who may wake and promote whom.
#
# It also asserts the NEGATIVE: neither consumer defines any of the shared names any more. An extraction
# that leaves a copy behind is worse than no extraction, because the copy will win in one script and lose
# in the other and nothing will say so.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
BIN="$HERE/../../bin"
. "$BIN/_fleet-ranks.sh" || { echo "FAIL: the table could not be sourced"; exit 1; }
n=0; fails=0
eq() {  # eq <label> <got> <want>
  n=$((n + 1))
  if [ "$2" = "$3" ]; then printf 'PASS  %-56s %s\n' "$1" "$2"
  else fails=$((fails + 1)); printf 'FAIL  %-56s got %s, want %s\n' "$1" "$2" "$3"; fi
}

echo "=== rank_of_name: every code, both forms, and the A0 rule"
eq "[A0] bare"                "$(rank_of_name '[A0] rear admiral')"   -1
eq "[A0-CC] is NOT the rear admiral" "$(rank_of_name '[A0-CC] impostor')" 9
eq "[A0-] is not either"      "$(rank_of_name '[A0-] x')"             9
eq "[C0] bare"                "$(rank_of_name '[C0] claude code')"     0
eq "[C0-CC] coded"            "$(rank_of_name '[C0-CC] claude code')"  0
eq "[C1] bare"                "$(rank_of_name '[C1] plugins')"         1
eq "[C1-CC] coded"            "$(rank_of_name '[C1-CC] plugins')"      1
eq "[C2] bare"                "$(rank_of_name '[C2] spec')"            2
eq "[C2-OB] coded"            "$(rank_of_name '[C2-OB] spec')"         2
eq "[L0] bare"                "$(rank_of_name '[L0] dotfiles')"        3
eq "[L0-FL] coded"            "$(rank_of_name '[L0-FL] dotfiles')"     3
eq "[L1] legacy bare"         "$(rank_of_name '[L1] old')"             3
eq "[L1-CC] legacy coded"     "$(rank_of_name '[L1-CC] old')"          3
eq "no rank code at all"      "$(rank_of_name 'dotfiles')"             9
eq "a lowercase code"         "$(rank_of_name '[c0] x')"               9
eq "a code later in the name" "$(rank_of_name 'x [C0] y')"             9

echo
echo "=== rank_of_caller: the rank codes fall through, and the one non-rank arm does not"
# `human:nelson` WAS in this list, asserting that the seam was still empty — and the review of #61 said
# plainly that the assertion had to be DELETED when the arm landed rather than kept, because it was a claim
# about the seam being unused and not about correctness. Package 5 landed the arm, so it is deleted, and
# what replaces it is the pair of facts that matter: the table itself still does not know the name, and the
# caller function does.
for name in '[A0] rear admiral' '[C0] x' '[C1-CC] y' '[L0] z' 'nothing'; do
  label="caller and name agree on '$name'"
  eq "$label" "$(rank_of_caller "$name")" "$(rank_of_name "$name")"
done
eq "the TABLE does not know human:nelson"      "$(rank_of_name 'human:nelson')"   9
eq "the CALLER function does, at -2"           "$(rank_of_caller 'human:nelson')" -2
# -2 outranks the rear admiral at -1, which is the point and the risk: it is the only caller that may wake
# a captain or the rear admiral, and `--by` is not authenticated, so the protection is the log line and not
# the number. Asserted here so that a later edit cannot quietly demote or promote it.
eq "it outranks the rear admiral"              "$([ "$(rank_of_caller 'human:nelson')" -lt "$(rank_of_name '[A0] x')" ] && echo yes)" yes
eq "a near-miss spelling is NOT the arm"       "$(rank_of_caller 'human:Nelson')"  9
eq "nor is a bare human:"                      "$(rank_of_caller 'human:')"        9
eq "nor is a name that merely contains it"     "$(rank_of_caller 'x human:nelson')" 9

echo
echo "=== rank_of_agent: the definition names, and no A0 definition"
eq "captain"                        "$(rank_of_agent captain)"                          0
eq "commander"                      "$(rank_of_agent commander)"                        1
eq "lieutenant-commander"           "$(rank_of_agent lieutenant-commander)"             2
eq "lieutenant-commander-repository" "$(rank_of_agent lieutenant-commander-repository)"  2
eq "lieutenant"                     "$(rank_of_agent lieutenant)"                       3
eq "lieutenant-repository"          "$(rank_of_agent lieutenant-repository)"             3
eq "an unknown definition"          "$(rank_of_agent rear-admiral)"                      9

echo
echo "=== the words and the codes"
eq "word -1" "$(word_of_rank -1)" "rear admiral"
eq "word 0"  "$(word_of_rank 0)"  captain
eq "word 1"  "$(word_of_rank 1)"  commander
eq "word 2"  "$(word_of_rank 2)"  "lieutenant commander"
eq "word 3"  "$(word_of_rank 3)"  lieutenant
eq "word 9"  "$(word_of_rank 9)"  unknown
eq "bare code -1" "$(bare_code_of_rank -1)" "[A0]"
eq "bare code 0"  "$(bare_code_of_rank 0)"  "[C0]"
eq "bare code 3"  "$(bare_code_of_rank 3)"  "[L0]"
eq "bare code 9"  "$(bare_code_of_rank 9)"  "[??]"
# -1 FIRST, because it is the input the first version of this file got wrong and this test did not cover:
# `code_of_rank` was rewritten with its own hardcoded table instead of deriving from `bare_code_of_rank`,
# which turned `[A0-CC]` into `[??-CC]`. Unreachable today — `--to` only ever yields 1, 2 or 3 — and
# therefore exactly what a test has to hold, since nothing else catches the day it is reachable.
eq "coded -1 CC"  "$(code_of_rank -1 CC)"   "[A0-CC]"
eq "coded 9 CC"   "$(code_of_rank 9 CC)"    "[??-CC]"
eq "coded 0 CC"   "$(code_of_rank 0 CC)"    "[C0-CC]"
eq "coded 2 OB"   "$(code_of_rank 2 OB)"    "[C2-OB]"
eq "coded 3 FL"   "$(code_of_rank 3 FL)"    "[L0-FL]"
eq "coded 0 MA"   "$(code_of_rank 0 MA)"    "[C0-MA]"

echo
echo "=== the ships"
# MA, the macOS ship (captain `[C0-MA] macos`), on Nelson's "A, MA" of 2026-09-29; the eight area ships
# PE PP HH FN ED WK HB DV on the areas ruling of the same day (log 2026-09-29T03:35).
eq "KNOWN_SHIPS"          "$KNOWN_SHIPS"               "CC OB HS MA PE PP HH FN ED WK HB DV FL"
eq "FLOATING_SHIP"        "$FLOATING_SHIP"             "FL"
eq "FL is in the list"    "$(ship_is_known FL && echo yes)" yes
eq "CC is known"          "$(ship_is_known CC && echo yes)" yes
eq "OB is known"          "$(ship_is_known OB && echo yes)" yes
eq "HS is known"          "$(ship_is_known HS && echo yes)" yes
eq "MA is known"          "$(ship_is_known MA && echo yes)" yes
eq "PE is known"          "$(ship_is_known PE && echo yes)" yes
eq "PP is known"          "$(ship_is_known PP && echo yes)" yes
eq "HH is known"          "$(ship_is_known HH && echo yes)" yes
eq "FN is known"          "$(ship_is_known FN && echo yes)" yes
eq "ED is known"          "$(ship_is_known ED && echo yes)" yes
eq "WK is known"          "$(ship_is_known WK && echo yes)" yes
eq "HB is known"          "$(ship_is_known HB && echo yes)" yes
eq "DV is known"          "$(ship_is_known DV && echo yes)" yes
eq "XX is not"            "$(ship_is_known XX || echo no)"  no
eq "an empty code is not" "$(ship_is_known '' || echo no)"  no
eq "ship of [L0-CC]"      "$(ship_of_name '[L0-CC] dotfiles')" CC
eq "ship of [C0-HS]"      "$(ship_of_name '[C0-HS] orange')"   HS
eq "ship of [C0-MA]"      "$(ship_of_name '[C0-MA] macos')"    MA
eq "ship of [C0-DV]"      "$(ship_of_name '[C0-DV] divorce')"  DV
eq "ships in words"       "$(ships_in_words)"          "CC, OB, HS, MA, PE, PP, HH, FN, ED, WK, HB or DV"
eq "ships in words under a strict-mode IFS" "$(IFS=$'\n\t'; ships_in_words)" "CC, OB, HS, MA, PE, PP, HH, FN, ED, WK, HB or DV"
eq "ship of [L0-FL]"      "$(ship_of_name '[L0-FL] dotfiles')" FL
eq "ship of a bare name"  "$(ship_of_name '[L0] dotfiles')"    ""
eq "ship of [A0]"         "$(ship_of_name '[A0] rear admiral')" ""

echo
echo "=== promote-session.sh speaks the table: MA passes the ship gate, and both refusals name every ship"
# Added 2026-09-29 on review of #72: the refusal sentences once typed the ship list by hand, and no case
# read their text, so a ship missing from them would have shipped with every check green.
# NOTHING HERE READS THE MACHINE OR THE FLEET. A first version ran promote-session.sh as it stood, and a
# second review showed it went red under an empty HOME (no ~/.claude/agents/lieutenant.md) and queried the
# live `claude agents` listing. So HOME is a temp dir holding a stub rank definition, and `claude` is a stub
# on PATH that prints one fixture row; the all-zero id is no real session, --dry-run is set, and --jobs-dir
# and --log point into the temp dir. The one real dependency is `jq`, which the script itself needs; without
# it these cases are counted as skipped, and the skip is in the summary line.
PTMP=$(mktemp -d "${TMPDIR:-/tmp}/table-agrees.XXXXXX") || exit 1
trap 'trash "$PTMP" 2>/dev/null || true' EXIT   # trash, never rm (CLAUDE.md); a dir it cannot trash stays in the temp dir
ZERO=00000000-0000-0000-0000-000000000000
mkdir -p "$PTMP/home/.claude/agents" "$PTMP/stubbin" "$PTMP/cwd"
: > "$PTMP/home/.claude/agents/lieutenant-commander.md"
# The Pause note is a fixture too, set to not paused, so the gate never reads the fleet's own note and a
# change to how it treats a missing note cannot turn a ship case red (review 3 of #72).
printf -- '---\npaused: false\n---\n' > "$PTMP/pause.md"
# The fixture rows: a lieutenant, never a rank above one (tests/README.md section 4). The bare-named one
# has no ship, so the rear admiral's path has none to take from it.
row() { printf '[{"id":"zz000000","sessionId":"%s","name":"%s","cwd":"%s"}]\n' "$ZERO" "$1" "$PTMP/cwd" > "$PTMP/listing.json"; }
printf '#!/bin/sh\ncat "%s"\n' "$PTMP/listing.json" > "$PTMP/stubbin/claude"; chmod +x "$PTMP/stubbin/claude"
pr() { HOME="$PTMP/home" PATH="$PTMP/stubbin:$PATH" bash "$BIN/promote-session.sh" --session $ZERO --to lieutenant-commander --why x --jobs-dir "$PTMP" --log "$PTMP/log.md" --pause-note "$PTMP/pause.md" --dry-run "$@" 2>&1; }
# Passing means the dry run reaches its end and names the new ship; any refusal stops it earlier.
reached() { case "$2" in *"ship $1 ("*"dry run: nothing touched"*) echo past-the-ship-gates ;; *) printf '%s' "$2" ;; esac; }
skipped=0
if command -v jq >/dev/null 2>&1; then
  row "[L0] ship words target"
  out=$(pr --name "[C2] x" --by "[C0] ship words test")
  eq "no ship on --by: the refusal names every ship" "$out" "promote-session: --by has no ship code; pass --ship CC, OB, HS, MA, PE, PP, HH, FN, ED, WK, HB or DV (FL for a floating session)"
  out=$(pr --name "[C2-CC] x" --by "[A0] rear admiral")
  eq "no ship on the target: the refusal names every ship" "$out" "promote-session: refused: \`[L0] ship words target\` carries no ship code and [A0] rear admiral has none either, so the new name's ship cannot be read from anywhere; pass --ship CC, OB, HS, MA, PE, PP, HH, FN, ED, WK, HB or DV (FL for a floating session)"
  out=$(pr --name "[C2-MA] x" --by "[C0] ship words test" --ship MA)
  eq "--ship MA and a [C2-MA] name pass the ship gates" "$(reached MA "$out")" past-the-ship-gates
  # The common path: a coded MA caller, no --ship, on an MA target (the ship comes from the caller).
  row "[L0-MA] ship words target"
  out=$(pr --name "[C2-MA] x" --by "[C0-MA] macos")
  eq "[C0-MA] on an MA target, no --ship, passes" "$(reached MA "$out")" past-the-ship-gates
else
  skipped=4; printf 'SKIP  the four promote-session cases: jq is not installed, and the script needs it\n'
fi

echo
echo "=== the negative: neither consumer may still define a shared name"
for f in wake-session.sh promote-session.sh; do
  for fn in rank_of_name rank_of_caller rank_of_agent word_of_rank bare_code_of_rank code_of_rank ship_of_name ship_is_known ships_in_words; do
    # `grep -c` PRINTS 0 and EXITS 1 when it finds nothing, so a `|| echo 0` fallback appends a second
    # zero and the value becomes two lines. Learned here, at the cost of twenty false failures.
    # `^name()` WITHOUT requiring the brace: a copy written with `{` on the next line slipped past the
    # stricter pattern, and the review proved it by leaving one behind and watching this test stay green.
    c=$(grep -c "^$fn()" "$BIN/$f" 2>/dev/null || true)
    eq "$f does not define $fn" "$c" 0
  done
  for v in KNOWN_SHIPS FLOATING_SHIP; do
    c=$(grep -c "^$v=" "$BIN/$f" 2>/dev/null || true)
    eq "$f does not set $v" "$c" 0
  done
  c=$(grep -c '_fleet-ranks.sh' "$BIN/$f" 2>/dev/null || true)
  if [ "$c" -ge 1 ]; then eq "$f sources the table" yes yes; else eq "$f sources the table" no yes; fi
done

# The count is asserted, not only printed (tests/README.md rule 1): 84 before the MA cases, 92 after
# the review of #72 (three MA table cases, `ships_in_words`, two promote-session cases, and the two new
# negative checks), 93 with the rear admiral's refusal, 102 with the eight area ships (one
# known-check each, and the ship of a [C0-DV] name), 103 with the [C0-MA] common-path case, and 104 with ships_in_words under a strict-mode IFS.
# Change EXPECTED only in the commit that adds or removes a check, and say which.
# The count is part of the summary line, so a run that lost checks can never print a green summary.
EXPECTED=104
[ $((n + skipped)) = "$EXPECTED" ] || { fails=$((fails + 1)); echo "FAIL  the check count is $((n + skipped)) ($n run, $skipped skipped), expected $EXPECTED: a line was lost or added without updating EXPECTED"; }
printf '\n%s checks (expected %s), %s skipped, %s failed\n' "$n" "$EXPECTED" "$skipped" "$fails"
[ "$fails" = 0 ] || exit 1
