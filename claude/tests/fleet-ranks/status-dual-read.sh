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
# IT RUNS UNATTENDED. Every case is a temp notebook this script writes; no fleet id, no live session, no
# `claude` command, and the two scripts are pointed at the temp notebook with their own test flags.
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
n=0; fails=0
eq() { n=$((n + 1)); if [ "$2" = "$3" ]; then printf 'PASS  %-58s %s\n' "$1" "$2"; else fails=$((fails + 1)); printf 'FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fi; }

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

echo "=== 1. the library: every key in every state, and both keys together"
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
eq "new key carrying a stable path" "$(state_of "$E_OTHER_NEW")" other
eq "a quoted old value"            "$(state_of "$E_QUOTED")"     running
eq "a single-quoted new value"     "$(state_of "$E_QUOTED_NEW")" running
# A CONFLICT MUST NAME BOTH VALUES, because a refusal that says only "they disagree" leaves a human opening
# the file to find out which key is stale — and which is stale is the whole question during the window.
case "$(detail_of "$E_CONFLICT")" in
  *"'running'"*"'archived/ended'"*) eq "the conflict detail names both values" yes yes ;;
  *) eq "the conflict detail names both values" "no: $(detail_of "$E_CONFLICT")" yes ;;
esac
# `stable/*` is never a session status. The ruling says so in as many words, so `other` rather than running.
case "$(detail_of "$E_OTHER_NEW")" in
  *"stable/verified"*) eq "an unknown new value is named in the detail" yes yes ;;
  *) eq "an unknown new value is named in the detail" "no" yes ;;
esac
eq "session_is_running agrees on the new key"  "$(bash -c '. "$1" && session_is_running "$2" && echo yes || echo no' _ "$LIB" "$E_NEW_RUN")" yes
eq "session_is_running refuses a conflict"     "$(bash -c '. "$1" && session_is_running "$2" && echo yes || echo no' _ "$LIB" "$E_CONFLICT")" no
eq "session_is_running refuses an absent key"  "$(bash -c '. "$1" && session_is_running "$2" && echo yes || echo no' _ "$LIB" "$E_NEITHER")" no

echo
echo "=== 2. wake-session: its own awk index, run directly, gives the same word"
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
eq "awk: a stable path is not a session status" "$(index_word "$E_OTHER_NEW")" other
eq "awk: a quoted old value"          "$(index_word "$E_QUOTED")"     running
eq "awk: a single-quoted new value"   "$(index_word "$E_QUOTED_NEW")" running
# AND THE TWO ROADS MUST AGREE ENTRY BY ENTRY, which is the assertion that actually guards the duplication:
# the library and the awk are two copies of one rule, and this compares them on every fixture rather than
# trusting that both were edited.
disagreements=0
for f in "$E_OLD_RUN" "$E_OLD_END" "$E_NEW_RUN" "$E_NEW_END" "$E_BOTH_RUN" "$E_BOTH_END" "$E_CONFLICT" "$E_CONFLICT2" "$E_NEITHER" "$E_OTHER_OLD" "$E_OTHER_NEW" "$E_QUOTED" "$E_QUOTED_NEW"; do
  a=$(state_of "$f"); b=$(index_word "$f")
  if [ "$a" != "$b" ]; then
    disagreements=$((disagreements + 1))
    printf '      %s: library says %s, awk says %s\n' "$(basename "$f")" "$a" "$b"
  fi
done
eq "the library and the awk agree on every fixture" "$disagreements" 0

echo
echo "=== 3. rename-notebook: it reads the shared rule rather than carrying its own"
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
src_has "it sources the shared rule"                 'session-status\.sh' yes
src_has "it calls the shared reader"                 'session_status_of' yes
src_has "it refuses a conflict"                      'disagrees with itself' yes
src_has "its refusal carries the shared detail"      'sess_detail' yes
src_has "it no longer tests the old key by hand"     'fm_value .* session-status' no
# The three guards #61 ruled for a sourced library, each by name: readable, parses, defines what is wanted.
src_has "it refuses an unreadable rule file"         'is missing or unreadable at' yes
src_has "it refuses a rule file that does not parse" 'does not parse' yes
src_has "it refuses a rule file that defines nothing" 'defined no reader' yes

echo "=== 4. the hook: either key stops it, and it NEVER fails a turn"
# The hook decides whether a rename is needed at all. It is given a payload for a session id that no registry
# row matches, so it exits early — what matters here is that every path exits 0, including the ones that read
# the notebook. A hook that refuses is worse than a name out of step.
for line in 'session-status: running' 'status: draft/running' 'session-status: running
status: archived/ended' ''; do
  d="$TMP/hook"; rm -rf "$d"; mkdir -p "$d/2026-09"
  {
    printf -- '---\nsession: "[L0-CC] hook target"\n'
    [ -z "$line" ] || printf '%s\n' "$line"
    printf -- '---\n'
  } > "$d/2026-09/Agent session 2026-09-27T0101.md"
  printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"11111111-2222-3333-4444-555555555555"}' \
    | NOTEBOOK_DIR="$d" "$HOOK" >/dev/null 2>&1
  rc=$?
  eq "the hook exits 0 on: ${line:-(no key)}" "$rc" 0
done

echo
echo "=== 5. nothing in this repository writes the old key any more"
# The ruling says what is WRITTEN from now carries `status: draft/running` and never `session-status`. Nothing
# in this repo writes either key into a note today, so what this guards is that it stays that way: a writer
# added later that emits the old key would be building work for the same migration twice.
writers=$(grep -rn "session-status[[:space:]]*:" "$ROOT/claude" --include='*.sh' 2>/dev/null \
  | grep -v '^\s*#' \
  | grep -E 'printf|echo|>>|cat <<|sed -i' \
  | grep -v '/tests/' || true)
eq "no script writes session-status into a note" "$(printf '%s' "$writers" | grep -c . || true)" 0
# And the state table itself must still be readable as the authority: one file, both keys, the expiry date.
# NOT A COUNT. The first version of these two asserted how MANY times each string appears, which is a number
# that changes whenever a sentence is rewritten and says nothing about correctness — a test that fails on an
# edit to a comment trains people to stop reading failures.
eq "the library names the expiry date"  "$(grep -q '2026-10-04' "$LIB" && echo yes || echo no)" yes
eq "the library still knows the old key" "$(grep -q 'session-status' "$LIB" && echo yes || echo no)" yes
eq "the library knows the new values"    "$(grep -q 'draft/running' "$LIB" && grep -q 'archived/ended' "$LIB" && echo yes || echo no)" yes

printf '\n%s checks, %s failed\n' "$n" "$fails"
[ "$fails" = 0 ] || exit 1
