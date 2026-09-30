#!/usr/bin/env bash
# claude/lib/bg-id.sh: the one parser of `claude --bg` output. The fixtures are real output, measured 2026-09-29 on throwaways that were then stopped and removed (see bg-id.sh's header); the rest are built forms that must pass or must fail.
#
# Run: bash claude/tests/bg-id/parse.sh   (prints the check count; exits non-zero on any failure)
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
LIB="$HERE/../../lib/bg-id.sh"
FIX="$HERE/fixtures"
BIN="$HERE/../../bin"
n=0; fails=0
pass() { n=$((n + 1)); printf 'PASS  %s\n' "$1"; }
fail() { n=$((n + 1)); fails=$((fails + 1)); printf 'FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; }
T=$(mktemp -d "${TMPDIR:-/tmp}/bg-id-test.XXXXXX") || exit 1
trap '/usr/bin/trash "$T" 2>/dev/null || true' EXIT

# Each case reads its input by redirection, never from a pipe: a pipe would run the case in a subshell and lose its count.
gives() {  # gives <label> <expected id> : stdin is the output
  local out rc
  out=$(bash "$LIB" 2>"$T/err"); rc=$?
  if [ "$rc" = 0 ] && [ "$out" = "$2" ]; then pass "$1 -> $2"; else fail "$1" "rc $rc, got '$out', stderr: $(head -c 200 "$T/err")"; fi
}
refuses() {  # refuses <label> <word the message must hold> : stdin is the output
  local out rc
  out=$(bash "$LIB" 2>"$T/err"); rc=$?
  if [ "$rc" != 0 ] && [ -z "$out" ] && grep -q -- "$2" "$T/err"; then pass "$1 is refused, loudly"; else fail "$1 is refused, loudly" "rc $rc, stdout '$out', stderr: $(head -c 200 "$T/err")"; fi
}

echo "=== 1. the real output"
if [ -f "$LIB" ]; then
  gives "a fresh start (piped, colour codes and all)" 2dae6ecc < "$FIX/fresh.out"
  gives "a fresh start under a tty (^D, backspaces, CR)" 05ab1bf4 < "$FIX/fresh-tty.out"
  gives "a resume of a stopped session (woke note)" 2dae6ecc < "$FIX/resume-stopped.out"
  gives "a resume of a running session (copy note)" 61efac93 < "$FIX/resume-running-copy.out"
  gives "a resume with flags (copy note, new name)" 236a4f0e < "$FIX/resume-flags-copy.out"
else
  fail "the parser exists at claude/lib/bg-id.sh" "none"
fi

echo
echo "=== 2. built forms"
E=$'\033'
gives "an ANSI-coloured line" abcdef12 < <(printf 'backgrounded · %s[36mabcdef12%s[39m · [L0-CC] x\n' "$E" "$E")
gives "a CR form" abcdef12 < <(printf 'backgrounded · abcdef12 · [L0-CC] x\r\n  claude attach abcdef12\r\n')
gives "a 'resumed as' phrase is not read (the CLI prints none)" 0badcafe < <(printf 'note: resumed as 11111111.\nbackgrounded · 0badcafe · [L0-CC] x\n')
gives "a copy phrase inside the NAME is not read" 1234abcd < <(printf 'backgrounded · 1234abcd · [L0-CC] started a copy as deadbeef\n')
gives "a 6-hex id is an id" abc123 < <(printf 'backgrounded · abc123 · [L0-CC] x\n')
gives "a longer hex id is an id" 0123456789ab < <(printf 'backgrounded · 0123456789ab · [L0-CC] x\n')
gives "a hex word in the name is not the id" 1234abcd < <(printf 'backgrounded · 1234abcd · [L0-CC] deadbeef\n')
gives "no name after the id" 1234abcd < <(printf 'backgrounded · 1234abcd\n')
refuses "a no-id form" "no id" < <(printf 'Error: something went wrong\n')
refuses "empty output" "no id" < <(printf '')
refuses "a copy note and a backgrounded line that disagree" "different ids" < <(printf 'note: this started a copy as 11111111.\nbackgrounded · 22222222 · [L0-CC] x\n')
refuses "two backgrounded lines with two ids" "different ids" < <(printf 'backgrounded · 11111111 · a\nbackgrounded · 22222222 · b\n')
refuses "a backgrounded line with no hex id" "no hex id" < <(printf 'backgrounded · nothexid · [L0-CC] x\n')
refuses "a 5-hex token" "no hex id" < <(printf 'backgrounded · abc12 · [L0-CC] x\n')

echo
echo "=== 3. sourced, and used by both scripts"
got=$(bash -c '. "$1"; printf "backgrounded · 9abcdef0\n" | bg_id' _ "$LIB" 2>&1)
if [ "$got" = 9abcdef0 ]; then pass "sourced, bg_id works as a function"; else fail "sourced, bg_id works as a function" "got '$got'"; fi
probe() {  # probe <input>: run bg_parse sourced, print "rc NEW COPY"
  bash -c '. "$1"; bg_parse <<<"$2"; rc=$?; printf "%s %s %s" "$rc" "${BG_NEW:--}" "${BG_COPY:--}"' _ "$LIB" "$1"
}
got=$(probe "$(cat "$FIX/resume-running-copy.out")")
if [ "$got" = "0 61efac93 61efac93" ]; then pass "bg_parse on a real copy: new and copy ids"; else fail "bg_parse on a real copy" "got '$got'"; fi
got=$(probe "$(cat "$FIX/resume-flags-copy.out")")
if [ "$got" = "0 236a4f0e 236a4f0e" ]; then pass "bg_parse on a real flags copy: new and copy ids"; else fail "bg_parse on a real flags copy" "got '$got'"; fi
got=$(probe "$(printf 'note: session 05ab1bf4 is already running in the background, so this started a copy as 61efac93.\nbackgrounded • 61efac93\n')")
if [ "$got" = "1 - 61efac93" ]; then pass "bg_parse gives the copy id even when the backgrounded line cannot be read"; else fail "bg_parse gives the copy id even when the backgrounded line cannot be read" "got '$got'"; fi
if grep -q 'lib/bg-id.sh' "$BIN/promote-session.sh" && grep -q '| bg_id)' "$BIN/promote-session.sh"; then pass "promote-session.sh reads the id through bg_id"; else fail "promote-session.sh reads the id through bg_id" "no bg_id use"; fi
if grep -q 'lib/bg-id.sh' "$BIN/wake-session.sh" && grep -q 'bg_parse <<<"$out"' "$BIN/wake-session.sh"; then pass "wake-session.sh reads the ids through bg_parse"; else fail "wake-session.sh reads the ids through bg_parse" "no bg_parse use"; fi
for s in promote-session.sh wake-session.sh; do
  if grep -qE "awk '/\^backgrounded/|started a copy as \(" "$BIN/$s"; then fail "$s has no parser of its own left" "an own backgrounded or copy parser remains"; else pass "$s has no parser of its own left"; fi
done

EXPECTED=27
[ "$n" = "$EXPECTED" ] || { fails=$((fails + 1)); echo "FAIL  the check count is $n, expected $EXPECTED"; }
printf '\n%s checks (expected %s), %s failed\n' "$n" "$EXPECTED" "$fails"
[ "$fails" = 0 ] || exit 1
