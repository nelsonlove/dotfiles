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

# THE CALLER. The hook lets a DV start through only for the session its registry records as `[A0] areas admiral`
# with agent `admiral`. The registry here is a FIXTURE directory under $T, reached through the hook's test-only
# seam DV_TRIPWIRE_SESSIONS_DIR (honoured only under a temp directory); the real ~/.claude/sessions is never read.
# CALLER is the session_id the hook is given; the default is a caller with no record, so every case above the
# caller section is a non-admiral caller.
SESS="$T/sessions"; mkdir -p "$SESS"
AAID=aaaaaaaa-0000-0000-0000-000000000000   # the areas admiral, both keys right
NAID=aaaaaaa1-0000-0000-0000-000000000000   # the areas admiral's name, agent null (the real one, measured 2026-09-30)
RAID=bbbbbbbb-0000-0000-0000-000000000000   # the rear admiral
C0ID=c0c0c0c0-0000-0000-0000-000000000000   # a captain
TWID=aaaaaaa2-0000-0000-0000-000000000000   # two records: one right, one renamed
NKID=aaaaaaa3-0000-0000-0000-000000000000   # the areas admiral's name with no agent key at all
rec() { printf '%s\n' "$2" > "$SESS/$1.json"; }
rec 101 "{\"sessionId\":\"$AAID\",\"name\":\"[A0] areas admiral\",\"agent\":\"admiral\",\"kind\":\"bg\"}"
rec 102 "{\"sessionId\":\"$NAID\",\"name\":\"[A0] areas admiral\",\"nameSource\":\"peer\",\"agent\":null,\"kind\":\"bg\"}"
rec 103 "{\"sessionId\":\"$RAID\",\"name\":\"[A0] rear admiral\",\"agent\":\"admiral\",\"kind\":\"bg\"}"
rec 104 "{\"sessionId\":\"$C0ID\",\"name\":\"[C0-PE] personal\",\"agent\":\"captain\",\"kind\":\"bg\"}"
rec 105 "{\"sessionId\":\"$TWID\",\"name\":\"[A0] areas admiral\",\"agent\":\"admiral\"}"
rec 106 "{\"sessionId\":\"$TWID\",\"name\":\"[L0-PE] renamed\",\"agent\":\"admiral\"}"
rec 107 "{\"sessionId\":\"$NKID\",\"name\":\"[A0] areas admiral\"}"
printf 'not json' > "$SESS/108.json"
CALLER=""; SESSDIR="$SESS"

decide() {  # decide <command>: prints deny or allow, for the caller $CALLER and the registry $SESSDIR
  local json out
  json=$(CMD="$1" SID="$CALLER" /usr/bin/python3 -c 'import json,os; d={"tool_name":"Bash","tool_input":{"command":os.environ["CMD"]}}
if os.environ["SID"]: d["session_id"]=os.environ["SID"]
print(json.dumps(d))')
  out=$(printf '%s' "$json" | DV_TRIPWIRE_SESSIONS_DIR="$SESSDIR" PATH="$T/stubbin:$PATH" bash "$HOOK" 2>/dev/null)
  case "$out" in *'"permissionDecision": "deny"'*|*'"permissionDecision":"deny"'*) echo deny ;; *) echo allow ;; esac
}
case_() {  # case_ <want> <command>
  n=$((n + 1)); local got; got=$(decide "$2")
  if [ "$got" = "$1" ]; then printf 'PASS  %-5s %s\n' "$1" "$2"
  else fails=$((fails + 1)); printf 'FAIL  %-5s %s   (got %s)\n' "$1" "$2" "$got"; fi
}
# known_limit <command>: a DV start the hook is KNOWN to let through. Counted apart, never as a pass; the day the hook refuses it, this fails, so move it to the deny list and out of the header's limits.
known=0
known_limit() {
  n=$((n + 1)); local got; got=$(decide "$1")
  if [ "$got" = allow ]; then known=$((known + 1)); printf 'KNOWN-LIMIT  let through, as the header says: %s\n' "$1"
  else fails=$((fails + 1)); printf 'FAIL  a known limit is now refused, so it is fixed: move it to the deny list: %s\n' "$1"; fi
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
# Review 2 of #86: the file system ignores case, and bash joins a quoted or escaped name back together.
case_ deny  'Claude --bg --name "[C0-DV] x" y'
case_ deny  'CLAUDE --bg --name "[C0-DV] x" y'
case_ deny  'c\laude --bg --name "[C0-DV] x" y'
case_ deny  'cl""aude --bg --name "[C0-DV] x" y'
case_ deny  "'cl'aude --bg --name \"[C0-DV] x\" y"
# Review 3 of #86: a program the shell builds from ANSI-C quotes, a substitution, or a glob.
case_ deny  "\$'claude' --bg --name \"[C0-DV] x\" y"
case_ deny  "\$'\\x63laude' --bg --name \"[C0-DV] x\" y"
case_ deny  "claude --bg --name \$'[C0-\\x44V] x' y"
case_ deny  '"$(command -v claude)" --bg --name "[C0-DV] x" y'
case_ deny  '$(echo claude) --bg --name "[C0-DV] x" y'
case_ deny  '`echo claude` --bg --name "[C0-DV] x" y'
case_ deny  '/opt/homebrew/bin/claud* --bg --name "[C0-DV] x" y'
case_ deny  '/opt/homebrew/bin/cl[a]ude --bg --name "[C0-DV] x" y'
# Review 4 of #86: a glob with no "cl" or "ude" in it, and an apostrophe earlier on the line.
case_ deny  '/opt/homebrew/bin/c*de --bg --name "[C0-DV] x" y'
case_ deny  '/opt/homebrew/bin/c?a?d? --bg --name "[C0-DV] x" y'
case_ deny  'echo "it'"'"'s"; "$(command -v claude)" --bg --name "[C0-DV] x" y'
case_ deny  $'# it\'s\n$(echo claude) --bg --name "[C0-DV] x" y'
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
# KNOWN LIMITS, found by the DV soak of 2026-09-29 and the review of #86: the hook reads the command's text and does not run the shell, so it cannot see a name or a program built by the shell.
known_limit "n='[L0-DV] var'; claude --bg --name \"\$n\" y"
known_limit "c=claude; \$c --bg --name \"[C0-DV] x\" y"
# A substitution that runs claude for its output is not a start.
case_ allow 'x=$(claude agents --json --all); echo "$x" | jq length'
case_ allow 'echo "$(claude --version)"'
case_ allow ''

echo
echo "=== the caller: only the session registered as [A0] areas admiral with agent admiral starts or resumes DV"
DVSTART='claude --bg --agent captain --name "[C0-DV] divorce" "start"'
DVRESUME="claude --bg --resume $DVID"
DVRESUME_BYNAME='claude --resume abc --name "[C0-DV] divorce"'
CALLER=$AAID
case_ allow "$DVSTART"
case_ allow "$DVRESUME"
case_ allow "$DVRESUME_BYNAME"
case_ allow "bash -c 'claude --resume $DVID'"
case_ allow 'claude --bg --name "[C0-PE] personal" x'   # its own ships, as before
CALLER=$NAID;  case_ deny "$DVSTART"; case_ deny "$DVRESUME"   # the name without agent admiral
CALLER=$NKID;  case_ deny "$DVSTART"                           # the name with no agent key
CALLER=$RAID;  case_ deny "$DVSTART"; case_ deny "$DVRESUME"   # the rear admiral
CALLER=$C0ID;  case_ deny "$DVSTART"; case_ deny "$DVRESUME"   # a captain
CALLER=ffffffff-0000-0000-0000-000000000000; case_ deny "$DVSTART"   # no record: an unknown caller
CALLER=$TWID;  case_ deny "$DVSTART"                           # two records that disagree
CALLER="";     case_ deny "$DVSTART"                           # no session_id at all
# The registry itself: unreadable, missing, or outside the seam's leash. Each is a refusal (fail closed).
CALLER=$AAID
SESSDIR="$T/no-such-dir";       case_ deny "$DVSTART"
mkdir -p "$T/locked"; cp "$SESS/101.json" "$T/locked/"; chmod 000 "$T/locked"
SESSDIR="$T/locked";            case_ deny "$DVSTART"
chmod 700 "$T/locked"
mkdir -p "$HOME/.dv-tripwire-leash-test.$$" && cp "$SESS/101.json" "$HOME/.dv-tripwire-leash-test.$$/"
SESSDIR="$HOME/.dv-tripwire-leash-test.$$"; case_ deny "$DVSTART"   # outside a temp dir: the seam is not honoured
/usr/bin/trash "$HOME/.dv-tripwire-leash-test.$$" 2>/dev/null || true
SESSDIR="$SESS"; CALLER=""
# The refusal names the one allowed caller.
n=$((n + 1))
why=$(printf '{"tool_input":{"command":"claude --bg --name \\"[C0-DV] x\\" y"}}' | DV_TRIPWIRE_SESSIONS_DIR="$SESS" PATH="$T/stubbin:$PATH" bash "$HOOK" 2>/dev/null)
case "$why" in *"[A0] areas admiral"*"admiral"*) printf 'PASS  the refusal names the one allowed caller\n' ;;
  *) fails=$((fails + 1)); printf 'FAIL  the refusal does not name the allowed caller: %s\n' "$why" ;; esac

echo
echo "=== registered: the REPO's claude/settings.json runs the hook on every Bash call (the live ~/.claude/settings.json is whatever the main checkout holds)"
n=$((n + 1))
reg=$(python3 - "$HERE/../../settings.json" <<'PYX'
import json, sys
d = json.load(open(sys.argv[1]))
hits = [h for e in d.get("hooks", {}).get("PreToolUse", []) if e.get("matcher") == "Bash"
        for h in e.get("hooks", []) if h.get("command") == "/Users/nelson/.claude/hooks/dv-tripwire.sh"]
print("ok" if len(hits) == 1 and hits[0].get("type") == "command" and isinstance(hits[0].get("timeout"), int) and 1 <= hits[0]["timeout"] <= 10 else "missing or wrong: %r" % hits)
PYX
)
if [ "$reg" = ok ]; then printf 'PASS  the repo settings.json has one Bash PreToolUse entry for dv-tripwire.sh, timeout 1-10 s\n'; else fails=$((fails + 1)); printf 'FAIL  settings.json: %s\n' "$reg"; fi

printf '\n%s checks, %s failed, %s known limits let through\n' "$n" "$fails" "$known"
EXPECTED=106
[ "$n" = "$EXPECTED" ] || { echo "FAIL  the check count is $n, expected $EXPECTED"; exit 1; }
[ "$fails" = 0 ] || exit 1
