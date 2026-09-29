#!/usr/bin/env bash
# The start hook's disposition text (claude/hooks/cross-session-inject.py), on Nelson's ruling of 2026-09-29,
# relayed by [C0-CC] claude code: "so the agents are restating all of the cross session log messages in the
# chat. we need to make \"don't do that\" a memory and inform the agents". The text the hook puts in front of
# the unread entries must tell a session to dispose of them SILENTLY, and must not send replies to the log,
# which since 2026-09-26 carries claims, releases and rulings only.
#
# NOTHING HERE READS THE REAL LOG OR THE REAL STATE. HOME is a temp dir holding a fixture vault with one log
# entry stamped now, and the hook's state lands under that HOME. The real ~/obsidian is never opened.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
HOOK="$HERE/../../hooks/cross-session-inject.py"
n=0; fails=0
check() {  # check <label> <yes|no> <needle>: is the needle in the injected text?
  n=$((n + 1))
  local got=no
  case "$CTX" in *"$3"*) got=yes ;; esac
  if [ "$got" = "$2" ]; then printf 'PASS  %s\n' "$1"; else fails=$((fails + 1)); printf 'FAIL  %s (want %s, got %s)\n' "$1" "$2" "$got"; fi
}

T=$(mktemp -d "${TMPDIR:-/tmp}/inject-text.XXXXXX") || exit 1
trap '/usr/bin/trash "$T" 2>/dev/null || true' EXIT
LOGDIR="$T/obsidian/03.16 Cross-session log"; mkdir -p "$LOGDIR"
stamp=$(date +%Y-%m-%dT%H:%M)
printf -- '---\naudience: fleet\n---\n\n## %s · [L0-CC] fixture — claim\nA fixture entry. — [L0-CC] fixture\n' "$stamp" > "$LOGDIR/CROSS-SESSION.md"

out=$(printf '{"session_id":"inject-text-test"}' | HOME="$T" python3 "$HOOK")
CTX=$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' 2>/dev/null)

check "the fixture entry was injected (the test reads what it thinks it reads)" yes "A fixture entry."
check "the new text is there, word for word" yes "read each entry in full and dispose of it silently: act, reply by SendMessage, or dismiss. Do not restate entries in chat; say at most one line on what one changes for you."
check "a reply by SendMessage stays mandatory for your scope" yes "A reply by SendMessage is mandatory if an entry names your scope, files, or claims."
check "no reply in the log" no "reply in the log"
n=$((n + 1))
if [ -f "$T/.local/share/cross-session-hook/inject-text-test" ]; then echo "PASS  the state file landed under the temp HOME, not the real one"
else fails=$((fails + 1)); echo "FAIL  no state file under the temp HOME"; fi

EXPECTED=5
printf '\n%s checks (expected %s), %s failed\n' "$n" "$EXPECTED" "$fails"
[ "$n" = "$EXPECTED" ] || { echo "FAIL  the check count is $n, expected $EXPECTED"; exit 1; }
[ "$fails" = 0 ] || exit 1
