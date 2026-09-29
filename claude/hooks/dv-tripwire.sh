#!/bin/bash
# dv-tripwire.sh — PreToolUse[Bash]: refuse a command line that would start or resume a session on ship DV.
#
# Nelson's areas ruling (log 2026-09-29T03:35): 80-89 Divorce is guarded, and "its captain starts only when
# Nelson starts it". The fleet scripts refuse every caller for DV (`ship_refusal` in claude/bin/_fleet-ranks.sh),
# but a session does not need a script to start one: a bare `claude --bg --name "[C0-DV] …"` does it. This
# hook is the guard on that bare command line. It refuses:
#   * `claude … --bg …` or `claude … --resume …` / `-r` whose `--name` (or `-n`, `--name=`) is a `-DV]`
#     session, in any case; the free-text prompt is not read;
#   * `claude --resume <id>` / `-r <id>` / `--resume=<id>` where <id> (short or full) is a session whose
#     name in `claude agents --json --all` carries `-DV]`;
#   * the same behind `FOO=1` and wrappers (`env`, `nohup`, `nice -n 5`, `timeout 30`, `xargs` …), after
#     `;`, `&&` or a newline even when stuck to a word, inside `$( )`, backticks, a subshell, a heredoc fed
#     to a shell, and a shell's `-c` string.
# Nelson starts a DV session in his own terminal, where this hook does not run.
#
# WHAT IT CANNOT SEE. A SendMessage to a stopped DV session wakes it without any Bash command, so no Bash hook
# sees it; nothing guards SendMessage. `claude -c` / `--continue` resumes the latest conversation of the
# working directory without naming it, and is not checked. A line that does not parse is skipped.
#
# Fail-open on everything else: no `claude` word, bad JSON, or a listing that cannot be read lets the call
# through, because a tripwire that blocks unrelated work would be switched off, and then it guards nothing.

input=$(cat)
cmd=$(printf '%s' "$input" | /usr/bin/python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("tool_input",{}).get("command",""))
except Exception: pass' 2>/dev/null) || exit 0

# Fast path: the line never says `claude`, not even inside quotes (a shell's -c string is checked too).
printf '%s' "$cmd" | grep -q 'claude' || exit 0

TRIP_CMD="$cmd" /usr/bin/python3 - <<'PYEOF'
import json, os, re, shlex, subprocess, sys

cmd = os.environ.get("TRIP_CMD", "")
DV = re.compile(r"-dv\]", re.I)

def deny(reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason}}))
    sys.exit(0)

REASON = ("refused by the DV tripwire: ship DV (80-89 Divorce) is guarded, and its sessions start only when "
          "Nelson starts them (areas ruling, 2026-09-29). No agent starts or resumes a DV session.")

# Split on newlines and on ; & | ( ) < > ` { } even when they touch a word, so `cd x; claude`, `a&&claude`,
# `$(claude …)`, a subshell and a heredoc body fed to a shell all come apart into commands (review 1 of #73).
PUNCT = "();<>|&\n`{}"
WRAPPERS = {"env", "nohup", "exec", "command", "time", "caffeinate", "sudo", "nice", "timeout", "gtimeout",
            "xargs", "stdbuf", "doas"}
SHELLS = {"bash", "sh", "zsh", "dash"}
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")

listing = None
def name_of(ident):
    global listing
    if listing is None:
        try:
            out = subprocess.run(["claude", "agents", "--json", "--all"], capture_output=True, text=True, timeout=8).stdout
            listing = json.loads(out) if out.strip() else []
        except Exception:
            listing = []
    for row in listing if isinstance(listing, list) else []:
        if ident in (row.get("id"), row.get("sessionId")):
            return row.get("name") or ""
    return ""

def tokenize(line):
    lex = shlex.shlex(line, posix=True, punctuation_chars=PUNCT)
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    return list(lex)

def is_sep(t):
    return t != "" and all(ch in PUNCT or ch == "$" for ch in t)

def segments(tokens):
    cur = []
    for t in tokens:
        if is_sep(t):
            if cur: yield cur
            cur = []
        else:
            # `out=$` before `(`: the `$` belongs to the separator, not to the word
            cur.append(t[:-1] if t.endswith("=$") else t)
    if cur: yield cur

def check_claude(args):
    starts = "--bg" in args
    resumes = [a for a in args if a in ("--resume", "-r") or a.startswith("--resume=")]
    if not (starts or resumes):
        return
    # Only a NAME or a RESUMED ID counts. The free-text prompt is not a name: a brief that mentions
    # `[C0-DV]` to leave it alone is not a DV start (review 1 of #73).
    for k, a in enumerate(args):
        val = None
        if a in ("--name", "-n") and k + 1 < len(args):
            val = args[k + 1]
        elif a.startswith("--name="):
            val = a.split("=", 1)[1]
        if val is not None and DV.search(val):
            deny(REASON)
        ident = None
        if a.startswith("--resume="):
            ident = a.split("=", 1)[1]
        elif a in ("--resume", "-r") and k + 1 < len(args):
            ident = args[k + 1]
        if ident:
            if DV.search(ident):
                deny(REASON)
            nm = name_of(ident)
            if DV.search(nm):
                deny(REASON + f" (Session {ident} is listed as {nm!r}.)")

def check_segment(c, depth):
    i = 0
    while i < len(c) and ASSIGN.match(c[i]):
        i += 1
    if i >= len(c):
        return
    prog = os.path.basename(c[i])
    if prog == "claude":
        check_claude(c[i + 1:])
    elif prog in WRAPPERS:
        # A wrapper and its own flags and values come first (`nice -n 5`, `timeout 30`, `env -u FOO`); the
        # first `claude` word after it is the command it runs.
        for j in range(i + 1, len(c)):
            if os.path.basename(c[j]) == "claude":
                check_claude(c[j + 1:])
                break
    elif prog in SHELLS and depth < 3:
        # A shell's -c string is a command line of its own (`bash -c "claude …"`, `zsh -lc '…'`).
        args = c[i + 1:]
        for j, a in enumerate(args):
            if a.startswith("-") and not a.startswith("--") and "c" in a[1:] and j + 1 < len(args):
                check(args[j + 1], depth + 1)
                break

def check(line, depth=0):
    try:
        segs = list(segments(tokenize(line)))
    except ValueError:
        # An unbalanced quote, most often an apostrophe in a heredoc body. Read it line by line instead, and
        # skip a line that still does not parse: a line the shell cannot parse starts no session.
        segs = []
        for part in line.split("\n"):
            try:
                segs.extend(segments(tokenize(part)))
            except ValueError:
                continue
    for c in segs:
        check_segment(c, depth)

check(cmd)
sys.exit(0)
PYEOF
