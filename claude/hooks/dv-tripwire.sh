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
#     backticks (in double quotes or none; single quotes are text), a subshell, a heredoc or herestring a
#     shell reads (after `&&`, through a pipe, behind a wrapper), `echo … | bash`, a shell's `-c` string,
#     `eval`, `env -S` / `--split-string`, and with an attached value (`-n"[C0-DV] x"`, `-r<id>`).
# A heredoc body that goes to anything but a shell (`cat <<'EOF' >> notes.md`, `git commit -F -`) is text,
# and is not read, except the `$( )` and backticks of an unquoted one, which the shell runs. This is a tripwire, not a parser of every shell: it closes the shapes an agent writes.
# Nelson starts a DV session in his own terminal, where this hook does not run.
#
# WHAT IT CANNOT SEE. A SendMessage to a stopped DV session wakes it without any Bash command, so no Bash hook
# sees it; nothing guards SendMessage. `claude -c` / `--continue` resumes the latest conversation of the
# working directory without naming it, and is not checked. A line that does not parse is skipped.
# A name built in a shell variable (`n='[L0-DV] x'; claude --bg --name "$n"`) is not seen either: the hook reads the command's text and does not run the shell. Found by the DV soak of 2026-09-29; the test suite asserts it passes, so a future fix shows up.
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
    # Yields (command words, the separator before it, herestring words). A redirect is NOT a split point:
    # `claude --bg 2>/dev/null --name …` is one command. The operator, its target and a file-descriptor number
    # before it are dropped; a herestring's word (`<<< "…"`) is kept aside, since a shell runs it.
    cur, sep, here, skip = [], None, [], None
    for t in tokens:
        if skip is not None:
            if skip == "<<<":
                here.append(t)
            skip = None
            continue
        if is_redirect(t):
            if cur and cur[-1].isdigit():
                cur.pop()
            skip = t
            continue
        if is_sep(t):
            if cur: yield cur, sep, here
            cur, here, sep = [], [], t
        else:
            # `out=$` before `(`: the `$` belongs to the separator, not to the word
            cur.append(t[:-1] if t.endswith("=$") else t)
    if cur: yield cur, sep, here

def effective(c):
    # The program a command really runs: past `FOO=1` words, and past a wrapper and its own flags and values
    # (`nice -n 5`, `timeout 30`, `sudo -u x`) to the first word that runs something we read.
    i = 0
    while i < len(c) and ASSIGN.match(c[i]):
        i += 1
    if i >= len(c):
        return "", []
    prog = os.path.basename(c[i])
    if prog in WRAPPERS:
        for j in range(i + 1, len(c)):
            w = os.path.basename(c[j])
            if w == "claude" or w in SHELLS or w == "eval":
                return effective(c[j:])
    return prog, c[i + 1:]

def runs_shell(prog):
    return prog in SHELLS or prog == "eval"

def substitutions(line, quotes=True):
    # Every `$( … )` and backtick span the shell would run, found in the raw text so one inside DOUBLE quotes
    # is checked too (shlex keeps a quoted string as one word). Inside SINGLE quotes they are literal text and
    # are skipped, and so is an escaped `\$(` (review 3 of #73). Nested spans are found when each inner
    # string is checked.
    out, i, n, sq, dq = [], 0, len(line), False, False
    while i < n:
        ch = line[i]
        if ch == "\\" and not sq:
            i += 2; continue
        if not quotes:
            pass  # a heredoc body: quotes are plain text there, only `$( )` and backticks count (review 4)
        elif ch == "#" and not sq and not dq and (i == 0 or line[i - 1] in " \t\n;&|("):
            # an unquoted `#` at the start of a word begins a comment to the end of the line (review 4)
            j = line.find("\n", i)
            i = n if j < 0 else j
            continue
        elif ch == "'" and not dq:
            sq = not sq; i += 1; continue
        elif ch == '"' and not sq:
            dq = not dq; i += 1; continue
        if sq:
            i += 1; continue
        if line.startswith("$(", i):
            # Quotes and escapes inside the span are tracked, so a quoted `)` does not end it (review 5).
            depth, j, isq, idq = 1, i + 2, False, False
            while j < n and depth:
                c2 = line[j]
                if c2 == "\\" and not isq:
                    j += 2; continue
                if c2 == "'" and not idq: isq = not isq
                elif c2 == '"' and not isq: idq = not idq
                elif not isq and not idq:
                    if c2 == "(": depth += 1
                    elif c2 == ")": depth -= 1
                j += 1
            out.append(line[i + 2:j - 1] if depth == 0 else line[i + 2:])
            i = j
        elif ch == "`":
            j = line.find("`", i + 1)
            if j < 0:
                out.append(line[i + 1:]); break
            out.append(line[i + 1:j]); i = j + 1
        else:
            i += 1
    return out

HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
def line_feeds_shell(ln):
    # True when any command on the heredoc's own line runs a shell: `bash <<EOF`, `cd x && bash <<EOF`,
    # `cat <<EOF | bash`, `nohup bash <<EOF`, `sudo bash <<EOF` (review 3 of #73). A line that does not parse
    # counts as feeding a shell, so its body is read as commands rather than dropped.
    try:
        segs = list(segments(tokenize(ln)))
    except ValueError:
        return True
    return any(runs_shell(effective(c)[0]) for c, _, _ in segs)

def strip_text_heredocs(line):
    # A heredoc body is TEXT unless a shell reads it: `cat <<'EOF' >> notes.md` and `git commit -F - <<'EOF'`
    # carry prose, and prose that describes a DV start is not one (review 2 of #73). A body a shell reads stays
    # in the line and is read as commands. An UNQUOTED text body is returned apart: the shell still runs the
    # `$( )` and backticks in it while it builds the text (review 3 of #73).
    lines, out, unquoted, i = line.split("\n"), [], [], 0
    while i < len(lines):
        ln = lines[i]; out.append(ln); i += 1
        m = HEREDOC.search(ln)
        if not m or line_feeds_shell(ln):
            continue
        end, body = m.group(2), []
        while i < len(lines) and lines[i].strip() != end:
            body.append(lines[i]); i += 1
        if i < len(lines):
            out.append(lines[i]); i += 1
        if m.group(1) == "":
            unquoted.append("\n".join(body))
    return "\n".join(out), unquoted

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

def env_split_string(c):
    # `env -S "…"`, `env -S'…'`, `env --split-string="…"` and `env --split-string "…"` hand a whole command
    # line in one word (review 3 of #73).
    i = 0
    while i < len(c) and ASSIGN.match(c[i]):
        i += 1
    if i >= len(c) or os.path.basename(c[i]) != "env":
        return None
    args = c[i + 1:]
    for j, a in enumerate(args):
        if a in ("-S", "--split-string") and j + 1 < len(args):
            return args[j + 1]
        if a.startswith("--split-string="):
            return a.split("=", 1)[1]
        if a.startswith("-S") and len(a) > 2:
            return a[2:]
    return None

def check_segment(c, sep, here, prev, depth):
    if depth > 4:
        return
    s = env_split_string(c)
    if s is not None:
        check(s, depth + 1)
    prog, args = effective(c)
    if prog == "claude":
        check_claude(args)
    elif prog == "eval":
        check(" ".join(args), depth + 1)
        for h in here:
            check(h, depth + 1)
    elif prog in SHELLS:
        # A shell's -c string is a command line of its own (`bash -c "claude …"`, `zsh -lc '…'`), and so is a
        # herestring it reads (`bash <<< "…"`).
        for j, a in enumerate(args):
            if a.startswith("-") and not a.startswith("--") and "c" in a[1:] and j + 1 < len(args):
                check(args[j + 1], depth + 1)
                break
        for h in here:
            check(h, depth + 1)
        # `echo '…' | bash` and `printf '…' | sh`: the words the left side prints are the shell's commands.
        if sep == "|" and prev is not None:
            pprog, pargs = effective(prev)
            if pprog in ("echo", "printf"):
                words = [a for a in pargs if not a.startswith("-")]
                for w in words:
                    check(w, depth + 1)
                check(" ".join(words), depth + 1)

def check(line, depth=0):
    if depth > 4:
        return
    # Text heredocs go first, so prose inside a QUOTED one is never read as a substitution; an unquoted one is
    # still scanned, because the shell expands it.
    line, unquoted = strip_text_heredocs(line)
    for body in unquoted:
        for sub in substitutions(body, quotes=False):
            check(sub, depth + 1)
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
    prev = None
    for c, sep, here in segs:
        check_segment(c, sep, here, prev, depth)
        prev = c

check(cmd)
sys.exit(0)
PYEOF
