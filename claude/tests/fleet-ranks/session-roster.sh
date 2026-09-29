#!/usr/bin/env bash
# THE SESSION ROSTER: the four keys, who writes them, and what a resume may do with them.
#
# WHAT IS GUARDED. A session's notebook entry is the record OF that session — `session-id` (full, 36
# characters), `session`, `agent`, `cwd` — and after `claude rm` it is the ONLY place the name, the agent and
# the directory still exist. So three things must hold: the hook writes them and never lies, the sweeper
# removes a job only when the entry can stand in for it, and a resume refuses rather than guesses.
#
# THE FIRST CASE IS THE REAL NOTEBOOK, read-only, as `claude/tests/README.md` requires — a suite that only
# meets its own fixtures is a test of the fixtures. It asserts the properties that must hold whatever the
# fleet is doing and PRINTS the counts, because they move while it measures: entries are written by other
# sessions mid-run, and a count asserted over a live tree fails on somebody else's turn.
#
# EVERYTHING ELSE IS SEALED. Temp notebook, temp registry, temp job state, temp projects directory, a fake
# `claude` that records rather than acts. No fleet id is ever a fixture — not as a target, not as an argument
# to a check that stops before it acts; that rule came from a run that did the real thing to a real session,
# and the proof of the full-id STOP in `wake-and-promote.sh` is taken with a THROWAWAY's id for the same
# reason. Nothing here dispatches, wakes, stops or removes anything.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
ROOT=$(cd "$HERE/../../.." && pwd -P)
LIB_ROOTS="$ROOT/claude/lib/notebook-roots.sh"
LIB_STATUS="$ROOT/claude/lib/session-status.sh"
LIB_ROSTER="$ROOT/claude/lib/session-roster.sh"
HOOK="$ROOT/claude/hooks/notebook-name-sync.sh"
SWEEP="$ROOT/claude/bin/sweep-jobs.sh"
TMP=$(mktemp -d -t session-roster) || exit 1
trap 'rm -rf "$TMP"' EXIT
n=0; fails=0; skips=0
# Every check outside section 1, whose own count depends on whether the real notebook is on this machine.
SUITE_BASE=139
SECTION1_CHECKS=0
SECTION1_SKIPPED=0
eq() { n=$((n + 1)); if [ "$2" = "$3" ]; then printf 'PASS  %-56s %s\n' "$1" "$2"; else fails=$((fails + 1)); printf 'FAIL  %-56s got %s, want %s\n' "$1" "$2" "$3"; fi; }
pass() { n=$((n + 1)); printf 'PASS  %-56s %s\n' "$1" "${2:-yes}"; }
fail() { n=$((n + 1)); fails=$((fails + 1)); printf 'FAIL  %-56s %s\n' "$1" "${2:-}"; }
has() {  # has <label> <haystack> <needle>
  case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "did not carry '$3': $(printf '%s' "$2" | tr '\n' ' ' | cut -c1-110)" ;; esac
}
hasnt() {
  case "$2" in *"$3"*) fail "$1" "carried '$3' and should not" ;; *) pass "$1" ;; esac
}

# NO `eval "$@"`. The first version re-split every argument on whitespace, and the fixtures live under a
# `/var/folders/…` temp path — so six cases silently compared a path fragment against a value. The snippet is
# interpolated into the shell program and its arguments arrive as `$1`, `$2`, quoted by the caller.
lib() {  # lib <snippet> [args…]; inside the snippet the args are $1, $2, …
  lib_snippet="$1"; shift
  bash -euo pipefail -c '. "$1"; . "$2"; . "$3"; shift 3
'"$lib_snippet"'' _ "$LIB_ROOTS" "$LIB_STATUS" "$LIB_ROSTER" "$@" 2>&1
}

echo "=== 1. THE REAL NOTEBOOK, read-only, under the callers own shell options"
# Pointable, so a MUTATION RUN can skip it. Section 1 reads every entry in the real notebook — 495 of them,
# about two minutes — and the reviewer of this branch reported his mutation run stalling behind it and giving
# up after two of six mutants. A discipline that costs two minutes a mutant is a discipline nobody completes,
# so `ROSTER_REAL_AGENTS=/nonexistent` turns section 1 into its SKIP branch and the count guard adapts. The
# default is the real notebook and no runner has to know this exists.
REAL_AGENTS="${ROSTER_REAL_AGENTS:-$HOME/obsidian/00-09 System/03 Agents}"
if [ -d "$REAL_AGENTS/03.04 Records/Agent notebook" ]; then
  real=$(bash -euo pipefail -c '
    . "$1"; . "$2"; . "$3"
    files=$(notebook_entry_files_of "$4/03.04 Records/Agent notebook" 0 "$4/03.09 Archive/Agent notebook" 0)
    total=0; full=0; four=0; short=0
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      total=$((total + 1))
      roster_read "$f"
      [ -n "$roster_id" ] || continue
      if roster_id_is_full "$roster_id"; then
        full=$((full + 1))
        [ -n "$roster_session" ] && [ -n "$roster_agent" ] && [ -n "$roster_cwd" ] && four=$((four + 1))
      else
        short=$((short + 1))
      fi
    done <<EOF
$files
EOF
    printf "%s %s %s %s" "$total" "$full" "$four" "$short"
  ' _ "$LIB_ROOTS" "$LIB_STATUS" "$LIB_ROSTER" "$REAL_AGENTS" 2>/dev/null)
  rc=$?
  eq "the live notebook does not abort a strict caller" "$rc" 0
  set -- $real
  live_total="${1:-0}"; live_full="${2:-0}"; live_four="${3:-0}"; live_short="${4:-0}"
  if [ "$live_total" -gt 100 ]; then pass "the population is real ($live_total entries read)"
  else fail "the population is real" "only $live_total entries; this section proves nothing at that size"; fi
  # A REAL PROPERTY, not a tautology. The first version compared two counters where one is incremented only
  # inside the other's branch — true by construction, unable to fail, and the review named it. What actually
  # matters is that the SHORT ids are the historical bulk and that no entry the sweeper could act on carries
  # one, so this re-reads the population and asserts that no four-key entry has a short id.
  bad=$(bash -euo pipefail -c '
    . "$1"; . "$2"; . "$3"
    files=$(notebook_entry_files_of "$4/03.04 Records/Agent notebook" 0 "$4/03.09 Archive/Agent notebook" 0)
    n=0
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      roster_read "$f"
      [ -n "$roster_session" ] && [ -n "$roster_agent" ] && [ -n "$roster_cwd" ] || continue
      roster_id_is_full "$roster_id" || n=$((n + 1))
    done <<EOF
$files
EOF
    printf "%s" "$n"
  ' _ "$LIB_ROOTS" "$LIB_STATUS" "$LIB_ROSTER" "$REAL_AGENTS" 2>/dev/null)
  eq "no four-key entry carries a short id" "${bad:-unknown}" 0
  eq "and the short ids are the historical bulk" "$([ "$live_short" -gt "$live_full" ] && echo yes || echo no)" yes
  printf '      live counts: %s entries, %s with a full id, %s with all four keys, %s short or junk\n' \
    "$live_total" "$live_full" "$live_four" "$live_short"
  SECTION1_CHECKS=4
else
  n=$((n + 1)); skips=$((skips + 1))
  printf 'SKIP  %-56s the notebook is not at %s\n' "the real-notebook population case" "$REAL_AGENTS"
  # AND IT SAYS WHAT THIS RUN NO LONGER PROVES. A suite that skips a section and still ends "0 failed" reads
  # as a pass to anyone who looks at the last line — which is the same failure as a suite that prints a happy
  # total while its assertions never ran, the one the count guard exists for. The properties lost here are the
  # ones only the real corpus can show: that no four-key entry carries a short id, and that 495 real entries
  # do not abort a caller running under `set -euo pipefail`.
  printf 'WARN  this run does NOT prove the real-notebook properties: no four-key entry with a short id, and no abort across the live corpus\n'
  SECTION1_SKIPPED=1
  SECTION1_CHECKS=1
fi

echo
echo "=== 2. the roster reader: the four keys, and what counts as a full id"
NB="$TMP/nb"; mkdir -p "$NB/2026-09"
entry() {  # entry <file> <lines…>
  f="$NB/2026-09/$1"; shift
  { printf -- '---\n'; for l in "$@"; do printf '%s\n' "$l"; done; printf -- '---\n\nbody\n'; } > "$f"
  printf '%s' "$f"
}
E_FOUR=$(entry "Agent session 2026-09-29T0401.md" 'session: "[L0-CC] roster four"' 'session-id: aaaaaaaa-1111-2222-3333-444444444444' 'agent: lieutenant' 'cwd: /tmp/four' 'status: draft/running')
E_NOAGENT=$(entry "Agent session 2026-09-29T0402.md" 'session: "[L0-CC] no agent"' 'session-id: bbbbbbbb-1111-2222-3333-444444444444' 'cwd: /tmp/noagent' 'status: archived/ended')
E_NOCWD=$(entry "Agent session 2026-09-29T0403.md" 'session: "[L0-CC] no cwd"' 'session-id: cccccccc-1111-2222-3333-444444444444' 'agent: lieutenant' 'status: archived/ended')
E_SHORT=$(entry "Agent session 2026-09-29T0404.md" 'session: "[L0-CC] short id"' 'session-id: dddddddd' 'agent: lieutenant' 'cwd: /tmp/short' 'status: archived/ended')
E_CLAUDE=$(entry "Agent session 2026-09-29T0405.md" 'session: "[C0-CC] a captain of nelsons"' 'session-id: eeeeeeee-1111-2222-3333-444444444444' 'agent: claude' 'cwd: /tmp/claude' 'status: archived/ended')
E_DISAGREE=$(entry "Agent session 2026-09-29T0406.md" 'session: "[C1-CC] says commander"' 'session-id: ffffffff-1111-2222-3333-444444444444' 'agent: lieutenant' 'cwd: /tmp/dis' 'status: archived/ended')

eq "all four keys read back"       "$(lib 'roster_read "$1"; printf "%s|%s|%s" "$roster_id" "$roster_agent" "$roster_cwd"' "$E_FOUR")" "aaaaaaaa-1111-2222-3333-444444444444|lieutenant|/tmp/four"
eq "a missing agent reads empty"   "$(lib 'roster_read "$1"; printf "[%s]" "$roster_agent"' "$E_NOAGENT")" "[]"
eq "a missing cwd reads empty"     "$(lib 'roster_read "$1"; printf "[%s]" "$roster_cwd"' "$E_NOCWD")" "[]"
# THE ROUND TRIP, which is what the quoting is for: a value carrying a hash and a trailing space comes back
# exactly as it went in. Unquoted it lost everything from the hash, and a post-rm resume would have started in
# the wrong directory.
# A DISTINCT ID: reusing E_FOUR's made this the NEWEST entry for it, so the sweeper case that expected
# "reads 'running'" correctly read this statusless entry instead. The newest-wins rule working, and my fixture
# colliding with it.
E_HASH=$(entry "Agent session 2026-09-29T0409.md" 'session: "[L0-CC] hashy"' 'session-id: 11111111-2222-3333-4444-555555555555' 'agent: "lieutenant"' 'cwd: "/tmp/live #2"')
eq "a quoted value with a hash survives" "$(lib 'roster_read "$1"; printf "%s" "$roster_cwd"' "$E_HASH")" "/tmp/live #2"
eq "an unquoted value still drops its comment" "$(lib 'roster_read "$1"; printf "%s" "$roster_agent"' "$E_FOUR")" "lieutenant"
# AN INDENTED KEY IS NOT THE RECORD'S KEY. The reader used to accept any indentation and take the last
# match, so a `cwd:` nested under a parent mapping beat the real one — and the writer only ever touches column
# zero, so the two disagreed about which line holds the value. A post-rm resume would have believed the nested
# one and started the session in the wrong directory.
E_NEST=$(entry "Agent session 2026-09-29T0410.md" 'session: "[L0-CC] nested"' 'session-id: 22222222-3333-4444-5555-666666666666' 'agent: lieutenant' 'cwd: /tmp/real' 'meta:' '  cwd: /tmp/nested')
eq "a nested cwd does not win"     "$(lib 'roster_read "$1"; printf "%s" "$roster_cwd"' "$E_NEST")" "/tmp/real"
# AN UNCLOSED BLOCK IS NOT FRONTMATTER FOR THE READER EITHER. The writer has refused one since the review of
# #71 while this read to the end of the file and handed back body PROSE as keys — enough to pass the sweeper's
# four-key test, or to send a resume to a directory named in a paragraph. A reader more credulous than the
# writer is where a broken record does its damage.
E_OPEN="$NB/2026-09/Agent session 2026-09-29T0411.md"
printf -- '---\nsession: "[L0-CC] unclosed"\nsession-id: 33333333-4444-5555-6666-777777777777\n\nagent: this is prose, not a key\ncwd: /tmp/from-the-body\n' > "$E_OPEN"
eq "an unclosed block reads as nothing"  "$(lib 'roster_read "$1"; printf "[%s|%s|%s]" "$roster_id" "$roster_agent" "$roster_cwd"' "$E_OPEN")" "[||]"

# A KEY STATED TWICE READS AS NOTHING, on both sides. The writer rewrites a key in place and this takes the
# last, and while the writer rewrote the FIRST the two disagreed about which line held the value — a resume
# went to a directory nobody wrote. The writer refuses such a record now, and so does this: empty is "not
# known", which makes the sweeper skip and a resume refuse.
E_DUP=$(entry "Agent session 2026-09-29T0412.md" 'session: "[L0-CC] doubled"' 'session-id: 55555555-6666-7777-8888-999999999999' 'agent: lieutenant' 'cwd: /tmp/first' 'cwd: /tmp/second')
eq "a doubled cwd reads as nothing"      "$(lib 'roster_read "$1"; printf "[%s]" "$roster_cwd"' "$E_DUP")" "[]"
eq "and the keys beside it still read"   "$(lib 'roster_read "$1"; printf "%s" "$roster_agent"' "$E_DUP")" "lieutenant"
# THE TWO ID TESTS ARE ASYMMETRIC ON PURPOSE, and this asserts the asymmetry rather than either half alone.
# `roster_entry_may_be_id` decides which entries COMPETE to be the newest, where a false positive costs a skip
# and a false negative costs a live session's job — so it is loose. `roster_entry_is_id` decides whether an
# entry is OURS TO WRITE INTO, where a false positive overwrites another session's record — so it is strict.
# Every previous version had one test doing both jobs, and it was wrong in the dangerous direction twice.
ID5=abcdef01-2222-3333-4444-555555555555
E_COMMENT=$(entry "Agent session 2026-09-29T0420.md" 'session: "[L0-CC] commented id"' "session-id: $ID5 # hand-edited" 'agent: lieutenant' 'cwd: /tmp/c')
E_BODYID="$NB/2026-09/Agent session 2026-09-29T0421.md"
printf -- '---\nsession: "[L0-CC] body id"\nagent: lieutenant\ncwd: /tmp/b\n---\n\nsession-id: %s\n' "$ID5" > "$E_BODYID"
# A TRAILING COMMENT is what `roster_value` strips, so the reader calls this entry ID5 — and the selection test
# must agree, or the entry vanishes from the comparison and an older ended one decides.
eq "the reader takes an id with a comment"   "$(lib 'roster_read "$1"; printf "%s" "$roster_id"' "$E_COMMENT")" "$ID5"
eq "and it competes for newest"              "$(lib 'roster_entry_may_be_id "$1" "'"$ID5"'" && echo yes || echo no' "$E_COMMENT")" yes
eq "and it is ours to write into"            "$(lib 'roster_entry_is_id "$1" "'"$ID5"'" && echo yes || echo no' "$E_COMMENT")" yes
# AN ID IN THE BODY ONLY: it may compete (a spurious competitor only causes a skip) but it is NOT ours.
eq "a body-only id may compete"              "$(lib 'roster_entry_may_be_id "$1" "'"$ID5"'" && echo yes || echo no' "$E_BODYID")" yes
eq "but a body-only id is never ours"        "$(lib 'roster_entry_is_id "$1" "'"$ID5"'" && echo yes || echo no' "$E_BODYID")" no
eq "and a doubled id is never ours"          "$(lib 'roster_entry_is_id "$1" "aaaaaaaa-1111-2222-3333-444444444444" && echo yes || echo no' "$E_FOUR")" yes
# THE TWO COPIES OF THE SHARED PARSE MUST NOT DRIFT. The hook cannot source the library — it runs before
# anything sets a library path and must never fail a turn — so the awk program that reads `session-id` exists
# twice. Two parsers of one line disagreeing is the defect this package produced twice over five review
# rounds, once by stripping a trailing comment the other kept and once by anchoring a line the other did not,
# and both times it cost a live session's record or its job. Two copies are acceptable only with a check that
# compares them, so this extracts both programs and requires them to be identical, byte for byte.
LIBPROG=$(sed -n '/^roster_id_in_frontmatter()/,/^}/p' "$ROOT/claude/lib/session-roster.sh" | sed -n '/awk /,/END { if (closed) print last }/p')
HOOKPROG=$(sed -n '/^nns_id_in_frontmatter()/,/^}/p' "$HOOK" | sed -n '/awk /,/END { if (closed) print last }/p')
if [ -n "$LIBPROG" ] && [ "$LIBPROG" = "$HOOKPROG" ]; then pass "the shared id parse is identical in both files"
else fail "the shared id parse is identical in both files" "the library and the hook have drifted, or the extraction found nothing"; fi
# AND NEITHER COPY MAY CARRY A LITERAL APOSTROPHE, which would close the single-quoted program early. This has
# now happened three times in this package, and the third time was inside the very function written to stop
# two parsers disagreeing.
eq "no apostrophe in the library parse"      "$(printf '%s' "$LIBPROG" | tr -cd "'" | wc -c | tr -d ' ')" 2
eq "no apostrophe in the hook parse"         "$(printf '%s' "$HOOKPROG" | tr -cd "'" | wc -c | tr -d ' ')" 2
eq "a full id is accepted"         "$(lib 'roster_read "$1"; roster_id_is_full "$roster_id" && echo yes || echo no' "$E_FOUR")" yes
eq "a short id is refused"         "$(lib 'roster_read "$1"; roster_id_is_full "$roster_id" && echo yes || echo no' "$E_SHORT")" no
eq "junk in the id is refused"     "$(lib 'roster_id_is_full "vaultbridge" && echo yes || echo no')" no
# THE SHAPE, NOT JUST THE LENGTH. The first version tested a 36-character glob whose `?` matches a dash and a
# character class that allowed dashes anywhere, so a string of 36 dashes was "a full id" — and would have
# become a sweeper candidate and a resume target.
eq "36 dashes is not an id"        "$(lib 'roster_id_is_full "------------------------------------" && echo yes || echo no')" no
eq "dashes in the wrong places"    "$(lib 'roster_id_is_full "aaaaaaa--1111-2222-3333-44444444444a" && echo yes || echo no')" no
eq "non-hex is not an id"          "$(lib 'roster_id_is_full "zzzzzzzz-1111-2222-3333-444444444444" && echo yes || echo no')" no
eq "a real id still passes"        "$(lib 'roster_id_is_full "aaaaaaaa-1111-2222-3333-444444444444" && echo yes || echo no')" yes

echo
# BACKTICKS IN A DOUBLE-QUOTED STRING RUN A COMMAND. This header used to carry `claude` in backticks, so the
# suite executed the real CLI — the one thing its own header promises it never does. Single quotes now.
echo '=== 3. the rank code against the agent: a disagreement refuses, and claude never disagrees'
RANKS="$ROOT/claude/bin/_fleet-ranks.sh"
rank_lib() {  # same shape as `lib`, with the rank table sourced too
  rl_snippet="$1"; shift
  bash -euo pipefail -c '. "$1"; . "$2"; . "$3"; . "$4"; shift 4
'"$rl_snippet"'' _ "$LIB_ROOTS" "$LIB_STATUS" "$LIB_ROSTER" "$RANKS" "$@" 2>&1
}
# THROUGH THE ENTRY, not a literal pair: `E_DISAGREE` exists for this and was unused.
out=$(rank_lib 'roster_read "$1"; roster_agent_disagrees "$roster_session" "$roster_agent" && printf "%s" "$roster_disagreement"' "$E_DISAGREE")
has  "a lieutenant agent under a [C1] name disagrees" "$out" "is not resolved in favour of either"
has  "and it names the agent"                        "$out" "lieutenant"
has  "and it names the rank the name carries"        "$out" "rank 1"
eq   "a matching pair does not disagree"             "$(rank_lib 'roster_agent_disagrees "[L0-CC] x" "lieutenant" && echo yes || echo no')" no
# `claude` IS NOT A RANK AND NEVER DISAGREES. 4 of 14 live sessions run as `claude` under rank-coded names —
# the obsidian captain and the rear admiral among them — so a reader that refused here would refuse their wakes.
eq   "agent claude under a captain name does not disagree" "$(rank_lib 'roster_agent_disagrees "[C0-OB] obsidian" "claude" && echo yes || echo no')" no
eq   "agent claude under a lieutenant name either"         "$(rank_lib 'roster_agent_disagrees "[L0-CC] x" "claude" && echo yes || echo no')" no
# WHICH FACT THE `no` STANDS FOR. Seven different ones used to share one exit code, so the first caller would
# have read "the rank table was never sourced" as "they agree".
# `|| true` ON EVERY ONE: six of the seven states return 1, which is the ordinary answer here.
eq "a real disagreement says disagree"     "$(rank_lib 'roster_agent_disagrees "[C1-CC] x" "lieutenant" || true; printf "%s" "$roster_agree_state"')" disagree
eq "agreement says agree"                  "$(rank_lib 'roster_agent_disagrees "[L0-CC] x" "lieutenant" || true; printf "%s" "$roster_agree_state"')" agree
# THE TWO STATES NOTHING CALLED FOR. Both return the same rc as `agree` and as each other, so only the state
# tells them apart — and an agent name the table does not know must not read as "they agree", which is how an
# entry naming a rank that no longer exists would resume as something real.
eq "an agent the table never heard of"     "$(rank_lib 'roster_agent_disagrees "[L0-CC] x" "wizard" || true; printf "%s" "$roster_agree_state"')" unknown-agent
eq "nothing to compare says no-input"      "$(rank_lib 'roster_agent_disagrees "" "" || true; printf "%s" "$roster_agree_state"')" no-input
eq "a name with no agent says no-input"    "$(rank_lib 'roster_agent_disagrees "[L0-CC] x" "" || true; printf "%s" "$roster_agree_state"')" no-input
eq "claude says not-a-rank"                "$(rank_lib 'roster_agent_disagrees "[C0-OB] x" "claude" || true; printf "%s" "$roster_agree_state"')" not-a-rank
eq "no rank table says no-table"           "$(lib 'roster_agent_disagrees "[C1-CC] x" "lieutenant" || true; printf "%s" "$roster_agree_state"')" no-table
eq "an unreadable name says unknown-name"  "$(rank_lib 'roster_agent_disagrees "no code here" "lieutenant" || true; printf "%s" "$roster_agree_state"')" unknown-name

echo
echo "=== 4. the ended-entry line: silence unless the newest entry is ended"
ended_line() {  # <id>
  bash -euo pipefail -c '. "$1"; . "$2"; . "$3"; roster_ended_line_for "$4" "$5" 1 "$6" 0; printf "%s" "$roster_ended_line"' \
    _ "$LIB_ROOTS" "$LIB_STATUS" "$LIB_ROSTER" "$1" "$NB" "$TMP/no-archive" 2>&1
}
eq "a running entry gets no line"  "$(ended_line aaaaaaaa-1111-2222-3333-444444444444)" ""
out=$(ended_line bbbbbbbb-1111-2222-3333-444444444444)
has "an ended entry gets the line"        "$out" "was ended while you were stopped"
has "and the line names the entry's path" "$out" "Agent session 2026-09-29T0402.md"
has "and it says not to reopen it"        "$out" "do not reopen it"
eq  "no entry for the id: no line, no failure" "$(ended_line 99999999-1111-2222-3333-444444444444)" ""
eq  "a short id: no line, no failure"          "$(ended_line dddddddd)" ""
# TWO ENTRIES, ONE ID: the NEWEST decides. 18 ids in the live notebook carry more than one entry, so this is a
# real case and not a hypothetical. The older one is ended, the newer one running — the line must be silent.
entry "Agent session 2026-09-28T0101.md" 'session: "[L0-CC] two entries"' 'session-id: 77777777-1111-2222-3333-444444444444' 'agent: lieutenant' 'cwd: /tmp/two' 'status: archived/ended' >/dev/null
entry "Agent session 2026-09-29T0407.md" 'session: "[L0-CC] two entries"' 'session-id: 77777777-1111-2222-3333-444444444444' 'agent: lieutenant' 'cwd: /tmp/two' 'status: draft/running' >/dev/null
eq  "two entries for one id: the newest decides" "$(ended_line 77777777-1111-2222-3333-444444444444)" ""
# AND THE OTHER WAY ROUND, which is the direction a newest-picker bug hides in: an OLDER running entry beside
# a NEWER ended one must produce the line. An empty expectation is also what a broken lookup returns, so the
# silent case above proves nothing on its own.
entry "Agent session 2026-09-27T0101.md" 'session: "[L0-CC] newer ended"' 'session-id: 44444444-1111-2222-3333-444444444444' 'agent: lieutenant' 'cwd: /tmp/ne' 'status: draft/running' >/dev/null
entry "Agent session 2026-09-29T0408.md" 'session: "[L0-CC] newer ended"' 'session-id: 44444444-1111-2222-3333-444444444444' 'agent: lieutenant' 'cwd: /tmp/ne' 'status: archived/ended' >/dev/null
has "an older running entry does not hide a newer ended one" "$(ended_line 44444444-1111-2222-3333-444444444444)" "2026-09-29T0408"

echo
echo "=== 5. where the conversation is: four outcomes, and two of them refuse"
PROJ="$TMP/projects"
mk_transcript() { mkdir -p "$PROJ/$1" && : > "$PROJ/$1/$2.jsonl"; }
tcheck() {  # <id> <cwd>
  bash -euo pipefail -c '. "$1"; . "$2"; . "$3"; roster_transcript_check "$4" "$5" "$6"; printf "%s|%s" "$roster_transcript_state" "$roster_transcript_found"' \
    _ "$LIB_ROOTS" "$LIB_STATUS" "$LIB_ROSTER" "$1" "$2" "$PROJ" 2>&1
}
ID1=aaaaaaaa-1111-2222-3333-444444444444
mk_transcript "-tmp-here" "$ID1"
eq "found at the recorded cwd"        "$(tcheck "$ID1" /tmp/here | cut -d'|' -f1)" here
eq "none anywhere is a refusal"       "$(tcheck 55555555-1111-2222-3333-444444444444 /tmp/here | cut -d'|' -f1)" none
# THE FIXTURE MUST LEAVE EXACTLY ONE. The first version left the `-tmp-here` transcript in place and then
# added a second, so the case that wanted "one other directory" had two and correctly reported `many` — the
# test was wrong, not the code.
rm -rf "$PROJ/-tmp-here"
mk_transcript "-tmp-somewhere-else" "$ID1"
out=$(tcheck "$ID1" /tmp/not-here)
eq "found under one OTHER dir is elsewhere" "$(printf '%s' "$out" | cut -d'|' -f1)" elsewhere
has "and it names the directory it found"   "$out" "-tmp-somewhere-else"
mk_transcript "-tmp-third" "$ID1"
eq "found under two others is a refusal"    "$(tcheck "$ID1" /tmp/not-here | cut -d'|' -f1)" many
# THE ENCODING IS LOSSY, which is WHY `elsewhere` refuses instead of relocating: two real directories produce
# one name. Derived from six live pairs — every character outside [A-Za-z0-9-] becomes `-`.
eq "the encoding: + becomes -"  "$(lib 'roster_transcript_dir_encode "/a/b+c"')" "-a-b-c"
eq "the encoding: . becomes -"  "$(lib 'roster_transcript_dir_encode "/a/.b"')"  "-a--b"
eq "two paths, one directory name" \
   "$([ "$(lib 'roster_transcript_dir_encode "/w/feat+x"')" = "$(lib 'roster_transcript_dir_encode "/w/feat-x"')" ] && echo yes || echo no)" yes

echo
echo "=== 6. the hook writes the keys, on a turn, and never lies"
HNB="$TMP/hooknb"; mkdir -p "$HNB/2026-09" "$TMP/sessions" "$TMP/jobs/abcd1234"
SID=abcd1234-1111-2222-3333-444444444444
printf '{"sessionId":"%s","name":"[L0-CC] roster test","jobId":"abcd1234","cwd":"%s","agent":"lieutenant"}\n' "$SID" "$TMP/live" > "$TMP/sessions/1.json"
printf '{"template":"lieutenant-repository","cwd":"%s"}\n' "$TMP/start" > "$TMP/jobs/abcd1234/state.json"
hook_entry() {
  { printf -- '---\nsession: "[L0-CC] roster test"\nstatus: draft/running\n'; [ -z "${1:-}" ] || printf '%s\n' "$1"; printf -- '---\n\nthe body must survive\n'; } > "$HNB/2026-09/Agent session 2026-09-29T0500.md"
}
run_hook() {
  printf '%s' "{\"hook_event_name\":\"${2:-UserPromptSubmit}\",\"session_id\":\"$SID\"${3:-}}" \
    | NOTEBOOK_NAME_SYNC_DIR="$HNB" NOTEBOOK_NAME_SYNC_SCRIPT=/usr/bin/true \
      NOTEBOOK_NAME_SYNC_SESSIONS_DIR="$TMP/sessions" NOTEBOOK_NAME_SYNC_JOBS_DIR="$TMP/jobs" \
      "$HOOK" >/dev/null 2>&1
  hook_rc=$?
}
hook_entry; run_hook
body=$(cat "$HNB/2026-09/Agent session 2026-09-29T0500.md")
eq   "the hook exits 0"                    "$hook_rc" 0
has  "it writes the full session-id, quoted" "$body" 'session-id: "'"$SID"'"'
has  "agent comes from the JOB STATE"      "$body" 'agent: "lieutenant-repository"'
hasnt "not from the registry"              "$body" 'agent: "lieutenant"'
has  "cwd comes from the REGISTRY"         "$body" 'cwd: "'"$TMP/live"'"'
has  "the body survives"                   "$body" "the body must survive"
cp "$HNB/2026-09/Agent session 2026-09-29T0500.md" "$TMP/after-first"
run_hook
if cmp -s "$TMP/after-first" "$HNB/2026-09/Agent session 2026-09-29T0500.md"; then pass "a second turn changes nothing (idempotent)"
else fail "a second turn changes nothing (idempotent)" "the file changed"; fi
# NEITHER AGENT SOURCE: nothing is invented, and the turn still passes.
rm -rf "$TMP/jobs/abcd1234"
printf '{"sessionId":"%s","name":"[L0-CC] roster test","jobId":"gone","cwd":"%s"}\n' "$SID" "$TMP/live" > "$TMP/sessions/1.json"
hook_entry; run_hook
body=$(cat "$HNB/2026-09/Agent session 2026-09-29T0500.md")
eq    "with no agent anywhere the hook still exits 0" "$hook_rc" 0
hasnt "and writes no agent key"                        "$body" "agent:"
has   "but still writes the id"                        "$body" 'session-id: "'"$SID"'"'
# A RESUME IS NOT A TURN: the keys are READ on a resume, so writing then would race the read.
printf '{"sessionId":"%s","name":"[L0-CC] roster test","jobId":"abcd1234","cwd":"%s","agent":"lieutenant"}\n' "$SID" "$TMP/live" > "$TMP/sessions/1.json"
mkdir -p "$TMP/jobs/abcd1234"; printf '{"template":"lieutenant-repository"}\n' > "$TMP/jobs/abcd1234/state.json"
hook_entry; run_hook "" SessionStart ',"source":"resume"'
body=$(cat "$HNB/2026-09/Agent session 2026-09-29T0500.md")
eq    "a resume exits 0"          "$hook_rc" 0
hasnt "and writes nothing"        "$body" "session-id:"
# THE POSITIVE CONTROL. "Writes nothing" also passes when the hook exited early for an unrelated reason — a
# missing jq, an unmatched registry row, a name lookup that failed — so the same fixture is run as a TURN and
# must write. Without this pair the negative proves only that something did not happen.
hook_entry; run_hook
has   "but the same fixture on a TURN does write" "$(cat "$HNB/2026-09/Agent session 2026-09-29T0500.md")" "session-id:"

# THE SHAPES THE REVIEW FOUND, each of which the hook handles and none of which had a case. A fix with no
# test is a fix until someone edits the line.
hook_raw() {  # hook_raw <lines…> — the whole entry, fence included, so the broken shapes can be written
  { for l in "$@"; do printf '%s\n' "$l"; done; } > "$HNB/2026-09/Agent session 2026-09-29T0500.md"
}
hook_body() { cat "$HNB/2026-09/Agent session 2026-09-29T0500.md"; }
FOREIGN=99999999-1111-2222-3333-444444444444

# ANOTHER SESSION'S ID IS NEVER WRITTEN OVER. This is the defect the review of #71 found in the wild: the
# entry was matched by DISPLAY NAME, and a name recurs — eleven sessions shared one on 2026-09-26.
hook_entry "session-id: \"$FOREIGN\""; run_hook
body=$(hook_body)
eq    "a foreign id exits 0"                     "$hook_rc" 0
has   "the foreign id is left exactly as it was" "$body" "$FOREIGN"
hasnt "and ours is not written beside it"        "$body" "$SID"
hasnt "and no cwd is written either"             "$body" "cwd:"

# TWO ids, OURS FIRST AND A FOREIGN ONE LAST. The reader takes the last; the writer took the first, so this
# entry read as ours on the way in and as somebody else's on the way out. Both take the last now, so this
# refuses — which is the safe direction when a record disagrees with itself.
hook_raw '---' 'session: "[L0-CC] roster test"' "session-id: \"$SID\"" "session-id: \"$FOREIGN\"" 'status: draft/running' '---' '' 'body'
run_hook
body=$(hook_body)
eq    "two ids, the foreign one last: exits 0"   "$hook_rc" 0
hasnt "and nothing is written"                   "$body" "cwd:"

# NO CLOSING FENCE IS NOT FRONTMATTER. Without this the writer stayed "inside frontmatter" to the end of the
# file and rewrote body lines that happened to begin `agent:` or `cwd:`.
hook_raw '---' 'session: "[L0-CC] roster test"' 'status: draft/running' '' 'agent: this is prose, not a key'
run_hook
body=$(hook_body)
eq    "an unclosed frontmatter exits 0"          "$hook_rc" 0
hasnt "and writes nothing at all"                "$body" "session-id:"
has   "and leaves the prose alone"               "$body" "agent: this is prose, not a key"

# A NESTED KEY IS NOT HOISTED OUT OF ITS PARENT. Rewriting it would destroy the parent mapping, and the line
# count would not change, so the guard at the end of the write would pass it through.
hook_raw '---' 'session: "[L0-CC] roster test"' 'status: draft/running' 'meta:' '  cwd: /tmp/nested' '---' '' 'body'
run_hook
body=$(hook_body)
has   "the nested cwd is left nested"            "$body" "  cwd: /tmp/nested"
has   "and the real cwd is added at column zero" "$body" "cwd: \"$TMP/live\""

# A FOLDED VALUE IS REFUSED, NOT HALF-REPLACED. `agent: >` and an indented line are one value across two
# lines: replacing the first orphans the second under the new scalar, and the file does not shrink, so the
# line-count guard sees nothing wrong.
hook_raw '---' 'session: "[L0-CC] roster test"' 'status: draft/running' 'agent: >' '  lieutenant' '---' '' 'body'
run_hook
body=$(hook_body)
eq    "a folded value exits 0"                   "$hook_rc" 0
hasnt "and nothing is written"                   "$body" "session-id:"
has   "and the folded value survives whole"      "$body" "  lieutenant"

# A BACKSLASH NEVER REACHES `awk -v`, WHICH INTERPRETS ESCAPES. A cwd holding `\n` wrote a real line break
# inside a quoted scalar — two lines where the note has one value, and the frontmatter no longer parses. The
# key is blanked, the id still lands, and the block is still one block.
printf '{"sessionId":"%s","name":"[L0-CC] roster test","jobId":"abcd1234","cwd":"/tmp/a\\\\nb","agent":"lieutenant"}\n' "$SID" > "$TMP/sessions/1.json"
# The fixture already carries a cwd, because blanking is only meaningful where a value is standing: an absent
# key with an unwritable value stays absent, which is right and proves nothing.
hook_entry 'cwd: /tmp/the-old-place'; run_hook
body=$(hook_body)
eq    "a cwd holding a backslash exits 0"        "$hook_rc" 0
has   "the stale value is blanked"               "$body" 'cwd: ""'
hasnt "and the old directory does not stand"     "$body" "/tmp/the-old-place"
hasnt "no backslash reaches the record"          "$body" '\'
has   "and the id still lands"                   "$body" "session-id: \"$SID\""
eq    "the frontmatter is still one block"       "$(grep -c '^---$' "$HNB/2026-09/Agent session 2026-09-29T0500.md")" 2
printf '{"sessionId":"%s","name":"[L0-CC] roster test","jobId":"abcd1234","cwd":"%s","agent":"lieutenant"}\n' "$SID" "$TMP/live" > "$TMP/sessions/1.json"

# A FOREIGN ID FOLLOWED BY A BLANK ONE. This is the road around the identity guard: the writer takes the LAST
# `session-id` as the entry's identity, the last value here is empty, so the entry counted as id-less, was
# adopted — and the FOREIGN line, being the first, was the one overwritten. The record then claimed a live
# session's id. A key stated twice is refused outright now.
hook_raw '---' 'session: "[L0-CC] roster test"' "session-id: \"$FOREIGN\"" 'session-id:' 'status: draft/running' '---' '' 'body'
run_hook
body=$(hook_body)
eq    "a foreign id then a blank one exits 0"    "$hook_rc" 0
has   "the foreign id is untouched"              "$body" "$FOREIGN"
hasnt "and ours is not written"                  "$body" "$SID"

# A DOUBLED `cwd`: the writer rewrote the first and the reader took the last, so a resume went to a directory
# nobody wrote. Neither line is touched now.
hook_raw '---' 'session: "[L0-CC] roster test"' 'status: draft/running' 'cwd: /tmp/first' 'cwd: /tmp/second' '---' '' 'body'
run_hook
body=$(hook_body)
eq    "a doubled cwd exits 0"                    "$hook_rc" 0
has   "the first is left alone"                  "$body" "cwd: /tmp/first"
has   "and so is the second"                     "$body" "cwd: /tmp/second"
hasnt "and nothing is written"                   "$body" "session-id:"

# A CONTROL CHARACTER NEVER REACHES THE RECORD. A backspace byte in a cwd went raw into the quoted scalar, and
# YAML does not allow one there — the note's properties stop parsing. Only `"` and `\` were refused before.
printf '{"sessionId":"%s","name":"[L0-CC] roster test","jobId":"abcd1234","cwd":"/tmp/a\\bb","agent":"lieutenant"}\n' "$SID" > "$TMP/sessions/1.json"
hook_entry 'cwd: /tmp/the-old-place'; run_hook
body=$(hook_body)
eq    "a cwd holding a control byte exits 0"     "$hook_rc" 0
has   "the stale value is blanked"               "$body" 'cwd: ""'
eq    "and no control byte is in the file"       "$(LC_ALL=C tr -d '\n' < "$HNB/2026-09/Agent session 2026-09-29T0500.md" | LC_ALL=C grep -c '[[:cntrl:]]' || true)" 0
has   "and the id still lands"                   "$body" "session-id: \"$SID\""
printf '{"sessionId":"%s","name":"[L0-CC] roster test","jobId":"abcd1234","cwd":"%s","agent":"lieutenant"}\n' "$SID" "$TMP/live" > "$TMP/sessions/1.json"

# THE NEWEST ENTRY OF THE NAME IS THE ONE WRITTEN TO. The candidate list came back in directory order and the
# loop stopped at the first `running` entry, so a STALE running entry from an earlier session of the same name
# won. An entry with no `session-id` is adopted by design — that is what an entry written before the roster
# ruling looks like — so the stale one took today's id, agent and cwd while the live session's own entry got
# nothing. Both entries here are id-less and running, which is exactly the shape that has no other tiebreak.
rm -f "$HNB/2026-09/Agent session 2026-09-29T0500.md"
for stamp in 2026-09-20T0100 2026-09-29T2300; do
  printf -- '---\nsession: "[L0-CC] roster test"\nstatus: draft/running\n---\n\nbody\n' > "$HNB/2026-09/Agent session $stamp.md"
done
run_hook
has   "the newest same-named entry is written"   "$(cat "$HNB/2026-09/Agent session 2026-09-29T2300.md")" "session-id: \"$SID\""
hasnt "and the stale one is left alone"          "$(cat "$HNB/2026-09/Agent session 2026-09-20T0100.md")" "session-id:"
rm -f "$HNB/2026-09/Agent session 2026-09-20T0100.md" "$HNB/2026-09/Agent session 2026-09-29T2300.md"
# AND AGAIN WITH THE FILES CREATED IN THE OTHER ORDER. The check above depends on what `grep -rl` hands back,
# which on this filesystem is alphabetical — so on a filesystem that returns creation order it could pass
# without the sort at all. Creating the newest FIRST means one of the two runs contradicts creation order
# whatever the filesystem does, and only a real sort passes both.
for stamp in 2026-09-29T2300 2026-09-20T0100; do
  printf -- '---\nsession: "[L0-CC] roster test"\nstatus: draft/running\n---\n\nbody\n' > "$HNB/2026-09/Agent session $stamp.md"
done
run_hook
has   "newest wins whatever order they were made in" "$(cat "$HNB/2026-09/Agent session 2026-09-29T2300.md")" "session-id: \"$SID\""
rm -f "$HNB/2026-09/Agent session 2026-09-20T0100.md" "$HNB/2026-09/Agent session 2026-09-29T2300.md"

# OUR OWN ENTRY BEATS A NEWER ONE THAT IS NOT OURS. A plain newest-first sort put a later same-named session's
# entry ahead of ours; the write refused on its foreign id and this session's own entry got nothing. An entry
# carrying our id is unambiguously ours, so it is tried first.
printf -- '---\nsession: "[L0-CC] roster test"\nsession-id: "%s"\nstatus: draft/running\n---\n\nbody\n' "$SID" > "$HNB/2026-09/Agent session 2026-09-20T0200.md"
printf -- '---\nsession: "[L0-CC] roster test"\nsession-id: "%s"\nstatus: draft/running\n---\n\nbody\n' "$FOREIGN" > "$HNB/2026-09/Agent session 2026-09-29T2200.md"
run_hook
has   "our own older entry is written, not the newer foreign one" "$(cat "$HNB/2026-09/Agent session 2026-09-20T0200.md")" "cwd: \"$TMP/live\""
hasnt "and the foreign entry is untouched"       "$(cat "$HNB/2026-09/Agent session 2026-09-29T2200.md")" "cwd:"
rm -f "$HNB/2026-09/Agent session 2026-09-20T0200.md" "$HNB/2026-09/Agent session 2026-09-29T2200.md"

# A BODY LINE MUST NOT MAKE ANOTHER SESSION'S ENTRY OURS. The ownership test grepped the whole file, so an
# id-less entry belonging to someone else — with our id quoted in its body, in a pasted handoff — was tried
# first, and the writer (which reads only the frontmatter, sees no id, and adopts an id-less entry by design)
# wrote our facts over that session's record. Ownership is decided inside the frontmatter now.
# THE BODY LINE MUST BE AT COLUMN ZERO or it proves nothing: the first version of this fixture indented it
# behind "quoted from a handoff:", so the whole-file grep it was written to catch did not match it either and
# the case passed against the broken code. The mutation run caught that — the case went GREEN with the guard
# reverted, which is the one result a test must never give.
printf -- '---\nsession: "[L0-CC] roster test"\nstatus: draft/running\n---\n\nfrom the handoff:\n\nsession-id: %s\n' "$SID" > "$HNB/2026-09/Agent session 2026-09-19T0100.md"
printf -- '---\nsession: "[L0-CC] roster test"\nstatus: draft/running\n---\n\nbody\n' > "$HNB/2026-09/Agent session 2026-09-29T2400.md"
run_hook
hasnt "a body mention does not make an entry ours" "$(cat "$HNB/2026-09/Agent session 2026-09-19T0100.md")" "cwd:"
has   "and the newest entry is written instead"    "$(cat "$HNB/2026-09/Agent session 2026-09-29T2400.md")" "cwd: \"$TMP/live\""
rm -f "$HNB/2026-09/Agent session 2026-09-19T0100.md" "$HNB/2026-09/Agent session 2026-09-29T2400.md"

echo
echo "=== 7. the sweeper: all four keys, ended, and not alive — or it skips"
SJOBS="$TMP/sjobs"; mkdir -p "$SJOBS"
FAKE="$TMP/fake-claude"
printf '#!/usr/bin/env bash\ncase "$1" in\n  agents) printf "%%s" "$(cat "%s/listing.json")" ;;\n  rm) printf "%%s\\n" "$2" >> "%s/removed.log" ;;\nesac\nexit 0\n' "$TMP" "$TMP" > "$FAKE"
chmod +x "$FAKE"
printf '[]' > "$TMP/listing.json"
mkjob() { mkdir -p "$SJOBS/$1"; printf '{"sessionId":"%s","name":"%s"}\n' "$2" "$3" > "$SJOBS/$1/state.json"; }
mkjob aaaaaaaa aaaaaaaa-1111-2222-3333-444444444444 "[L0-CC] roster four"      # running entry
mkjob bbbbbbbb bbbbbbbb-1111-2222-3333-444444444444 "[L0-CC] no agent"         # ended but no agent key
mkjob dddddddd dddddddd                              "[L0-CC] short id"        # short id in its entry
mkjob eeeeeeee eeeeeeee-1111-2222-3333-444444444444 "[C0-CC] a captain of nelsons"  # four keys + ended
sweep() { "$SWEEP" --jobs-dir "$SJOBS" --notebook-dir "$NB" --claude-bin "$FAKE" --log "$TMP/sweeplog.md" "$@" 2>&1; }
out=$(sweep)
has  "the ended four-key job would be removed" "$out" "WOULD REMOVE  eeeeeeee"
has  "a running entry is skipped"              "$out" "SKIP  aaaaaaaa"
has  "and the skip says why"                   "$out" "reads 'running'"
has  "a missing agent key is skipped"          "$out" "SKIP  bbbbbbbb"
has  "a short id is skipped, not refused"      "$out" "SKIP  dddddddd"
eq   "a dry run removes nothing"               "$([ -f "$TMP/removed.log" ] && echo removed || echo nothing)" nothing
# ALIVE BEATS EVERYTHING, and alive means A LIVE PID — the test `wake-session.sh` uses. A row's `.status` is
# not the measure: the review showed a live row can carry none, and two readers of one listing disagreeing
# about who is alive is how a live session gets swept. `$$` is this shell, so the pid is certainly alive.
printf '[{"sessionId":"eeeeeeee-1111-2222-3333-444444444444","pid":%s}]' "$$" > "$TMP/listing.json"
out=$(sweep)
has  "a live pid is never swept"               "$out" "SKIP  eeeeeeee"
has  "and the skip says the pid is live"       "$out" "live pid"
# A ROW WITH NO `.status` AT ALL is still alive if its pid is: the case that used to read as dead.
printf '[{"sessionId":"eeeeeeee-1111-2222-3333-444444444444","pid":%s,"name":"x"}]' "$$" > "$TMP/listing.json"
has  "a live row carrying no status is alive"  "$(sweep)" "SKIP  eeeeeeee"
# A DEAD PID IS NOT ALIVE: pid 1 is init, which this test cannot own; use an id no process has.
printf '[{"sessionId":"eeeeeeee-1111-2222-3333-444444444444","pid":999999,"status":"idle"}]' > "$TMP/listing.json"
has  "a row whose pid is gone is sweepable"    "$(sweep)" "WOULD REMOVE  eeeeeeee"
# A DEAD ROW MUST NOT HIDE A LIVE ONE. The check took the FIRST row's pid for an id, so two rows sharing a
# sessionId with the dead one first swept a live session's job. One live pid anywhere under that id is enough.
printf '[{"sessionId":"eeeeeeee-1111-2222-3333-444444444444","pid":999999},{"sessionId":"eeeeeeee-1111-2222-3333-444444444444","pid":%s}]' "$$" > "$TMP/listing.json"
has  "a dead row does not hide a live one"     "$(sweep)" "SKIP  eeeeeeee"
printf '[]' > "$TMP/listing.json"

# THE LISTING MUST BE READABLE AND AN ARRAY, or the sweeper REFUSES. Every one of these used to resolve to
# "not running", which is the unsafe direction for a script that deletes.
FAKE_FAIL="$TMP/fake-claude-fail"
printf '#!/usr/bin/env bash\nexit 1\n' > "$FAKE_FAIL"; chmod +x "$FAKE_FAIL"
out=$("$SWEEP" --jobs-dir "$SJOBS" --notebook-dir "$NB" --claude-bin "$FAKE_FAIL" --log "$TMP/sweeplog.md" 2>&1); rc=$?
eq   "a failed listing refuses"                "$rc" 2
has  "and says it will not sweep blind"        "$out" "refusing to sweep without knowing"
printf '{"sessions":[{"sessionId":"eeeeeeee-1111-2222-3333-444444444444","status":"idle"}]}' > "$TMP/listing.json"
out=$(sweep); rc=$?
eq   "a listing that is not an array refuses"  "$rc" 2
has  "and says why"                            "$out" "not an array of objects"
# AN ARRAY OF THE WRONG THING IS ALSO WRONG. `[1]`, `["x"]` and `[null]` all passed a bare `type == "array"`
# check; the pid lookup then failed on each row, its failure was swallowed, and every ended job was removed.
# A sweeper that deletes must refuse a listing it cannot read, in every shape of "cannot read".
for junk in '[1]' '["eeeeeeee-1111-2222-3333-444444444444"]' '[null]'; do
  printf '%s' "$junk" > "$TMP/listing.json"
  out=$(sweep); rc=$?
  eq "a listing of $junk refuses"              "$rc" 2
done
printf '[]' > "$TMP/listing.json"

# TWO ENTRIES FOR ONE ID: the NEWEST decides. An older `archived/ended` beside a newer `draft/running` used to
# sweep the job, because the index took the first match in oldest-filename order.
entry "Agent session 2026-09-20T0100.md" 'session: "[L0-CC] two for one"' 'session-id: 66666666-1111-2222-3333-444444444444' 'agent: lieutenant' 'cwd: /tmp/two' 'status: archived/ended' >/dev/null
entry "Agent session 2026-09-29T2300.md" 'session: "[L0-CC] two for one"' 'session-id: 66666666-1111-2222-3333-444444444444' 'agent: lieutenant' 'cwd: /tmp/two' 'status: draft/running' >/dev/null
mkjob 66666666 66666666-1111-2222-3333-444444444444 "[L0-CC] two for one"
out=$(sweep)
has  "the newest entry decides, not the first" "$out" "SKIP  66666666"
has  "and the skip quotes the newest state"    "$out" "reads 'running'"

# AN UNREADABLE NEWEST ENTRY MUST NOT LET AN OLDER ONE DECIDE. The round-three rule made a record that states
# a key twice parse as nothing — safe for one entry, and dangerous here: the newest entry vanished from the
# comparison, an older `archived/ended` entry became "the newest", and the job of a session whose newest record
# says running was removed. The broken entry competes on its stamp now and then fails the four-key test, so the
# sweeper skips and a human settles the record.
entry "Agent session 2026-09-21T0100.md" 'session: "[L0-CC] unreadable newest"' 'session-id: 99999999-aaaa-bbbb-cccc-dddddddddddd' 'agent: lieutenant' 'cwd: /tmp/un' 'status: archived/ended' >/dev/null
entry "Agent session 2026-09-29T2100.md" 'session: "[L0-CC] unreadable newest"' 'session-id: 99999999-aaaa-bbbb-cccc-dddddddddddd' 'session-id: 99999999-aaaa-bbbb-cccc-dddddddddddd' 'agent: lieutenant' 'cwd: /tmp/un' 'status: draft/running' >/dev/null
mkjob 99999999 99999999-aaaa-bbbb-cccc-dddddddddddd "[L0-CC] unreadable newest"
out=$(sweep)
has  "an unreadable newest entry blocks the sweep" "$out" "SKIP  99999999"
hasnt "and the older ended entry does not decide"  "$out" "WOULD REMOVE  99999999"

# A NEWER ENTRY WHOSE ID CARRIES A TRAILING COMMENT MUST STILL COMPETE. The anchored raw match rejected the
# ` # comment` that `roster_value` strips, so the newest running entry vanished from the comparison and the
# older ended one decided — the round-four defect again, through a narrower door. That it was the same defect
# twice is why the selection test is now deliberately loose and says so.
entry "Agent session 2026-09-22T0100.md" 'session: "[L0-CC] commented newest"' 'session-id: bbbbbbbb-cccc-dddd-eeee-ffffffffffff' 'agent: lieutenant' 'cwd: /tmp/cn' 'status: archived/ended' >/dev/null
entry "Agent session 2026-09-29T2000.md" 'session: "[L0-CC] commented newest"' 'session-id: bbbbbbbb-cccc-dddd-eeee-ffffffffffff # hand-edited' 'agent: lieutenant' 'cwd: /tmp/cn' 'status: draft/running' >/dev/null
mkjob bbbbbbbb bbbbbbbb-cccc-dddd-eeee-ffffffffffff "[L0-CC] commented newest"
out=$(sweep)
has  "a commented id still competes for newest" "$out" "SKIP  bbbbbbbb"
hasnt "and the older ended entry does not win"  "$out" "WOULD REMOVE  bbbbbbbb"

# AND A SET THIS CANNOT ORDER IS NEVER SWEPT. An entry whose filename carries no stamp had no order at all and
# was given the empty string, which loses to every real stamp — so an unstamped RUNNING entry silently lost to
# a stamped ENDED one. "Newest wins" with no order is a guess, and this script deletes on the answer.
entry "Agent session 2026-09-23T0100.md" 'session: "[L0-CC] no stamp"' 'session-id: cccccccc-dddd-eeee-ffff-000000000000' 'agent: lieutenant' 'cwd: /tmp/ns' 'status: archived/ended' >/dev/null
entry "Agent session latest.md" 'session: "[L0-CC] no stamp"' 'session-id: cccccccc-dddd-eeee-ffff-000000000000' 'agent: lieutenant' 'cwd: /tmp/ns' 'status: draft/running' >/dev/null
mkjob cccccccc cccccccc-dddd-eeee-ffff-000000000000 "[L0-CC] no stamp"
has  "an undatable entry blocks the sweep"      "$(sweep)" "SKIP  cccccccc"

# THE ARCHIVE ROOT IS READ IN PRODUCTION. An ended entry MOVES there, so a sweeper that reads only the
# notebook skips exactly the population it exists for — which is what the first version did, with
# `--agents-dir` accepted and ignored.
AR="$TMP/agents"; mkdir -p "$AR/03.04 Records/Agent notebook/2026-09" "$AR/03.09 Archive/Agent notebook/2026-09"
printf -- '---\nsession: "[L0-CC] in the archive"\nsession-id: 88888888-1111-2222-3333-444444444444\nagent: lieutenant\ncwd: /tmp/arch\nstatus: archived/ended\n---\n' \
  > "$AR/03.09 Archive/Agent notebook/2026-09/Agent session 2026-09-28T0100.md"
mkjob 88888888 88888888-1111-2222-3333-444444444444 "[L0-CC] in the archive"
out=$("$SWEEP" --jobs-dir "$SJOBS" --agents-dir "$AR" --claude-bin "$FAKE" --log "$TMP/sweeplog.md" 2>&1)
has  "--agents-dir is honoured, not ignored"   "$out" "WOULD REMOVE  88888888"
has  "and the archive root is read"            "$out" "03.09 Archive"
# --go NEEDS --by, because a removal is an act and an act is attributed.
out=$(sweep --go 2>&1); rc=$?
eq   "--go without --by refuses"               "$rc" 2
has  "and says why"                            "$out" "an act is attributed"
out=$(sweep --go --by "[L0-CC] roster test")
has  "with --by it removes"                    "$out" "REMOVED  eeeeeeee"
eq   "and it called claude rm with the SHORT id" "$(cat "$TMP/removed.log" 2>/dev/null | tr -d '\n')" "eeeeeeee"
has  "and wrote one release line"              "$(cat "$TMP/sweeplog.md" 2>/dev/null)" "— release"
has  "naming the entry it read"                "$(cat "$TMP/sweeplog.md" 2>/dev/null)" "Agent session 2026-09-29T0405.md"

# THE COUNT IS PART OF THE PROOF. `claude/tests/README.md` requires it because a suite in this directory once
# printed "0 failed" while two of its assertions never ran at all — a section swallowed by a `set -u` abort
# still ends with a happy total. Update EXPECTED deliberately when you add a case.
# 80, TAKEN FROM A CLEAN RUN rather than guessed. The first value here was a guess and the guard fired on its
# own suite — which is the right failure, and the reason to set this from a run you have just watched pass.
# THE EXPECTED COUNT DEPENDS ON WHETHER SECTION 1 RAN. Section 1 reads the real notebook and runs four
# checks; where there is no notebook it runs one SKIP, so a single fixed number made the guard itself fail on
# a machine that is behaving correctly — and a guard that cries wolf is a guard someone deletes. Each branch
# says how many checks it is worth, and the total is derived.
EXPECTED=$((SUITE_BASE + SECTION1_CHECKS))
printf '\n%s checks, %s failed, %s skipped (expected %s checks)%s\n' "$n" "$fails" "$skips" "$EXPECTED" \
  "$([ "${SECTION1_SKIPPED:-0}" = 1 ] && printf ' — REAL-NOTEBOOK SECTION SKIPPED, this run proves less' || true)"
[ "$n" = "$EXPECTED" ] || { printf 'FAIL  the suite ran %s checks, not the %s it expects — a section did not run\n' "$n" "$EXPECTED"; exit 1; }
[ "$fails" = 0 ] || exit 1
