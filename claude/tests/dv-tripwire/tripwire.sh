#!/usr/bin/env bash
# The DV tripwire, `claude/hooks/dv-tripwire.sh`, fed Bash tool calls as JSON on stdin, the way Claude Code
# calls a PreToolUse hook. It must refuse a `claude --bg` or `claude … --resume` command line that names a
# `-DV]` session, by name on the line or through the id it resumes, and let everything else through.
#
# WHAT IT CANNOT SEE: a SendMessage to a stopped DV session wakes it without any Bash command, so no Bash
# hook can see it. This suite proves the command-line guard only.
#
# The id lookup runs `claude agents --json --all`; here `claude` is a stub on PATH that prints a fixture
# listing, so nothing reads the live fleet.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
HOOK="$HERE/../../hooks/dv-tripwire.sh"
n=0; fails=0
T=$(mktemp -d "${TMPDIR:-/tmp}/dv-tripwire.XXXXXX") || exit 1
trap 'trash "$T" 2>/dev/null || rm -rf "$T"' EXIT
mkdir -p "$T/stubbin"
DVID=dddddddd-0000-0000-0000-000000000000
CCID=cccccccc-0000-0000-0000-000000000000
cat > "$T/listing.json" <<JSON
[{"id":"dddddddd","sessionId":"$DVID","name":"[C0-DV] divorce"},
 {"id":"cccccccc","sessionId":"$CCID","name":"[L0-CC] dotfiles"}]
JSON
printf '#!/bin/sh\ncat "%s"\n' "$T/listing.json" > "$T/stubbin/claude"; chmod +x "$T/stubbin/claude"

decide() {  # decide <command>: prints deny or allow
  local json out
  json=$(CMD="$1" /usr/bin/python3 -c 'import json,os; print(json.dumps({"tool_name":"Bash","tool_input":{"command":os.environ["CMD"]}}))')
  out=$(printf '%s' "$json" | PATH="$T/stubbin:$PATH" bash "$HOOK" 2>/dev/null)
  case "$out" in *'"permissionDecision": "deny"'*|*'"permissionDecision":"deny"'*) echo deny ;; *) echo allow ;; esac
}
case_() {  # case_ <want> <command>
  n=$((n + 1)); local got; got=$(decide "$2")
  if [ "$got" = "$1" ]; then printf 'PASS  %-5s %s\n' "$1" "$2"
  else fails=$((fails + 1)); printf 'FAIL  %-5s %s   (got %s)\n' "$1" "$2" "$got"; fi
}

echo "=== refused: a DV session named on the line"
case_ deny  'claude --bg --agent captain --name "[C0-DV] divorce" "start"'
case_ deny  "claude --bg --agent lieutenant --name '[L0-DV] evidence' x"
case_ deny  'cd /tmp && claude --bg --name "[C2-DV] x" y'
case_ deny  'claude --resume abc --name "[C0-DV] divorce"'
case_ deny  '/opt/homebrew/bin/claude --bg --name "[C1-DV] x" y'
case_ deny  'claude --bg --name "[c0-dv] lower" y'
case_ deny  'nohup claude --bg --name "[C0-DV] x" y &'
case_ deny  'FOO=1 claude --bg --name "[C0-DV] x" y'
case_ deny  'env FOO=1 claude --bg --name "[C0-DV] x" y'
case_ deny  'bash -c "claude --bg --name \"[C0-DV] x\" y"'
case_ deny  "zsh -lc 'claude --resume $DVID'"
echo
echo "=== refused: a DV session reached through the id it resumes"
case_ deny  "claude --resume $DVID"
case_ deny  "claude -r $DVID"
case_ deny  "claude --resume dddddddd"
case_ deny  "claude --resume=$DVID"
echo
echo "=== allowed"
case_ allow 'claude --bg --agent lieutenant --name "[L0-CC] dotfiles" x'
case_ allow "claude --resume $CCID"
case_ allow 'claude agents --json --all'
case_ allow 'grep -n "\-DV\]" notes.md'
case_ allow 'echo "[C0-DV] divorce is the guarded captain"'
case_ allow 'git commit -m "claude --bg names [C0-DV] in a message"'
case_ allow 'ls ~/obsidian/"80-89 Divorce"'
case_ allow ''

printf '\n%s checks, %s failed\n' "$n" "$fails"
EXPECTED=23
[ "$n" = "$EXPECTED" ] || { echo "FAIL  the check count is $n, expected $EXPECTED"; exit 1; }
[ "$fails" = 0 ] || exit 1
