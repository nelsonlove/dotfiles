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
echo "=== rank_of_caller: identical to rank_of_name until package 5 adds its arm"
for name in '[A0] rear admiral' '[C0] x' '[C1-CC] y' '[L0] z' 'nothing' 'human:nelson'; do
  eq "caller and name agree on '$name'" "$(rank_of_caller "$name")" "$(rank_of_name "$name")"
done

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

echo
echo "=== the ships"
eq "KNOWN_SHIPS"          "$KNOWN_SHIPS"               "CC OB HS FL"
eq "FLOATING_SHIP"        "$FLOATING_SHIP"             "FL"
eq "FL is in the list"    "$(ship_is_known FL && echo yes)" yes
eq "CC is known"          "$(ship_is_known CC && echo yes)" yes
eq "OB is known"          "$(ship_is_known OB && echo yes)" yes
eq "HS is known"          "$(ship_is_known HS && echo yes)" yes
eq "XX is not"            "$(ship_is_known XX || echo no)"  no
eq "an empty code is not" "$(ship_is_known '' || echo no)"  no
eq "ship of [L0-CC]"      "$(ship_of_name '[L0-CC] dotfiles')" CC
eq "ship of [C0-HS]"      "$(ship_of_name '[C0-HS] orange')"   HS
eq "ship of [L0-FL]"      "$(ship_of_name '[L0-FL] dotfiles')" FL
eq "ship of a bare name"  "$(ship_of_name '[L0] dotfiles')"    ""
eq "ship of [A0]"         "$(ship_of_name '[A0] rear admiral')" ""

echo
echo "=== the negative: neither consumer may still define a shared name"
for f in wake-session.sh promote-session.sh; do
  for fn in rank_of_name rank_of_caller rank_of_agent word_of_rank bare_code_of_rank code_of_rank ship_of_name ship_is_known; do
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

printf '\n%s checks, %s failed\n' "$n" "$fails"
[ "$fails" = 0 ] || exit 1
