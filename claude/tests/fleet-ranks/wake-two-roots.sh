#!/usr/bin/env bash
# wake-session.sh reads the reporting line from TWO roots: the agent notebook, where running entries live, and
# the agents archive (`03 Agents/03.09*`), where an ended entry moves (ruled 2026-09-29). A stopped session's
# own entry is usually an ended one, so a wake that read only the notebook would refuse every stopped session
# after the move. This suite proves the index finds an entry in either root, follows a line that crosses them,
# lets the newest entry win whichever root it sits in, and takes only files named `Agent session *.md`.
#
# HOW TO RUN IT. Dispatch one throwaway of your own, named exactly as TARGET below, then pass its id:
#
#     cd /tmp
#     claude --bg --agent lieutenant --name "[L0-CC] two-roots test" \
#            "[test artifact — safe to delete] Do nothing. Reply standing-by and stop."
#     bash claude/tests/fleet-ranks/wake-two-roots.sh <id>
#     claude stop <id>; claude rm <id>      # afterwards, and check the listing after
#
# NEVER A LIVE FLEET ID, and a fixture is named for what it tests, as a lieutenant — see wake-and-promote.sh.
# Every wake below is `--dry-run` with `--log` in a temp dir: nothing is resumed and nothing reaches the fleet
# log. Section 1 reads the REAL notebook and archive read-only, per claude/tests/README.md: the population is
# proved real before any fixture is trusted, properties are asserted, counts are printed.
set -u
W="${2:-$(cd "$(dirname "$0")/../../bin" && pwd -P)/wake-session.sh}"
LT="${1:?usage: wake-two-roots.sh <throwaway-id> [wake-session.sh]; never a live fleet id}"
TMP=$(mktemp -d -t wake-two-roots) || exit 1
trap 'rm -rf "$TMP"' EXIT
LOG="$TMP/log.md"; : > "$LOG"
JOBS="$TMP/jobs-empty"; mkdir -p "$JOBS"
n=0; fails=0

pass() { n=$((n + 1)); printf 'PASS  [%s]\n' "$1"; }
fail() { n=$((n + 1)); fails=$((fails + 1)); printf 'FAIL  [%s]  %s\n' "$1" "${2:-}"; }
refused_because() {  # refused_because <label> <text the refusal must carry> -- cmd...
  label="$1"; want="$2"; shift 3
  out=$("$@" 2>&1); rc=$?
  if [ "$rc" != 2 ]; then fail "$label" "rc=$rc, wanted a refusal"; return; fi
  case "$out" in
    *"$want"*) pass "$label" ;;
    *) fail "$label" "refused, but on another rail: $(printf '%s' "$out" | grep -m 1 'refused:')" ;;
  esac
}
allowed() {  # allowed <label> [<text the output must carry>] -- cmd...   (the gate let it through; it is a dry run)
  # Only 0 (a dry run) and 3 (the target is live) are a pass. `die` is the only exit 2, so "not 2" would
  # also pass a crash under set -e (rc 1, 123, 127) that prints no refusal: the abort this suite exists to see.
  label="$1"; want=""; [ "$2" != -- ] && { want="$2"; shift; }; shift 2
  out=$("$@" 2>&1); rc=$?
  case "$rc" in 0|3) ;; *) fail "$label" "rc=$rc; $(printf '%s' "$out" | grep -m 1 'refused:')"; return ;; esac
  if printf '%s' "$out" | grep -q 'refused:'; then fail "$label" "rc=$rc but refused: $(printf '%s' "$out" | grep -m 1 'refused:')"; return; fi
  if [ -n "$want" ] && ! printf '%s' "$out" | grep -qE "$want"; then fail "$label" "rc=$rc, but the output never reached: $want"; return; fi
  pass "$label"
}

TARGET="[L0-CC] two-roots test"
HOP="[C1-CC] two-roots line hop"
TOP="[C0-CC] two-roots line top"
STRANGER="[C1-OB] two-roots stranger"
listed=$(claude agents --json --all 2>/dev/null | jq -r --arg i "$LT" '.[] | select(.id == $i or .sessionId == $i) | .name' | head -n 1)
if [ "$listed" != "$TARGET" ]; then
  printf 'STOP  the throwaway %s is listed as "%s"; this suite writes its line under "%s". Nothing was run.\n' "$LT" "${listed:-(not listed at all)}" "$TARGET"
  exit 1
fi

printf -- '=== 1. the real population, read only\n'
real_nb="$HOME/obsidian/00-09 System/03 Agents/03.04 Records/Agent notebook"
real_entries=$( { find "$real_nb" -type f -name 'Agent session *.md' 2>/dev/null
                  for d in "$HOME/obsidian/00-09 System/03 Agents"/03.09*; do [ -d "$d" ] && find "$d" -type f -name 'Agent session *.md'; done; } | wc -l | tr -d ' ')
archive_entries=$(for d in "$HOME/obsidian/00-09 System/03 Agents"/03.09*; do [ -d "$d" ] && find "$d" -type f -name 'Agent session *.md'; done | wc -l | tr -d ' ')
printf 'COUNT entries named "Agent session *.md": %s in both roots, %s of them in the archive (the archive may not exist yet; it moves under you)\n' "$real_entries" "$archive_entries"
if [ "$real_entries" -gt 0 ]; then pass "the real population is real: entries exist to index"; else fail "the real population is real" "no entries found; the rest of this suite would prove nothing about the live notebook"; fi
# The survey reads the real listing and the real roots, resumes nothing without --resume-stopped, and is a
# dry run besides. It must complete — an index that died on some real file would show here and nowhere else.
# It must reach one of its two closing lines, so a survey that stopped partway cannot pass on rc alone.
allowed "the survey completes over the real notebook and archive" \
  'nothing stopped in your line|to resume every stopped session above' -- \
  "$W" --all --by "[A0] rear admiral" --log "$LOG" --dry-run

mk() {  # mk <dir> <file stem> <session> <status> <reports-to>
  mkdir -p "$1"
  printf -- '---\ntitle: %s\nsession: "%s"\nstatus: %s\nreports-to: "%s"\n---\n\n[test artifact — safe to delete]\n' "$2" "$3" "$4" "$5" > "$1/$2.md"
}

printf -- '=== 2. the whole line only in the archive\n'
NB="$TMP/c2/notebook"; AR="$TMP/c2/archive/Agent notebook"; mkdir -p "$NB"
sub="$AR/2026-09"   # the real shape: <root>/YYYY-MM/Agent session *.md
mk "$sub" "Agent session 2026-09-27T0101" "$TARGET" archived/ended "$HOP"
mk "$sub" "Agent session 2026-09-27T0102" "$HOP"    archived/ended "$TOP"
mk "$sub" "Agent session 2026-09-27T0103" "$TOP"    archived/ended "[A0] rear admiral"
allowed "an entry only in the archive is found, and the line is followed through it" -- \
  "$W" --session "$LT" --by "$HOP" --why "two roots test" --notebook-dir "$NB" --archive-dir "$AR" --jobs-dir "$JOBS" --log "$LOG" --dry-run
# THE ONE-DIFFERENCE PAIR: the same files, the archive root not given. It must refuse on the missing record,
# and it must be THAT rail — if it refused on another, the pair would prove nothing about the second root.
refused_because "without the archive root the same wake refuses on the missing record" "no notebook entry for" -- \
  "$W" --session "$LT" --by "$HOP" --why "two roots test" --notebook-dir "$NB" --jobs-dir "$JOBS" --log "$LOG" --dry-run

printf -- '=== 3. a line that crosses the roots\n'
NB="$TMP/c3/notebook"; AR="$TMP/c3/archive"
mk "$AR/2026-09" "Agent session 2026-09-27T0101" "$TARGET" archived/ended "$HOP"
mk "$NB/2026-09"   "Agent session 2026-09-27T0102" "$HOP"    draft/running  "$TOP"
mk "$NB/2026-09"   "Agent session 2026-09-27T0103" "$TOP"    draft/running  "[A0] rear admiral"
allowed "the stopped target's ended entry in the archive, its superiors' running entries in the notebook" -- \
  "$W" --session "$LT" --by "$TOP" --why "two roots test" --notebook-dir "$NB" --archive-dir "$AR" --jobs-dir "$JOBS" --log "$LOG" --dry-run

printf -- '=== 4. the newest entry wins, whichever root it sits in\n'
NB="$TMP/c4a/notebook"; AR="$TMP/c4a/archive"
mk "$NB/2026-09" "Agent session 2026-09-26T0900" "$TARGET" draft/running  "$STRANGER"
mk "$AR/2026-09" "Agent session 2026-09-27T0101" "$TARGET" archived/ended "$HOP"
mk "$NB/2026-09" "Agent session 2026-09-27T0102" "$HOP" draft/running "$TOP"
mk "$NB/2026-09" "Agent session 2026-09-27T0103" "$TOP" draft/running "[A0] rear admiral"
allowed "a newer entry in the archive outranks an older one in the notebook" -- \
  "$W" --session "$LT" --by "$HOP" --why "two roots test" --notebook-dir "$NB" --archive-dir "$AR" --jobs-dir "$JOBS" --log "$LOG" --dry-run
NB="$TMP/c4b/notebook"; AR="$TMP/c4b/archive"
mk "$AR/2026-09" "Agent session 2026-09-26T0900" "$TARGET" archived/ended "$HOP"
mk "$NB/2026-09" "Agent session 2026-09-27T0101" "$TARGET" draft/running  "$STRANGER"
mk "$NB/2026-09" "Agent session 2026-09-27T0102" "$HOP" draft/running "$TOP"
mk "$NB/2026-09" "Agent session 2026-09-27T0103" "$TOP" draft/running "[A0] rear admiral"
# The refusal must name the STRANGER as the next hop: that is the proof the newer notebook entry was the one
# followed. Had the older archive entry won, the line would have reached the hop and the wake would pass.
refused_because "a newer entry in the notebook outranks an older one in the archive" "-> $STRANGER" -- \
  "$W" --session "$LT" --by "$HOP" --why "two roots test" --notebook-dir "$NB" --archive-dir "$AR" --jobs-dir "$JOBS" --log "$LOG" --dry-run

printf -- '=== 5. only "Agent session *.md" is taken from the archive\n'
NB="$TMP/c5/notebook"; AR="$TMP/c5/archive"; mkdir -p "$NB"
mk "$AR/2026-09" "Rollup W39" "$TARGET" archived/ended "$HOP"
refused_because "a non-entry note carrying the session key is not an entry" "no notebook entry for" -- \
  "$W" --session "$LT" --by "$HOP" --why "two roots test" --notebook-dir "$NB" --archive-dir "$AR" --jobs-dir "$JOBS" --log "$LOG" --dry-run

printf -- '=== 6. the DEFAULT archive root is exactly `03.09 Archive/Agent notebook`, one YYYY-MM level down\n'
# Nelson, 2026-09-29, on this PR: "narrow it" — other folders in 03.09 hold other archived things, so the
# lookup must not read everything under the archive. These cases give no --notebook-dir and no --archive-dir,
# only --agents-dir, so they test the DEFAULT roots. The three differ from each other in the folder only.
A6() { A="$TMP/c6$1"
  mk "$A/03.04 Records/Agent notebook/2026-09" "Agent session 2026-09-27T0102" "$HOP" draft/running "$TOP"
  mk "$A/03.04 Records/Agent notebook/2026-09" "Agent session 2026-09-27T0103" "$TOP" draft/running "[A0] rear admiral"
  mk "$A/03.09 Archive/$2" "Agent session 2026-09-27T0101" "$TARGET" archived/ended "$HOP"; }
A6 a "Agent notebook/2026-09"
allowed "an entry in 03.09 Archive/Agent notebook/YYYY-MM is read by default" -- \
  "$W" --session "$LT" --by "$HOP" --why "two roots test" --agents-dir "$A" --jobs-dir "$JOBS" --log "$LOG" --dry-run
A6 b "Old records/2026-09"
refused_because "an entry elsewhere under 03.09 Archive is NOT read" "no notebook entry for" -- \
  "$W" --session "$LT" --by "$HOP" --why "two roots test" --agents-dir "$A" --jobs-dir "$JOBS" --log "$LOG" --dry-run
A6 c "Agent notebook/stray/2026-09"
refused_because "an entry deeper than YYYY-MM under the archive root is NOT read" "no notebook entry for" -- \
  "$W" --session "$LT" --by "$HOP" --why "two roots test" --agents-dir "$A" --jobs-dir "$JOBS" --log "$LOG" --dry-run

printf -- '=== nothing reached a real log\n'
if [ ! -s "$LOG" ]; then pass "the temp log is empty: every case was a dry run"; else fail "the temp log is empty" "$(wc -l < "$LOG") lines written"; fi

EXPECTED=12
printf '\n%s checks, %s failed (expected %s checks)\n' "$n" "$fails" "$EXPECTED"
[ "$n" = "$EXPECTED" ] || { printf 'FAIL  the check count is %s, not %s: a broken line swallowed a section\n' "$n" "$EXPECTED"; exit 1; }
[ "$fails" = 0 ]
