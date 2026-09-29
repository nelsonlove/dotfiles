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
REAL_AGENTS="$HOME/obsidian/00-09 System/03 Agents"
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
else
  n=$((n + 1)); skips=$((skips + 1))
  printf 'SKIP  %-56s the notebook is not at %s\n' "the real-notebook population case" "$REAL_AGENTS"
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
has  "and says why"                            "$out" "not a JSON array"
printf '[]' > "$TMP/listing.json"

# TWO ENTRIES FOR ONE ID: the NEWEST decides. An older `archived/ended` beside a newer `draft/running` used to
# sweep the job, because the index took the first match in oldest-filename order.
entry "Agent session 2026-09-20T0100.md" 'session: "[L0-CC] two for one"' 'session-id: 66666666-1111-2222-3333-444444444444' 'agent: lieutenant' 'cwd: /tmp/two' 'status: archived/ended' >/dev/null
entry "Agent session 2026-09-29T2300.md" 'session: "[L0-CC] two for one"' 'session-id: 66666666-1111-2222-3333-444444444444' 'agent: lieutenant' 'cwd: /tmp/two' 'status: draft/running' >/dev/null
mkjob 66666666 66666666-1111-2222-3333-444444444444 "[L0-CC] two for one"
out=$(sweep)
has  "the newest entry decides, not the first" "$out" "SKIP  66666666"
has  "and the skip quotes the newest state"    "$out" "reads 'running'"

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
EXPECTED=80
printf '\n%s checks, %s failed, %s skipped (expected %s checks)\n' "$n" "$fails" "$skips" "$EXPECTED"
[ "$n" = "$EXPECTED" ] || { printf 'FAIL  the suite ran %s checks, not the %s it expects — a section did not run\n' "$n" "$EXPECTED"; exit 1; }
[ "$fails" = 0 ] || exit 1
