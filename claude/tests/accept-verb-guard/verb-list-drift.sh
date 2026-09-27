#!/bin/bash
# [test artifact — safe to delete] The four accept-verb names are hardcoded in accept-verb-guard.sh in
# more than one place. This asserts they agree.
#
# WHY. The guard's own header says, correctly, that a rename on the Obsidian side must come to this file,
# because the names are hardcoded and the guard never reads the vault. What it does not say is that
# "coming to this file" means editing TWO `qw(...)` lists that sit hundreds of lines apart — at the time
# of writing, line 200 (`my @verbs = qw(...)`, the presence gate) and line 477 (the same four words
# nested inside the run-tool exact-basename check) — plus a prose mention in the header.
#
# MY FIRST VERSION OF THIS COMMENT CLAIMED the battery would stay green on such a drift. I tested that
# instead of asserting it, and it is FALSE: mutating line 200 alone makes the battery fail 10 of 39, and
# mutating line 477 alone makes it fail 2 of 39. Both lists are consulted on paths the battery exercises.
# So the battery does catch a rename, and this test is not the only thing standing between a rename and a
# silent hole. Recorded rather than quietly fixed, because the wrong version is the more plausible-sounding
# one and someone will reach for it again.
#
# WHAT THIS TEST IS STILL FOR, narrower and real:
#   * A FIFTH verb added to one list and not the other. The battery has no case naming a fifth verb, so
#     every one of its 39 verdicts is unchanged — this is the drift it genuinely catches alone.
#   * Saying WHAT is wrong. A drift reports itself through the battery as 2 or 10 unrelated-looking
#     verdict failures; this says "the lists disagree" and prints both, which is the difference between a
#     five-minute diagnosis and an hour of reading verdicts.
#   * Making the duplication visible at all. Nothing else in the repo tells a maintainer there are two
#     lists, and the header's dependency note stops one sentence short of saying so.
#
# The better fix is one list referenced twice, which costs a line and makes this test unnecessary.
set -u
G="${1:?usage: verb-list-drift.sh <path to accept-verb-guard.sh>}"
[ -f "$G" ] || { printf 'no guard at %s\n' "$G" >&2; exit 2; }

# Every qw(...) list whose contents look like squashed verb names: lowercase words, at least one of
# which ends in "currentnote" or is "requestrevision". Printed as a sorted, normalised signature.
sigs=$(perl -ne '
  while (/qw\(([a-z0-9 ]+)\)/g) {
    my @w = split " ", $1;
    next unless grep { /currentnote$/ || $_ eq "requestrevision" } @w;
    printf "%d\t%s\n", $., join(",", sort @w);
  }' "$G")

if [ -z "$sigs" ]; then
  printf 'FAIL  no verb list found in %s — the matcher cannot be checked, which is worse than a drift\n' "$G"
  exit 1
fi

count=$(printf '%s\n' "$sigs" | wc -l | tr -d ' ')
distinct=$(printf '%s\n' "$sigs" | cut -f2 | sort -u | wc -l | tr -d ' ')

printf 'found %s verb list(s) in %s:\n' "$count" "$G"
printf '%s\n' "$sigs" | while IFS=$(printf '\t') read -r line sig; do printf '  line %-5s %s\n' "$line" "$sig"; done

# The expected set, written out so a FIFTH verb added to both lists still trips this until someone
# confirms it here too. That is deliberate: adding a verb is exactly the moment a human should look.
EXPECTED="answercurrentnote,reopencurrentnote,requestrevision,verifycurrentnote"

if [ "$distinct" -ne 1 ]; then
  printf '\nFAIL  the lists DISAGREE (%s distinct signatures) — a rename or addition reached one and not\n' "$distinct"
  printf '      the other. Fix both, then re-run the battery: it will also fail, but it reports this as\n'
  printf '      unrelated-looking verdict failures rather than as the one-line cause printed above.\n'
  exit 1
fi

actual=$(printf '%s\n' "$sigs" | cut -f2 | head -n 1)
if [ "$actual" != "$EXPECTED" ]; then
  printf '\nFAIL  the lists agree with each other but not with this test.\n'
  printf '      expected: %s\n      found:    %s\n' "$EXPECTED" "$actual"
  printf '      If a verb was renamed or a fifth added, confirm it here too — that is the point of this line.\n'
  exit 1
fi

printf '\nPASS  %s list(s), all agreeing, and matching the four verbs this test knows.\n' "$count"
