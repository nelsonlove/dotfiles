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
#   * the same behind `FOO=1` and wrappers (`env`, `nohup`, `nice -n 5`, `timeout 30`, `sudo -u x`, `xargs`
#     …), after `;`, `&&` or a newline even when stuck to a word, across a redirect, inside `$( )` and
#     backticks (quoted or not), a subshell, a heredoc fed to a shell, a shell's `-c` string, `eval` and
#     `env -S`, and with an attached value (`-n"[C0-DV] x"`, `-r<id>`).
# A heredoc body that goes to anything but a shell (`cat <<'EOF' >> notes.md`, `git commit -F -`) is text,
# and is not read. This is a tripwire, not a parser of every shell: it closes the shapes an agent writes.
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

def is_redirect(t):
    return t != "" and all(ch in "<>&" for ch in t) and ("<" in t or ">" in t)

def is_sep(t):
    return t != "" and all(ch in PUNCT or ch == "$" for ch in t) and not is_redirect(t)

def segments(tokens):
    # A redirect is NOT a split point: `claude --bg 2>/dev/null --name …` is one command. The operator, its
    # target and a file-descriptor number before it are dropped (review 2 of #73).
    cur, skip = [], False
    for t in tokens:
        if skip:
            skip = False
            continue
        if is_redirect(t):
            if cur and cur[-1].isdigit():
                cur.pop()
            skip = True
            continue
        if is_sep(t):
            if cur: yield cur
            cur = []
        else:
            # `out=$` before `(`: the `$` belongs to the separator, not to the word
            cur.append(t[:-1] if t.endswith("=$") else t)
    if cur: yield cur

def substitutions(line):
    # Every `$( … )` and backtick span, found in the raw text, so one inside double quotes is checked too
    # (shlex keeps a quoted string as one word). Nested spans are found when each inner string is checked.
    out, i, n = [], 0, len(line)
    while i < n:
        if line.startswith("$(", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if line[j] == "(": depth += 1
                elif line[j] == ")": depth -= 1
                j += 1
            out.append(line[i + 2:j - 1] if depth == 0 else line[i + 2:])
            i = j
        elif line[i] == "`":
            j = line.find("`", i + 1)
            if j < 0:
                out.append(line[i + 1:]); break
            out.append(line[i + 1:j]); i = j + 1
        else:
            i += 1
    return out

HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
def strip_text_heredocs(line):
    # A heredoc body is TEXT unless a shell reads it. `cat <<'EOF' >> notes.md` and `git commit -F - <<'EOF'`
    # carry prose, and prose that describes a DV start is not one (review 2 of #73). A body fed to bash, sh,
    # zsh, dash or eval stays, and is read as commands.
    lines, out, i = line.split("\n"), [], 0
    while i < len(lines):
        ln = lines[i]; out.append(ln); i += 1
        m = HEREDOC.search(ln)
        if not m:
            continue
        head = ln[:m.start()].split()
        words = [w for w in head if not ASSIGN.match(w)]
        prog = os.path.basename(words[0]) if words else ""
        if prog in SHELLS or prog == "eval":
            continue
        end = m.group(2)
        while i < len(lines) and lines[i].strip() != end:
            i += 1
        if i < len(lines):
            out.append(lines[i]); i += 1
    return "\n".join(out)

def check_claude(args):
    starts = "--bg" in args
    resumes = [a for a in args if a in ("--resume", "-r") or a.startswith("--resume=")
               or (a.startswith("-r") and not a.startswith("--") and len(a) > 2)]
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
        elif a.startswith("-n") and not a.startswith("--") and len(a) > 2:
            val = a[2:]
        if val is not None and DV.search(val):
            deny(REASON)
        ident = None
        if a.startswith("--resume="):
            ident = a.split("=", 1)[1]
        elif a in ("--resume", "-r") and k + 1 < len(args):
            ident = args[k + 1]
        elif a.startswith("-r") and not a.startswith("--") and len(a) > 2:
            ident = a[2:]
        if ident:
            if DV.search(ident):
                deny(REASON)
            nm = name_of(ident)
            if DV.search(nm):
                deny(REASON + f" (Session {ident} is listed as {nm!r}.)")

def check_segment(c, depth):
    if depth > 4:
        return
    i = 0
    while i < len(c) and ASSIGN.match(c[i]):
        i += 1
    if i >= len(c):
        return
    prog, args = os.path.basename(c[i]), c[i + 1:]
    if prog == "claude":
        check_claude(args)
    elif prog == "eval":
        check(" ".join(args), depth + 1)
    elif prog in WRAPPERS:
        # A wrapper and its own flags and values come first (`nice -n 5`, `timeout 30`, `env -u FOO`,
        # `sudo -u nelson`). The first word after it that runs something is checked as a command of its own,
        # so `nohup bash -c "…"` reaches the shell branch. `env -S "…"` hands a whole command line in one word.
        for j in range(len(args)):
            if prog == "env" and args[j] == "-S" and j + 1 < len(args):
                check(args[j + 1], depth + 1)
                return
            w = os.path.basename(args[j])
            if w == "claude" or w in SHELLS or w == "eval":
                check_segment(args[j:], depth + 1)
                return
    elif prog in SHELLS:
        # A shell's -c string is a command line of its own (`bash -c "claude …"`, `zsh -lc '…'`).
        for j, a in enumerate(args):
            if a.startswith("-") and not a.startswith("--") and "c" in a[1:] and j + 1 < len(args):
                check(args[j + 1], depth + 1)
                break

def check(line, depth=0):
    if depth > 4:
        return
    # Text heredocs go first, so prose inside one (backticks included) is never read as a substitution.
    line = strip_text_heredocs(line)
    for sub in substitutions(line):
        check(sub, depth + 1)
    try:
        segs = list(segments(tokenize(line)))
    except ValueError:
        # An unbalanced quote. Read it line by line instead, and skip a line that still does not parse: a
        # line the shell cannot parse starts no session.
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
