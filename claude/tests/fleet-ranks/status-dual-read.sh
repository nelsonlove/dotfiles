#!/usr/bin/env bash
# EITHER STATUS KEY, read the same way by all three readers, until 2026-10-04.
#
# WHAT IS BEING GUARDED. The notebook's status machine folds into the vault's ordinary one, ruled by Nelson
# through `[A0] rear admiral` on 2026-09-27: `session-status: running|ended` becomes `status:
# draft/running|archived/ended`. The vault's 55-entry migration and this repository land on different days, so
# every reader here accepts EITHER key during the window. The failure this prevents is SILENT in both
# directions: a reader that knows one key sees a notebook written in the other as having no running entries at
# all, and nothing refuses — the machinery just stops finding what it looks for.
#
# THREE READERS, THREE MECHANISMS, ONE RULE. `claude/lib/session-status.sh` is the authority and is read by
# `rename-notebook.sh` (which refuses a conflict, because renaming the wrong entry cannot be undone) and by
# `claude/hooks/notebook-name-sync.sh` (which never refuses anything, because it must never fail a turn).
# `wake-session.sh` carries the rule inside its one-pass `awk` index, because a shell function per file would
# turn a survey into hundreds of processes. This suite exists because those are three copies of one rule, and
# the last time this repo held two copies of one rule they drifted — see #61 and the pause parser.
#
# IT RUNS UNATTENDED. Every case but the first is a temp notebook this script writes; no fleet id, no live
# session dispatched, no `claude` command, and the two scripts are pointed at the temp notebook with their own
# test flags.
#
# THE FIRST CASE IS THE REAL POPULATION (the notebook and, since 2026-09-29, the archive), read-only, under `bash -euo pipefail` — the options `rename-notebook.sh`
# actually runs under. It is first because it is the case that did not exist when this suite passed 48 checks
# over a library that could not survive its own population, and both of #65's fatal defects die in it. A suite
# that only ever meets its own fixtures is a test of the fixtures.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
ROOT=$(cd "$HERE/../../.." && pwd -P)
LIB="$ROOT/claude/lib/session-status.sh"
WAKE="$ROOT/claude/bin/wake-session.sh"
RENAME="$ROOT/claude/bin/rename-notebook.sh"
HOOK="$ROOT/claude/hooks/notebook-name-sync.sh"
TMP=$(mktemp -d -t status-dual-read) || exit 1
trap 'rm -rf "$TMP"' EXIT
NB="$TMP/notebook/2026-09"
mkdir -p "$NB"
n=0; fails=0; skips=0
eq() { n=$((n + 1)); if [ "$2" = "$3" ]; then printf 'PASS  %-58s %s\n' "$1" "$2"; else fails=$((fails + 1)); printf 'FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fi; }
# `pass` and `fail` exist because two cases cannot be written as an `eq`, and because their ABSENCE cost this
# suite its most important assertion: the sibling suites define them, this one did not, and two `pass`/`fail`
# calls added in the fix-forward were silent `command not found` lines. Under `set -u` a missing command does
# not stop a script, so the run still reported "0 failed" while the headline case — an unrelated record must
# not poison the renamer — could not fail in either direction. A helper that does not exist is worse than an
# assertion that is wrong, because nothing in the output says so.
pass() { n=$((n + 1)); printf 'PASS  %-58s %s\n' "$1" "${2:-yes}"; }
fail() { n=$((n + 1)); fails=$((fails + 1)); printf 'FAIL  %-58s %s\n' "$1" "${2:-}"; }

# entry <file> <session name> <frontmatter lines…>: the keys are passed verbatim so a case can write one key,
# both keys, or neither, and nothing here normalises them.
entry() {
  f="$NB/$1.md"; shift
  sess="$1"; shift
  {
    printf -- '---\n'
    printf 'title: %s\n' "test entry"
    printf 'session: "%s"\n' "$sess"
    for line in "$@"; do printf '%s\n' "$line"; done
    printf 'reports-to: "[C0-CC] battery line top"\n'
    printf -- '---\n\n[test artifact — safe to delete]\n'
  } > "$f"
  printf '%s' "$f"
}

echo "=== 1. THE REAL POPULATION (the notebook and the archive), under the callers own shell options"
# THIS IS THE FIRST CASE ON PURPOSE. It is the case that did not exist when this suite passed 48 checks over a
# library that could not survive its own notebook — #65's review found two FATAL defects that both die here in
# the first second: a bare `status: draft` on seven live entries read as a session claim (which refused the
# renamer for every session), and a `grep` that exits 1 on a missing key aborting a `set -euo pipefail` caller
# mid-loop. Fixtures cannot find either. The population can, and it costs one pass over it (517 files on 2026-09-27, all in the notebook then; the notebook and the archive since the move of 2026-09-29).
#
# READ-ONLY, and it asserts two things: that the run SURVIVES — a non-zero exit means some real entry aborts a
# caller — and that no entry reads as a `conflict`, because one conflict refuses the renamer for everybody.
strict_state() {  # the library under the callers own options
  bash -euo pipefail -c '. "$1" && session_status_of "$2" && printf "%s" "$sess_state"' _ "$LIB" "$1" 2>/dev/null
}
# THE POPULATION, since 2026-09-29, when ended entries began to move from the notebook to the archive's notebook (the notebook alone fell from 517 entries to 71, below this section's bound). Two readers matter, so the section reads the UNION of what each reads (review 1 of #90):
#   * the renamer, `rename-notebook.sh`, the strict caller this section guards: every file under the notebook, at any depth, with a `session:` key (its own `grep -rl`, run here with /usr/bin/grep so the shell's grep wrapper cannot change the answer);
#   * the wake: `<root>/YYYY-MM/Agent session *.md` under both roots, through `claude/lib/notebook-roots.sh`, whose functions also give the two default paths.
# The list goes to the strict shell on stdin, never as arguments, so a growing archive cannot hit the argument limit.
ROOTS_LIB="$ROOT/claude/lib/notebook-roots.sh"
AGENTS="$HOME/obsidian/00-09 System/03 Agents"
roots_ok=1
if [ -r "$ROOTS_LIB" ] && bash -n "$ROOTS_LIB" 2>/dev/null; then
  # shellcheck source=../../lib/notebook-roots.sh
  . "$ROOTS_LIB" || roots_ok=0
  for fn in notebook_dir_for archive_dir_for entries_in_root notebook_entry_files_of; do command -v "$fn" >/dev/null 2>&1 || roots_ok=0; done
else
  roots_ok=0
fi
if [ "$roots_ok" = 0 ]; then
  fail "the roots library loads and defines what it promises" "$ROOTS_LIB is missing, does not parse, or lacks a function; section 1 cannot choose its population"
  REAL_NB=""; REAL_ARCH=""
else
  REAL_NB=$(notebook_dir_for "$AGENTS" "" 0 1)
  REAL_ARCH=$(archive_dir_for "$AGENTS" "" 0)
fi
if [ "$roots_ok" = 1 ] && { [ -d "$REAL_NB" ] || [ -d "$REAL_ARCH" ]; }; then
  { [ -d "$REAL_NB" ] && /usr/bin/grep -rl -E "^[[:space:]]*session[[:space:]]*:" "$REAL_NB" 2>/dev/null
    notebook_entry_files_of "$REAL_NB" 1 "$REAL_ARCH" 1
  } | sort -u > "$TMP/population"
  nb_n=$(/usr/bin/grep -c -F "$REAL_NB/" "$TMP/population" || true)
  arch_n=$(/usr/bin/grep -c -F "$REAL_ARCH/" "$TMP/population" || true)
  printf '      population: %s files in the notebook (the renamer reads these), %s in the archive\n' "$nb_n" "$arch_n"
  # READ-ONLY, in one strict shell, the options the renamer runs under. What is asserted is that the run SURVIVES (a non-zero exit means some real entry aborts a caller) and that no entry reads as a conflict, because a single conflict refuses the renamer for every session.
  real_out=$(bash -euo pipefail -c '
    . "$1" || exit 9
    while IFS= read -r f; do session_status_of "$f"; printf "%s\n" "$sess_state"; done
  ' _ "$LIB" < "$TMP/population" 2>/dev/null)
  real_rc=$?
  eq "the notebook and the archive do not abort a strict caller" "$real_rc" 0
  # THE POPULATION MUST NOT BE EMPTY, or the conflict check below passes by reading nothing: `grep -c` over one empty line is 0, which is indistinguishable from a clean population. Counts are asserted here, and only here, because zero entries means this section measured NOTHING while claiming both fatal defects die in it. The total must be real, and so must the notebook's own part, which is what the renamer reads.
  live_n=$(printf '%s\n' "$real_out" | grep -c . || true)
  if [ "$live_n" -gt 100 ]; then pass "the population is real ($live_n entries read)"
  else fail "the population is real" "only $live_n entries were read; this section proves nothing at that size"; fi
  if [ "$nb_n" -gt 0 ]; then pass "the notebook itself is read ($nb_n files)"
  else fail "the notebook itself is read" "no file under $REAL_NB was read; the renamer's own population went untested"; fi
  eq "no entry reads as a conflict" "$(printf '%s\n' "$real_out" | grep -c '^conflict$' || true)" 0
  printf '      census: %s entries — %s\n' \
    "$live_n" \
    "$(printf '%s\n' "$real_out" | sort | uniq -c | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g')"
elif [ "$roots_ok" = 1 ]; then
  # COUNTED, so a machine without the vault cannot run this suite green while missing the only section that meets the real population. A skip that nothing counts is a hole with a label on it.
  n=$((n + 1)); skips=$((skips + 1))
  printf 'SKIP  %-58s neither root exists (%s, %s)\n' "the real population case" "$REAL_NB" "$REAL_ARCH"
fi

echo "=== 2. the library: every key in every state, and both keys together"
state_of() { bash -c '. "$1" && session_status_of "$2" && printf "%s" "$sess_state"' _ "$LIB" "$1"; }
detail_of() { bash -c '. "$1" && session_status_of "$2" && printf "%s" "$sess_detail"' _ "$LIB" "$1"; }

E_OLD_RUN=$(entry old-running   "[L0-CC] old running"   'session-status: running')
E_OLD_END=$(entry old-ended     "[L0-CC] old ended"     'session-status: ended')
E_NEW_RUN=$(entry new-running   "[L0-CC] new running"   'status: draft/running')
E_NEW_END=$(entry new-ended     "[L0-CC] new ended"     'status: archived/ended')
E_BOTH_RUN=$(entry both-running "[L0-CC] both running"  'session-status: running' 'status: draft/running')
E_BOTH_END=$(entry both-ended   "[L0-CC] both ended"    'session-status: ended'   'status: archived/ended')
E_CONFLICT=$(entry disagree     "[L0-CC] disagree"      'session-status: running' 'status: archived/ended')
E_CONFLICT2=$(entry disagree2   "[L0-CC] disagree two"  'session-status: ended'   'status: draft/running')
E_NEITHER=$(entry neither       "[L0-CC] neither")
E_OTHER_OLD=$(entry other-old   "[L0-CC] other old"     'session-status: paused')
E_OTHER_NEW=$(entry other-new   "[L0-CC] other new"     'status: stable/verified')
E_QUOTED=$(entry quoted         "[L0-CC] quoted"        'session-status: "running"')
E_QUOTED_NEW=$(entry quotednew  "[L0-CC] quoted new"    "status: 'draft/running'")

# THE SHAPES THE REVIEW FOUND, every one of which the two readers disagreed about because no well-formed
# fixture had them. They are first in the file now, so a reader meets the hard cases before the easy ones.
E_LIVE_DRAFT=$(entry live-draft   "[L0-CC] the live case"  'session-status: ended' 'status: draft')
E_QUOTED_SP="$NB/quoted-space.md"
printf -- '---\nsession: "[L0-CC] quoted with a trailing space"\nsession-status: "running"  \nreports-to: "[C0-CC] top"\n---\n' > "$E_QUOTED_SP"
E_DUP=$(entry duplicate-key "[L0-CC] duplicate key" 'session-status: ended' 'session-status: running')
E_BODY_KEY="$NB/body-key.md"
printf -- '---\nsession: "[L0-CC] key in the body"\nsession-status: running\n---\n\nsome prose\n\n---\n\nstatus: archived/ended\n' > "$E_BODY_KEY"
E_NO_FM="$NB/no-frontmatter.md"
printf -- 'not frontmatter\n\n---\nsession: "[L0-CC] no frontmatter"\nstatus: draft/running\n---\n' > "$E_NO_FM"
E_COMMENT=$(entry commented "[L0-CC] commented" 'status: draft/running # while it runs')
E_STABLE=$(entry stable "[L0-CC] a stable note" 'status: stable/verified')
# THE COMBINATIONS, which is where the divergences hid. Six inputs disagreed between the library and the awk
# after the fix-forward added comment-stripping to both in different positions, and not one of them was
# reachable from the fixtures then present: every quoted fixture was uncommented and the commented one was
# unquoted. A cross-product of two features is a different test from each feature alone.
E_Q_COMMENT=$(entry quoted-comment     "[L0-CC] quoted and commented"   'status: "draft/running" # while it runs')
E_Q_COMMENT2=$(entry quoted-comment2   "[L0-CC] quoted and commented 2" "session-status: 'running' # note")
E_HASH_IN=$(entry hash-inside          "[L0-CC] hash inside the quotes" 'status: "draft/running #x"')
E_CR_IN="$NB/cr-inside.md"
printf -- '---\nsession: "[L0-CC] a CR inside the value"\nstatus: draft\r/running\n---\n' > "$E_CR_IN"
E_MALFORMED_PLUS=$(entry malformed-plus "[L0-CC] malformed beside a claim" 'session-status: paused' 'status: draft/running')
E_NEWVAL_OLDKEY=$(entry newval-oldkey "[L0-CC] new value on the old key" 'session-status: draft/running')

eq "old key alone, running"        "$(state_of "$E_OLD_RUN")"    running
eq "old key alone, ended"          "$(state_of "$E_OLD_END")"    ended
eq "new key alone, running"        "$(state_of "$E_NEW_RUN")"    running
eq "new key alone, ended"          "$(state_of "$E_NEW_END")"    ended
eq "both keys agreeing, running"   "$(state_of "$E_BOTH_RUN")"   running
eq "both keys agreeing, ended"     "$(state_of "$E_BOTH_END")"   ended
eq "both keys disagreeing"         "$(state_of "$E_CONFLICT")"   conflict
eq "both keys disagreeing, other way round" "$(state_of "$E_CONFLICT2")" conflict
eq "neither key present"           "$(state_of "$E_NEITHER")"    absent
eq "old key carrying something else" "$(state_of "$E_OTHER_OLD")" other
# CHANGED BY THE REVIEW, not by a whim: `status: stable/verified` is the vault's own note status and is NOT a
# session claim, so it reads as `absent` rather than `other`. Under the rejected rule it was `other`, which is
# what made seven live entries conflict. `other` now has ONE source, our own key carrying something malformed.
eq "a stable path on the shared key is not a claim" "$(state_of "$E_OTHER_NEW")" absent
eq "a quoted old value"            "$(state_of "$E_QUOTED")"     running
eq "a single-quoted new value"     "$(state_of "$E_QUOTED_NEW")" running
# THE CASE THAT WAS A FATAL DEFECT, and the reason this suite exists at all now. `status` is the vault's
# UNIVERSAL note-status key: seven live entries carry `session-status: ended` beside `status: draft`, the
# vault's own note status, which says nothing about a session. Reading that as a session claim made every one a
# `conflict`, and `rename-notebook.sh` refuses on the first conflict it meets — so the renamer was dead for
# EVERY session until somebody hand-edited seven historical records. The old key decides here; the shared key
# is not making a claim at all.
eq "the live case: session-status ended beside status draft" "$(state_of "$E_LIVE_DRAFT")" ended
eq "a stable note status is not a session claim"             "$(state_of "$E_STABLE")"     absent
# BE LIBERAL ON OUR OWN KEY. CLAUDE.md now tells every session to write both keys during the window, so a
# session putting the NEW value on the OLD key is a plausible mistake with an unrecoverable outcome if it reads
# as a conflict. Both values are accepted on `session-status`, which is ours alone.
eq "the new value on the old key is still a live claim"      "$(state_of "$E_NEWVAL_OLDKEY")" running
# THE FOUR SHAPES WHERE THE TWO READERS DISAGREED, each fixed in the library rather than in the awk:
eq "a quoted value with a trailing space"        "$(state_of "$E_QUOTED_SP")"  running
eq "a duplicated key: the LAST one wins"         "$(state_of "$E_DUP")"        running
eq "a key after a --- in the BODY is not read"   "$(state_of "$E_BODY_KEY")"   running
eq "a file whose first line is not a fence"      "$(state_of "$E_NO_FM")"      absent
eq "a trailing YAML comment is not part of the value" "$(state_of "$E_COMMENT")" running
eq "a QUOTED value with a comment"                    "$(state_of "$E_Q_COMMENT")"   running
eq "single-quoted with a comment, on our own key"     "$(state_of "$E_Q_COMMENT2")"  running
eq "a hash INSIDE the quotes is part of the value"    "$(state_of "$E_HASH_IN")"     absent
eq "a carriage return inside the value"               "$(state_of "$E_CR_IN")"       running
# A MALFORMED VALUE ON OUR KEY IS NOT A CLAIM, so it cannot conflict with a real one: the real claim wins and
# the malformed value is named. The first version read this as `conflict`, which refused the renamer for that
# session over a value that claims nothing — and contradicted the library's own state table.
eq "malformed on our key beside a real claim"          "$(state_of "$E_MALFORMED_PLUS")" running
case "$(detail_of "$E_MALFORMED_PLUS")" in
  *"'paused'"*) eq "and the malformed value is still named" yes yes ;;
  *) eq "and the malformed value is still named" "no: $(detail_of "$E_MALFORMED_PLUS")" yes ;;
esac

# A CONFLICT MUST NAME BOTH VALUES, because a refusal that says only "they disagree" leaves a human opening
# the file to find out which key is stale — and which is stale is the whole question during the window.
case "$(detail_of "$E_CONFLICT")" in
  *"'running'"*"'archived/ended'"*) eq "the conflict detail names both values" yes yes ;;
  *) eq "the conflict detail names both values" "no: $(detail_of "$E_CONFLICT")" yes ;;
esac
# AND THE DETAIL IS EMPTY FOR IT, because nothing is wrong: a note carrying the vault's own status is ordinary,
# and a sentence about it would be noise in a refusal. The detail belongs to `conflict` and to a malformed
# value on OUR key — this case asserts the silence rather than a sentence.
eq "and nothing is said about it, because nothing is wrong" "$(detail_of "$E_OTHER_NEW")" ""
case "$(detail_of "$E_OTHER_OLD")" in
  *"paused"*) eq "a malformed value on our own key IS named in the detail" yes yes ;;
  *) eq "a malformed value on our own key IS named in the detail" "no: $(detail_of "$E_OTHER_OLD")" yes ;;
esac
eq "session_is_running agrees on the new key"  "$(bash -c '. "$1" && session_is_running "$2" && echo yes || echo no' _ "$LIB" "$E_NEW_RUN")" yes
eq "session_is_running refuses a conflict"     "$(bash -c '. "$1" && session_is_running "$2" && echo yes || echo no' _ "$LIB" "$E_CONFLICT")" no
eq "session_is_running refuses an absent key"  "$(bash -c '. "$1" && session_is_running "$2" && echo yes || echo no' _ "$LIB" "$E_NEITHER")" no

echo
echo
echo "=== 2b. the fixtures too, under those same options"
# `rename-notebook.sh` runs under `set -euo pipefail`. The library's key reader used to end in a `grep` that
# exits 1 when a key is absent, so under `pipefail` the assignment failed and under `set -e` the CALLER died
# mid-loop with exit 1 — on every entry carrying only one key, which is almost every entry in the notebook.
# Nothing in the first version of this suite ran either script under those options, which is exactly why 48
# checks passed over a script that could not survive its own notebook. These cases run the library the way its
# caller does, and one of them walks the REAL notebook, which is the population that broke it.
for pair in "$E_OLD_RUN:running" "$E_NEW_RUN:running" "$E_NEITHER:absent" "$E_LIVE_DRAFT:ended" "$E_CONFLICT:conflict"; do
  f=${pair%:*}; want=${pair##*:}
  eq "strict: $(basename "$f")" "$(strict_state "$f")" "$want"
done
echo "=== 3. wake-session: its own awk index, run directly, gives the same word"
# THE PROGRAM IS EXTRACTED AND RUN, rather than the script driven. `wake-session.sh` builds this index only on
# a path that first resolves a live session, so driving the script would need a live fixture — and the thing
# under test is not the script, it is the COPY OF THE RULE inside its awk program. So the program is pulled out
# of the file between its own delimiters and run over the same fixtures the library just read. If someone edits
# the awk and not the library, or the other way round, these five cases and the twenty above disagree.
# EXTRACTED WITH `sed`, BETWEEN THE ASSIGNMENT AND ITS CLOSING QUOTE. An `awk` extractor was tried first and
# silently produced a program that worked for the simple shapes and returned nothing for the interesting ones,
# because the `\x27` escape it used for a quote character is not portable and BSD awk read it literally. A
# harness that half-works is worse than one that fails: six cases passed and seven reported the script
# disagreeing with the library, which was a lie about the script.
AWK_PROG="$TMP/index.awk"
sed -n "/^index_awk='/,/^'\$/p" "$WAKE" | sed '1d;$d' > "$AWK_PROG"
eq "the awk program was extracted from the script" "$([ -s "$AWK_PROG" ] && echo yes || echo no)" yes
# NOT ONE LITERAL APOSTROPHE INSIDE THE PROGRAM. It lives in a single-quoted shell string, so one apostrophe in
# a comment ends the string and the shell parses awk source as commands — a syntax error at a line nobody was
# editing. It happened TWICE in one evening, both times inside a comment explaining something careful, so this
# is a case rather than a warning in a header. awk writes a literal quote as \047.
apos_count=$(grep -c "'" "$AWK_PROG" 2>/dev/null || true)
eq "no literal apostrophe inside the awk program" "${apos_count:-unknown}" 0
index_word() {  # $1 = a fixture path; prints field 4 of the index row
  awk -v key=reports-to -f "$AWK_PROG" "$1" 2>/dev/null | head -n 1 | cut -f 4
}
eq "awk: old key alone, running"      "$(index_word "$E_OLD_RUN")"    running
eq "awk: old key alone, ended"        "$(index_word "$E_OLD_END")"    ended
eq "awk: new key alone, running"      "$(index_word "$E_NEW_RUN")"    running
eq "awk: new key alone, ended"        "$(index_word "$E_NEW_END")"    ended
eq "awk: both agreeing"               "$(index_word "$E_BOTH_RUN")"   running
eq "awk: both disagreeing"            "$(index_word "$E_CONFLICT")"   conflict
eq "awk: the other disagreement"      "$(index_word "$E_CONFLICT2")"  conflict
eq "awk: neither key"                 "$(index_word "$E_NEITHER")"    absent
eq "awk: an unnamed old value"        "$(index_word "$E_OTHER_OLD")"  other
eq "awk: a stable path on the shared key is not a claim" "$(index_word "$E_OTHER_NEW")" absent
eq "awk: a quoted old value"          "$(index_word "$E_QUOTED")"     running
eq "awk: a single-quoted new value"   "$(index_word "$E_QUOTED_NEW")" running
eq "awk: a quoted value with a comment"        "$(index_word "$E_Q_COMMENT")"  running
eq "awk: single-quoted with a comment"         "$(index_word "$E_Q_COMMENT2")" running
eq "awk: a hash inside the quotes"             "$(index_word "$E_HASH_IN")"    absent
eq "awk: a carriage return inside the value"   "$(index_word "$E_CR_IN")"      running
eq "awk: malformed on our key beside a claim"  "$(index_word "$E_MALFORMED_PLUS")" running
# AND THE TWO ROADS MUST AGREE ENTRY BY ENTRY, which is the assertion that actually guards the duplication:
# the library and the awk are two copies of one rule, and this compares them on every fixture rather than
# trusting that both were edited.
disagreements=0
# EVERY FIXTURE, THE MALFORMED ONES ESPECIALLY. The review's verdict on this assertion was that it is the right
# one and proved nothing, because all thirteen fixtures were well-formed — and all four disagreements it found
# by hand were shapes no fixture had. Those shapes are now fixtures, and they are in this loop.
for f in "$E_OLD_RUN" "$E_OLD_END" "$E_NEW_RUN" "$E_NEW_END" "$E_BOTH_RUN" "$E_BOTH_END" "$E_CONFLICT" "$E_CONFLICT2" \
         "$E_NEITHER" "$E_OTHER_OLD" "$E_OTHER_NEW" "$E_QUOTED" "$E_QUOTED_NEW" \
         "$E_LIVE_DRAFT" "$E_QUOTED_SP" "$E_DUP" "$E_BODY_KEY" "$E_NO_FM" "$E_COMMENT" "$E_STABLE" "$E_NEWVAL_OLDKEY" \
         "$E_Q_COMMENT" "$E_Q_COMMENT2" "$E_HASH_IN" "$E_CR_IN" "$E_MALFORMED_PLUS"; do
  a=$(state_of "$f"); b=$(index_word "$f")
  # An entry the INDEX does not carry at all — no `session:` key inside its frontmatter, which is true of the
  # no-frontmatter fixture — yields an empty word rather than `absent`. That is the same answer in the index's
  # own terms: it only lists entries that name a session. Read as `absent` for the comparison, and said here
  # rather than hidden in a `||`.
  [ -n "$b" ] || b=absent
  if [ "$a" != "$b" ]; then
    disagreements=$((disagreements + 1))
    printf '      %s: library says %s, awk says %s\n' "$(basename "$f")" "$a" "$b"
  fi
done
eq "the library and the awk agree on every fixture" "$disagreements" 0

echo
echo "=== 4. rename-notebook, at source level only: it reads the shared rule, it does not restate it"
# WHAT CANNOT BE TESTED HERE, said rather than skipped quietly: this script resolves the session NAME from
# `~/.claude/sessions/<pid>.json` through a `SESSIONS_DIR` that is a plain variable, not a flag, so an
# end-to-end run needs either a live session or a `--sessions-dir` test flag the script does not have. Adding
# one is a change to a shipped script for a test's sake and belongs to its own package, not to a dual-read fix
# that has to be mergeable the moment Nelson gives a word. So what is asserted here is the thing that would
# actually break: that the script gets its answer from `claude/lib/session-status.sh` and holds no second copy
# of the rule. The rule's behaviour is proven twenty times in section 1.
src_has() {  # src_has <label> <pattern> <want yes|no>
  if grep -qE "$2" "$RENAME"; then got=yes; else got=no; fi
  eq "$1" "$got" "$3"
}
# EVERY LABEL HERE SAYS "the source", because that is all a grep can prove — the review was right that "it
# refuses a conflict" claimed behaviour a string match cannot show. Section 4b drives the refusal for real; these
# cases only guard against the rule being re-derived in this file instead of read from the library.
src_has "the source sources the shared rule"         'session-status\.sh' yes
src_has "the source calls the shared reader"         'session_status_of' yes
src_has "the source carries the conflict refusal"    'disagrees with itself' yes
src_has "the source passes the shared detail on"     'sess_detail' yes
src_has "the source no longer tests the old key by hand" 'fm_value .* session-status' no
# The three guards #61 ruled for a sourced library, each by name: readable, parses, defines what is wanted.
src_has "the source refuses an unreadable rule file" 'is missing or unreadable at' yes
src_has "the source refuses one that does not parse" 'does not parse' yes
src_has "the source refuses one that defines nothing" 'defined no reader' yes

echo "=== 5. the hook: it reads the notebook for real, and NEVER fails a turn"
# THE FIRST VERSION OF THIS SECTION COULD NOT FAIL, and the review said so plainly. It passed the fixture as
# `NOTEBOOK_DIR`, which the hook does not read — it reads `NOTEBOOK_NAME_SYNC_DIR` — and it used a session id
# that matches no registry row, so the hook exited before it read any notebook at all. Four cases, one
# assertion, and none of it about the status keys.
#
# What it takes to drive the real path: a session id that IS in the registry (this session's own, read from
# `~/.claude/sessions`, never invented), the two real override variables, and a fake rename script so nothing
# is ever renamed. `NOTEBOOK_NAME_SYNC_SCRIPT` pointing at `/usr/bin/true` means "a rename would have been
# attempted here" without one happening.
MY_SID=$(bash -c '
  for f in "$HOME"/.claude/sessions/*.json; do
    [ -f "$f" ] || continue
    sid=$(sed -n '"'"'s/.*"sessionId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'"'"' "$f" | head -n 1)
    nm=$(sed -n '"'"'s/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'"'"' "$f" | head -n 1)
    if [ -n "$sid" ] && [ -n "$nm" ]; then printf "%s\t%s" "$sid" "$nm"; exit 0; fi
  done')
HOOK_SID=$(printf '%s' "$MY_SID" | cut -f1)
HOOK_NAME=$(printf '%s' "$MY_SID" | cut -f2)
hook_run() {  # hook_run <status line for the entry> [extra env assignments are not needed]
  d="$TMP/hookreal"; rm -rf "$d"; mkdir -p "$d/2026-09"
  {
    printf -- '---\ntitle: entry\nsession: "%s"\n' "$HOOK_NAME"
    [ -z "$1" ] || printf '%s\n' "$1"
    printf 'reports-to: "[C0-CC] top"\n---\n'
  } > "$d/2026-09/Agent session 2026-09-27T0101.md"
  # NOT CALLED THROUGH `$( )`. A function whose output is captured runs in a SUBSHELL, so `hook_rc` set inside
  # it never comes back — the same trap that cost the notifier its duplicate-name clause earlier today, and
  # this is the fourth time in one session. The output goes to a file and both facts are read from the caller.
  printf '%s' "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$HOOK_SID\"}" \
    | NOTEBOOK_NAME_SYNC_DIR="$d" NOTEBOOK_NAME_SYNC_SCRIPT=/usr/bin/true "$HOOK" > "$TMP/hook.out" 2>&1
  hook_rc=$?
  hook_out=$(cat "$TMP/hook.out" 2>/dev/null || true)
}
if [ -z "$HOOK_SID" ]; then
  printf 'SKIP  no readable session registry, so the hook cases did not run (they need a real id)\n'
else
  # A RUNNING ENTRY UNDER EITHER KEY means nothing has drifted, so the hook says nothing and exits 0. An entry
  # that is NOT running means a rename is attempted — with the fake script, that is silent too. What separates
  # the cases is the CONFLICT, which must produce the warning on stderr, and every case must exit 0.
  for pair in "session-status: running:0" "status: draft/running:0" "session-status: ended:0" "status: archived/ended:0" ":0"; do
    line=${pair%:*}; want=${pair##*:}
    hook_run "$line"
    eq "the hook exits 0 on: ${line:-(no key)}" "$hook_rc" "$want"
  done
  hook_run "session-status: running
status: archived/ended"
  eq "a conflicting entry still exits 0"  "$hook_rc" 0
  case "$hook_out" in
    *"disagrees with itself"*) eq "and the conflict is said out loud, on stderr" yes yes ;;
    *) eq "and the conflict is said out loud, on stderr" "no: $(printf '%s' "$hook_out" | tr '\n' ' ' | cut -c1-110)" yes ;;
  esac
  # THE LIBRARY MISSING, UNPARSEABLE, OR DEFINING NOTHING. The hook must exit 0 and say so — it never refuses,
  # because a missed rename is a name out of step in a record while a refusal is Nelson's session unable to
  # think. Driven by copying the hook to a directory whose `../lib` holds each broken shape in turn.
  for shape in missing unparseable empty; do
    d="$TMP/broken-$shape"; rm -rf "$d"; mkdir -p "$d/hooks" "$d/lib" "$d/nb/2026-09"
    cp "$HOOK" "$d/hooks/notebook-name-sync.sh"
    case "$shape" in
      unparseable) printf 'session_status_of() {\n  if [\n}\n' > "$d/lib/session-status.sh" ;;
      empty)       printf '# defines nothing at all\n' > "$d/lib/session-status.sh" ;;
    esac
    printf -- '---\nsession: "%s"\nstatus: draft/running\n---\n' "$HOOK_NAME" > "$d/nb/2026-09/Agent session 2026-09-27T0101.md"
    printf '%s' "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$HOOK_SID\"}" \
      | NOTEBOOK_NAME_SYNC_DIR="$d/nb" NOTEBOOK_NAME_SYNC_SCRIPT=/usr/bin/true "$d/hooks/notebook-name-sync.sh" >/dev/null 2>&1
    eq "the hook exits 0 with a $shape status rule" "$?" 0
  done
  # A NOTEBOOK DIRECTORY THAT IS NOT THERE.
  printf '%s' "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$HOOK_SID\"}" \
    | NOTEBOOK_NAME_SYNC_DIR="$TMP/there-is-no-notebook" NOTEBOOK_NAME_SYNC_SCRIPT=/usr/bin/true "$HOOK" >/dev/null 2>&1
  eq "the hook exits 0 with no notebook directory" "$?" 0
fi

echo
echo "=== 5b. rename-notebook: the refusal is REACHED, not merely present in the source"
# D7: the first version of this section grepped the script for its own message strings, which proves a string
# exists and nothing about whether the branch runs. This drives the script instead. It cannot be driven
# end-to-end — the display name comes from `~/.claude/sessions` through a plain variable, not a flag, which is
# issue #66 — but the CONFLICT REFUSAL can be reached with a notebook whose matching entry disagrees with
# itself, because the name is resolved from the registry row of a real session id.
if [ -z "$HOOK_SID" ]; then
  printf 'SKIP  no readable session registry, so the refusal case did not run\n'
else
  d="$TMP/renreal"; rm -rf "$d"; mkdir -p "$d/2026-09"
  {
    printf -- '---\nsession: "%s"\n' "$HOOK_NAME"
    printf 'session-status: running\nstatus: archived/ended\n'
    printf 'reports-to: "[C0-CC] top"\n---\n'
  } > "$d/2026-09/Agent session 2026-09-27T0101.md"
  out=$("$RENAME" --session "$HOOK_SID" --notebook-dir "$d" --dry-run 2>&1); rc=$?
  eq "rename refuses a conflicting entry of its own, exit 2" "$rc" 2
  case "$out" in
    *"disagrees with itself"*"'running'"*"'archived/ended'"*) eq "and the refusal names both values" yes yes ;;
    *) eq "and the refusal names both values" "no: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-130)" yes ;;
  esac
  # AND AN UNRELATED RECORD MUST NOT POISON IT. This is D1's second half: the conflict test now runs only for an
  # entry whose name matches, so a disagreeing entry belonging to somebody else is skipped, not refused.
  d2="$TMP/renother"; rm -rf "$d2"; mkdir -p "$d2/2026-09"
  printf -- '---\nsession: "[L0-CC] somebody else entirely"\nsession-status: running\nstatus: archived/ended\n---\n' > "$d2/2026-09/Agent session 2026-09-01T0101.md"
  printf -- '---\nsession: "%s"\nstatus: draft/running\nreports-to: "[C0-CC] top"\n---\n' "$HOOK_NAME" > "$d2/2026-09/Agent session 2026-09-27T0102.md"
  out=$("$RENAME" --session "$HOOK_SID" --notebook-dir "$d2" --dry-run 2>&1); rc=$?
  case "$rc" in
    2) fail "another session's conflicting entry does not refuse ours" "it refused: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-130)" ;;
    *) pass "another session's conflicting entry does not refuse ours" ;;
  esac
fi

echo "=== 6. nothing in this repository writes the old key any more"
# The ruling says what is WRITTEN from now carries `status: draft/running` and never `session-status`. Nothing
# in this repo writes either key into a note today, so what this guards is that it stays that way: a writer
# added later that emits the old key would be building work for the same migration twice.
# D6: THE FILTER WAS DEAD AND THE SEARCH MISSED THIS REPO'S OWN IDIOM. `grep -v '^\s*#'` removed nothing,
# because `grep -rn` prefixes every line with `path:lineno:` so `^` never sees the `#` (and `\s` is not BRE
# anyway) — measured, 15 hits before and after. Worse, a heredoc writer is invisible to a line-based search:
# `cat <<'EOF' >> "$f"` on one line and `session-status: running` on the next share no line, and the atomic
# heredoc append is the idiom this repo's CLAUDE.md MANDATES for shared files. So the question is asked the
# other way round: find every line that writes the old key's TEXT, whatever the mechanism, by looking for the
# key in a context that is not a comment and not a read. Comments are dropped by looking after the line number
# prefix, and the tests are excluded by path because their fixtures write it on purpose.
#
# AND `\|\|` IS OUT OF THE EXCLUSION LIST. It dropped EVERY line containing `||`, so a real writer written as
# `printf 'session-status: running\n' >> "$f" || die ...` was silently not found — and `|| die` is how half the
# scripts in this repo are written. An exclusion list is exactly where a filter quietly becomes a blindfold, so
# every term in it has to name the KIND of line it removes, never a character that appears in the lines it was
# meant to catch.
writers=$(grep -rn "session-status" "$ROOT/claude" --include='*.sh' 2>/dev/null \
  | grep -v '/tests/' \
  | sed -E 's/^[^:]+:[0-9]+://' \
  | grep -vE '^[[:space:]]*#' \
  | grep -E "session-status[[:space:]]*:" \
  | grep -vE 'grep|match\(|session_status_value|case |printf .notebook-name-sync' || true)
# COUNTED, the way it was before the fix-forward replaced it with an inert `pass`. The count is the assertion;
# the first two offenders print beside it so a failure says what to look at.
eq "no script writes session-status into a note" "$(printf '%s' "$writers" | grep -c . || true)" 0
[ -z "$writers" ] || printf '      offenders: %s\n' "$(printf '%s' "$writers" | head -n 2 | tr '\n' ' ')"
# AND THE HEREDOC SHAPE IS PROVEN TO BE CATCHABLE, on a fixture, so the search above is not trusted blind: a
# file that writes the old key through a heredoc must be FOUND by it. A test of the test, because the review
# found this exact false negative.
FAKEW="$TMP/fake-writer.sh"
printf '#!/usr/bin/env bash\ncat <<EOF >> "$1"\nsession-status: running\nEOF\n' > "$FAKEW"
found=$(grep -rn "session-status" "$FAKEW" 2>/dev/null | sed -E 's/^[^:]+:[0-9]+://' | grep -cE "session-status[[:space:]]*:" || true)
eq "a heredoc writer would be caught by that search" "$found" 1
# And the state table itself must still be readable as the authority: one file, both keys, the expiry date.
# NOT A COUNT. The first version of these two asserted how MANY times each string appears, which is a number
# that changes whenever a sentence is rewritten and says nothing about correctness — a test that fails on an
# edit to a comment trains people to stop reading failures.
eq "the library names the expiry date"  "$(grep -q '2026-10-04' "$LIB" && echo yes || echo no)" yes
eq "the library still knows the old key" "$(grep -q 'session-status' "$LIB" && echo yes || echo no)" yes
eq "the library knows the new values"    "$(grep -q 'draft/running' "$LIB" && grep -q 'archived/ended' "$LIB" && echo yes || echo no)" yes

printf '\n%s checks, %s failed, %s skipped\n' "$n" "$fails" "$skips"
[ "$fails" = 0 ] || exit 1
