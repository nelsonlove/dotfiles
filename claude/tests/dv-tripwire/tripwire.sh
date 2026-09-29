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
trap '/usr/bin/trash "$T" 2>/dev/null || true' EXIT
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
# Review 1 of #73 proved each of these got past: separators stuck to words, newlines, substitutions,
# subshells, heredocs fed to a shell, and wrappers that take a value.
case_ deny  'cd /tmp; claude --bg --name "[C0-DV] x" y'
case_ deny  'true&&claude --bg --name "[C0-DV] x" y'
case_ deny  $'cd /tmp\nclaude --bg --name "[C0-DV] x" y'
case_ deny  'out=$(claude --bg --name "[C0-DV] x" y)'
case_ deny  'out=`claude --bg --name "[C0-DV] x" y`'
case_ deny  '(claude --bg --name "[C0-DV] x" y)'
case_ deny  $'bash <<EOF\nclaude --bg --name "[C0-DV] x" y\nEOF'
case_ deny  'nice -n 5 claude --bg --name "[C0-DV] x" y'
case_ deny  'env -u FOO claude --bg --name "[C0-DV] x" y'
case_ deny  'timeout 30 claude --bg --name "[C0-DV] x" y'
case_ deny  'claude --bg --name="[C0-DV] x" y'
# Review 2 of #73: redirects, quoted substitutions, shells behind wrappers, eval, env -S, attached values.
case_ deny  'claude --bg 2>/dev/null --name "[C0-DV] x" y'
case_ deny  'claude --bg </dev/null --name "[C0-DV] x" y'
case_ deny  "out=\"\$(claude --bg --name '[C0-DV] x' y)\""
case_ deny  'echo "$(claude --bg --name "[C0-DV] x" y)"'
case_ deny  "nohup bash -c \"claude --bg --name '[C0-DV] x' y\" &"
case_ deny  "sudo -u nelson sh -c \"claude --bg --name '[C0-DV] x' y\""
case_ deny  "eval \"claude --bg --name '[C0-DV] x' y\""
case_ deny  "env -S \"claude --bg --name '[C0-DV] x' y\""
case_ deny  'claude --bg -n"[C0-DV] x" y'
# Review 3 of #73: a heredoc fed to a shell by `&&`, a pipe or a wrapper; an unquoted body expands `$( )`;
# a herestring or a pipe into a shell; env's long and attached -S.
case_ deny  $'cd /tmp && bash <<\'EOF\'\nclaude --bg --name "[C0-DV] x" y\nEOF'
case_ deny  $'cat <<\'EOF\' | bash\nclaude --bg --name "[C0-DV] x" y\nEOF'
case_ deny  $'nohup bash <<\'EOF\'\nclaude --bg --name "[C0-DV] x" y\nEOF'
case_ deny  $'sudo bash <<EOF\nclaude --bg --name "[C0-DV] x" y\nEOF'
case_ deny  $'cat <<EOF\n$(claude --bg --name "[C0-DV] x" y)\nEOF'
case_ deny  "bash <<< \"claude --bg --name '[C0-DV] x' y\""
case_ deny  "echo 'claude --bg --name \"[C0-DV] x\" y' | bash"
case_ deny  "env --split-string=\"claude --bg --name '[C0-DV] x' y\""
case_ deny  "env -S'claude --bg --name [C0-DV]x y'"
# Review 4 of #73: quotes are plain text in a heredoc body, and `#` starts a comment.
case_ deny  $'cat <<EOF >> n.md\nNelson\'s note: $(claude --bg --name "[C0-DV] x" y)\nEOF'
case_ deny  $'echo hi # it\'s fine\necho "$(claude --bg --name \'[C0-DV] x\' y)"'
# Review 5 of #73: a quoted `)` inside `$( )` does not end it.
case_ deny  'echo "$(printf ")"; claude --bg --name "[C0-DV] x" y)"'
echo
echo "=== refused: a DV session reached through the id it resumes"
case_ deny  "claude --resume $DVID"
case_ deny  "claude -r $DVID"
case_ deny  "claude -r$DVID"
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
# The free-text prompt is not a name: a brief that mentions DV in order to leave it alone is not a DV start.
case_ allow 'claude --bg --agent lieutenant --name "[L0-CC] t" "leave [C0-DV] alone"'
# A heredoc append whose body mentions DV and has an apostrophe starts no session.
case_ allow $'cat <<\'EOF\' >> ~/.claude/notes.md\nNelson\'s ruling: [C0-DV] divorce is guarded\nEOF'
case_ allow 'echo claude --bg --name "[C0-DV] x"'
# Review 2 of #73: a heredoc body that goes to a program that is not a shell is text, not commands.
case_ allow $'cat <<\'EOF\' >> notes.md\nA bare `claude --bg --name "[C0-DV] x"` starts one\nEOF'
case_ allow $'git commit -F - <<\'EOF\'\nclaude --bg --name "[C0-DV] x" is refused\nEOF'
case_ allow 'claude --bg 2>/dev/null --name "[L0-CC] x" y'
# Review 3 of #73: inside single quotes `$( )` and backticks are text, and a quoted heredoc body is inert.
case_ allow "echo 'see \`claude --bg --name \"[C0-DV] x\"\` in docs' >> notes.md"
case_ allow "printf '%s\\n' '\$(claude --bg --name \"[C0-DV] x\")' >> notes.md"
case_ allow $'cat <<\'EOF\' > x.md\n$(claude --bg --name "[C0-DV] x" y)\nEOF'
case_ allow ''

printf '\n%s checks, %s failed\n' "$n" "$fails"
EXPECTED=65
[ "$n" = "$EXPECTED" ] || { echo "FAIL  the check count is $n, expected $EXPECTED"; exit 1; }
[ "$fails" = 0 ] || exit 1
