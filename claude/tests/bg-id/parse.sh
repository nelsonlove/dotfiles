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
gives "a 'resumed as' note that agrees" 0badcafe < <(printf 'note: resumed as 0badcafe.\nbackgrounded · 0badcafe · [L0-CC] x\n')
gives "a hex word in the name is not the id" 1234abcd < <(printf 'backgrounded · 1234abcd · [L0-CC] deadbeef\n')
gives "no name after the id" 1234abcd < <(printf 'backgrounded · 1234abcd\n')
refuses "a no-id form" "no id" < <(printf 'Error: something went wrong\n')
refuses "empty output" "no id" < <(printf '')
refuses "a copy note and a backgrounded line that disagree" "different ids" < <(printf 'note: this started a copy as 11111111.\nbackgrounded · 22222222 · [L0-CC] x\n')
refuses "two backgrounded lines with two ids" "different ids" < <(printf 'backgrounded · 11111111 · a\nbackgrounded · 22222222 · b\n')
refuses "a backgrounded line with no hex id" "no 8-hex id" < <(printf 'backgrounded · nothexid · [L0-CC] x\n')
refuses "a short hex token" "no 8-hex id" < <(printf 'backgrounded · abc123 · [L0-CC] x\n')

echo
echo "=== 3. sourced, and used by both scripts"
got=$(bash -c '. "$1"; printf "backgrounded · 9abcdef0\n" | bg_id' _ "$LIB" 2>&1)
if [ "$got" = 9abcdef0 ]; then pass "sourced, bg_id works as a function"; else fail "sourced, bg_id works as a function" "got '$got'"; fi
for s in promote-session.sh wake-session.sh; do
  if grep -q 'lib/bg-id.sh' "$BIN/$s" && grep -q '| bg_id' "$BIN/$s"; then pass "$s reads the id through bg_id"; else fail "$s reads the id through bg_id" "no bg_id use"; fi
  if grep -qE "awk '/\^backgrounded/" "$BIN/$s"; then fail "$s has no parser of its own left" "an awk /^backgrounded/ parser remains"; else pass "$s has no parser of its own left"; fi
done

EXPECTED=21
[ "$n" = "$EXPECTED" ] || { fails=$((fails + 1)); echo "FAIL  the check count is $n, expected $EXPECTED"; }
printf '\n%s checks (expected %s), %s failed\n' "$n" "$EXPECTED" "$fails"
[ "$fails" = 0 ] || exit 1
