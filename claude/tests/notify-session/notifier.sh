#!/usr/bin/env bash
# The notifier and its injecting hook, end to end, WITHOUT NOTIFYING ANYTHING REAL.
#
# HOW IT STAYS SAFE. Every notifier case passes `--dry-run`, so the script prints the acts it would take and
# writes nothing and wakes nobody; the notice directory, the fleet log and the wake script are all redirected
# to a temp dir through `NOTIFY_NOTICES_DIR`, `NOTIFY_FLEET_LOG` and `NOTIFY_WAKE_SCRIPT`; and the two cases
# that DO write a notice use a fake wake script that only records that it was called. No accept verb is
# invoked — this tests the machine that is TOLD one happened, which is the opposite — and no session is
# woken, dispatched or stopped.
#
# THE ONE THING IT CANNOT FAKE is the session listing, which comes from `claude agents --json --all`. So the
# cases that need a matching session take ONE THROWAWAY id you dispatch yourself, exactly as
# `claude/tests/fleet-ranks/wake-and-promote.sh` does, and never a live fleet id:
#
#     cd /tmp
#     claude --bg --agent lieutenant --name "[L0-FL] notifier battery target" \
#            "[test artifact — safe to delete] Do nothing. Reply standing-by and stop."
#     bash claude/tests/notify-session/notifier.sh <id>
#     claude stop <id>; claude rm <id>      # afterwards, and check the listing after
#
# A FIXTURE IS NEVER NAMED AS A RANK ABOVE A LIEUTENANT, widened by the captain on 2026-09-27 after a
# `[C0-CC] battery captain` throwaway appeared in the fleet view as a captain nobody had claimed. A throwaway
# is named for what it TESTS, as a lieutenant on its ship, and dispatched `--agent lieutenant`. Nothing here
# needs a captain-ranked session: the notifier reads a NAME out of a note and looks it up, so the rank of the
# session it finds never enters into it.
#
# Run with no arguments and the listing-dependent cases are SKIPPED and counted as skipped rather than
# passed, because a suite that silently tests less than it claims is worse than one that says so.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
ROOT=$(cd "$HERE/../../.." && pwd -P)
NOTIFY="$ROOT/claude/bin/notify-session.sh"
INJECT="$ROOT/claude/hooks/notice-inject.sh"
LT="${1:-}"   # one throwaway; there was a second for a captain-ranked row, and nothing here needs one
TMP=$(mktemp -d -t notifier-battery) || exit 1
trap 'rm -rf "$TMP"' EXIT
export NOTIFY_NOTICES_DIR="$TMP/notices"
export NOTIFY_FLEET_LOG="$TMP/log.md"
export NOTIFY_WAKE_SCRIPT="$TMP/fake-wake.sh"
: > "$NOTIFY_FLEET_LOG"
mkdir -p "$NOTIFY_NOTICES_DIR"
cat > "$NOTIFY_WAKE_SCRIPT" <<'FAKE'
#!/usr/bin/env bash
# [test artifact] records that it was called, and with what; wakes nothing.
printf '%s\n' "$*" >> "$(dirname "$0")/wake-calls.log"
exit 0
FAKE
chmod +x "$NOTIFY_WAKE_SCRIPT"
n=0; fails=0; skips=0
pass() { n=$((n + 1)); printf 'PASS  %s\n' "$1"; }
fail() { n=$((n + 1)); fails=$((fails + 1)); printf 'FAIL  %-60s %s\n' "$1" "${2:-}"; }
skip() { n=$((n + 1)); skips=$((skips + 1)); printf 'SKIP  %-60s %s\n' "$1" "${2:-no throwaway ids given}"; }

note() {  # note <name> <session-value-or-empty> ; prints the path
  local f="$TMP/$1.md"
  if [ -n "${2:-}" ]; then
    printf -- '---\ntype: Task\nsession: "%s"\nstatus: verified\n---\n\n# %s\n' "$2" "$1" > "$f"
  else
    printf -- '---\ntype: Task\nstatus: verified\n---\n\n# %s\n' "$1" > "$f"
  fi
  printf '%s' "$f"
}

echo "=== the interface refuses what it must, and never invents a stamp"
NO_SESSION=$(note plain "")
for args in \
  "--event verified --at 2026-09-27T14:05 --words w" \
  "--note $NO_SESSION --at 2026-09-27T14:05 --words w" \
  "--note $NO_SESSION --event verified --words w" \
  "--note $NO_SESSION --event shouted --at 2026-09-27T14:05 --words w" \
  "--note $NO_SESSION --event verified --at yesterday --words w" \
  "--note $NO_SESSION --event verified --at 2026-9-27 --words w" \
  "--note /tmp/there-is-no-such-note.md --event verified --at 2026-09-27T14:05 --words w" ; do
  # shellcheck disable=SC2086
  if "$NOTIFY" $args --dry-run >/dev/null 2>&1; then
    fail "refuses: $args" "it was accepted"
  else
    pass "refuses: $args"
  fi
done
if "$NOTIFY" --note "$NO_SESSION" --event verified --at 2026-09-27T14:05 --words "his words" --dry-run >/dev/null 2>&1; then
  pass "accepts a complete call"
else
  fail "accepts a complete call" "it was refused"
fi

echo
echo "=== the ship map, from the note's path (dry run: it prints who it would tell)"
map_case() {  # map_case <label> <path-under-tmp> <expected captain fragment>
  local d="$TMP/$(dirname "$2")"
  mkdir -p "$d"
  printf -- '---\ntype: Task\nstatus: verified\n---\n' > "$TMP/$2"
  local out
  out=$("$NOTIFY" --note "$TMP/$2" --event verified --at 2026-09-27T14:05 --words w --dry-run 2>&1)
  case "$out" in
    *"$3"*) pass "$1 → $3" ;;
    *) fail "$1 → $3" "got: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-120)" ;;
  esac
}
map_case "a spec note under 00-09 System"      "00-09 System/01 System architecture/01.65.md"        "[C0-OB] obsidian"
map_case "an agent-config note (03.11)"        "00-09 System/03 Agents/03.11 Claude Code config/x.md" "[C0-CC] claude code"
map_case "a plugins note (03.12)"              "00-09 System/03 Agents/03.12 Claude Code plugins/x.md" "[C0-CC] claude code"
map_case "a memories note (03.17)"             "00-09 System/03 Agents/03.17 Claude Code memories/x.md" "[C0-CC] claude code"
map_case "an agent definition (03.18)"         "00-09 System/03 Agents/03.18 Claude Code agents/x.md"  "[C0-CC] claude code"
map_case "a note with no inferable ship"       "10-19 Personal/somewhere/x.md"                        "[A0] rear admiral"

echo
echo "=== the notice file and the wake, with a throwaway session named in the note"
if [ -z "$LT" ]; then
  skip "a notice is written for the session the note names"
  skip "a stopped session is woken with --by human:nelson"
  skip "the log line names the note and the verb"
else
  lt_name=$(claude agents --json --all 2>/dev/null | jq -r --arg i "$LT" '.[] | select(.id == $i or .sessionId == $i) | .name' | head -n 1)
  lt_sid=$(claude agents --json --all 2>/dev/null | jq -r --arg i "$LT" '.[] | select(.id == $i or .sessionId == $i) | .sessionId' | head -n 1)
  if [ -z "$lt_name" ]; then
    skip "a notice is written for the session the note names" "the throwaway $LT is not in the listing"
    skip "a stopped session is woken with --by human:nelson" "the throwaway $LT is not in the listing"
    skip "the log line names the note and the verb" "the throwaway $LT is not in the listing"
  else
    n1=$(note addressed "$lt_name")
    "$NOTIFY" --note "$n1" --event verified --at 2026-09-27T14:05 --words "looks right to me" >/dev/null 2>&1
    if [ -s "$NOTIFY_NOTICES_DIR/$lt_sid.md" ]; then pass "a notice is written for the session the note names"
    else fail "a notice is written for the session the note names" "no file at $NOTIFY_NOTICES_DIR/$lt_sid.md"; fi
    if grep -q 'was verified at 2026-09-27T14:05: looks right to me' "$NOTIFY_NOTICES_DIR/$lt_sid.md" 2>/dev/null; then
      pass "the notice carries the event, the stamp and his words"
    else fail "the notice carries the event, the stamp and his words" "$(head -1 "$NOTIFY_NOTICES_DIR/$lt_sid.md" 2>/dev/null)"; fi
    # THE BRANCH IS DECIDED BY THE LISTING, AND EACH ONE IS ASSERTED. This case used to pass whichever way
    # it went — a wake call passed under one label and no wake call passed under another — which is a case
    # that cannot fail and therefore measures nothing. What the notifier promises is narrower and testable:
    # a RUNNING session is never woken, because its next turn reads the notice; a STOPPED one is woken, with
    # `--by human:nelson` and its FULL sessionId. To run the stopped branch: `claude stop <id>` and leave its
    # row in the listing (no `claude rm`), then run this again. The wake script here is a fake that records
    # its arguments, so neither branch wakes anything.
    lt_status=$(claude agents --json --all 2>/dev/null | jq -r --arg i "$LT" '.[] | select(.id == $i or .sessionId == $i) | (.status // "stopped")' | head -n 1)
    calls=$(cat "$TMP/wake-calls.log" 2>/dev/null || true)
    case "$lt_status" in
      busy|idle)
        if [ -z "$calls" ]; then pass "a running session is NOT woken (its next turn reads the notice)"
        else fail "a running session is NOT woken (its next turn reads the notice)" "the wake script was called: $calls"; fi
        skip "a stopped session is woken with --by human:nelson and its full sessionId" "the throwaway is $lt_status; stop it, keep its row, and run this again" ;;
      *)
        case "$calls" in
          *"--by human:nelson"*"$lt_sid"*|*"$lt_sid"*"--by human:nelson"*)
            pass "a stopped session is woken with --by human:nelson and its full sessionId" ;;
          *) fail "a stopped session is woken with --by human:nelson and its full sessionId" "the wake call was: ${calls:-(none)}" ;;
        esac
        skip "a running session is NOT woken (its next turn reads the notice)" "the throwaway is stopped; run this again while one is idle" ;;
    esac
    if grep -q "$n1" "$NOTIFY_FLEET_LOG" 2>/dev/null && grep -q 'verified verb' "$NOTIFY_FLEET_LOG" 2>/dev/null; then
      pass "the log line names the note and the verb"
    else fail "the log line names the note and the verb" "$(tail -2 "$NOTIFY_FLEET_LOG" 2>/dev/null | tr '\n' ' ')"; fi
  fi
fi

echo
echo "=== no session matches: the captain is told, and this script never dispatches"
n2=$(note unmatched "[L0-XX] a session that does not exist")
out=$("$NOTIFY" --note "$n2" --event answered --at 2026-09-27T14:05 --words "answered" --dry-run 2>&1)
case "$out" in
  *"[A0] rear admiral"*) pass "an unmapped path with no matching session goes to the rear admiral" ;;
  *) fail "an unmapped path with no matching session goes to the rear admiral" "$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-140)" ;;
esac
# NOT a grep for the word "dispatch": the log line legitimately says "the captain dispatches, this script
# does not", so matching the word failed on the script saying the right thing. What matters is that it never
# ISSUES one, so the test looks for the flags a dispatch would carry.
case "$out" in
  *--agent*|*"claude --bg"*) fail "it never dispatches" "the output carries dispatch flags" ;;
  *) pass "it never dispatches" ;;
esac

echo
echo "=== the injecting hook: it delivers, it clears, and it never blocks a turn"
hook_with() {  # hook_with <json>; prints stdout, and the exit code on the last line
  printf '%s' "$1" | "$INJECT" 2>/dev/null; printf 'rc=%s' "$?"
}
sid=deadbeef-0000-0000-0000-000000000000
printf -- '- your item `x.md` was verified at 2026-09-27T14:05: fine by me\n' > "$NOTIFY_NOTICES_DIR/$sid.md"
out=$(hook_with "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$sid\"}")
case "$out" in *"fine by me"*) pass "a waiting notice is injected on UserPromptSubmit" ;; *) fail "a waiting notice is injected on UserPromptSubmit" "$out" ;; esac
case "$out" in *rc=0*) pass "it exits 0 when it injects" ;; *) fail "it exits 0 when it injects" "$out" ;; esac
if [ -e "$NOTIFY_NOTICES_DIR/$sid.md" ]; then fail "the notice is cleared after it is injected" "the file is still there"; else pass "the notice is cleared after it is injected"; fi
out=$(hook_with "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$sid\"}")
case "$out" in rc=0) pass "a second turn injects nothing and still exits 0" ;; *) fail "a second turn injects nothing and still exits 0" "$out" ;; esac

printf -- '- a notice for a resume\n' > "$NOTIFY_NOTICES_DIR/$sid.md"
out=$(hook_with "{\"hook_event_name\":\"SessionStart\",\"source\":\"resume\",\"session_id\":\"$sid\"}")
case "$out" in *"a notice for a resume"*) pass "a resume injects the notice" ;; *) fail "a resume injects the notice" "$out" ;; esac
printf -- '- a notice that must NOT be injected on a fresh start\n' > "$NOTIFY_NOTICES_DIR/$sid.md"
out=$(hook_with "{\"hook_event_name\":\"SessionStart\",\"source\":\"startup\",\"session_id\":\"$sid\"}")
case "$out" in rc=0) pass "a fresh start injects nothing (and the notice is kept)" ;; *) fail "a fresh start injects nothing" "$out" ;; esac
if [ -s "$NOTIFY_NOTICES_DIR/$sid.md" ]; then pass "the notice survives a fresh start"; else fail "the notice survives a fresh start" "it was cleared"; fi

echo
echo "=== the hook fails OPEN on everything, because it must never block a turn"
for bad in '' 'not json' '{}' '{"hook_event_name":"UserPromptSubmit"}' '{"session_id":"x"}' \
           '{"hook_event_name":"PreToolUse","session_id":"'"$sid"'"}' '[1,2,3]'; do
  out=$(hook_with "$bad")
  case "$out" in *rc=0*) pass "fails open on: ${bad:-(empty)}" ;; *) fail "fails open on: ${bad:-(empty)}" "$out" ;; esac
done
chmod 000 "$NOTIFY_NOTICES_DIR/$sid.md" 2>/dev/null || true
out=$(hook_with "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$sid\"}")
case "$out" in *rc=0*) pass "fails open on an unreadable notice" ;; *) fail "fails open on an unreadable notice" "$out" ;; esac
chmod 644 "$NOTIFY_NOTICES_DIR/$sid.md" 2>/dev/null || true

printf '\n%s cases, %s failed, %s skipped\n' "$n" "$fails" "$skips"
[ "$fails" = 0 ] || exit 1
