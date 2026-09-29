#!/bin/bash
# dv-tripwire.sh — PreToolUse[Bash]: refuse a command line that would start or resume a session on ship DV.
#
# Nelson's areas ruling (log 2026-09-29T03:35): 80-89 Divorce is guarded, and "its captain starts only when
# Nelson starts it". The fleet scripts refuse every caller for DV (`ship_refusal` in claude/bin/_fleet-ranks.sh),
# but a session does not need a script to start one: a bare `claude --bg --name "[C0-DV] …"` does it. This
# hook is the guard on that bare command line. It refuses:
#   * `claude … --bg …` or `claude … --resume …` / `-r` whose line names a `-DV]` session, in any case;
#   * `claude --resume <id>` / `-r <id>` / `--resume=<id>` where <id> (short or full) is a session whose
#     name in `claude agents --json --all` carries `-DV]`;
#   * the same behind `FOO=1`, `env`, `nohup` and similar, and inside a shell's `-c` string.
# Nelson starts a DV session in his own terminal, where this hook does not run.
#
# WHAT IT CANNOT SEE. A SendMessage to a stopped DV session wakes it without any Bash command, so no Bash hook
# sees it; nothing guards SendMessage. A command it cannot parse (unbalanced quotes) is refused only if it
# names `-DV]` beside a `claude` word, since the shell will refuse it anyway.
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

SEP = {";", "&&", "||", "|", "&"}
WRAPPERS = {"env", "nohup", "exec", "command", "time", "caffeinate", "sudo", "nice"}
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

def check(line, depth=0):
    try:
        tokens = shlex.split(line, posix=True)
    except ValueError:
        if DV.search(line):
            deny(REASON + " (The command could not be parsed, and it names a DV session beside a claude word.)")
        return
    cmds, cur = [], []
    for t in tokens:
        if t in SEP:
            if cur: cmds.append(cur); cur = []
        else:
            cur.append(t)
    if cur: cmds.append(cur)
    for c in cmds:
        # Skip what runs a command without being one: `FOO=1`, `env`, `nohup` and their like.
        i = 0
        while i < len(c) and (ASSIGN.match(c[i]) or os.path.basename(c[i]) in WRAPPERS or (c[i].startswith("-") and i > 0)):
            i += 1
        if i >= len(c):
            continue
        prog, args = os.path.basename(c[i]), c[i + 1:]
        # A shell's -c string is a command line of its own (`bash -c "claude …"`, `zsh -lc '…'`).
        if prog in SHELLS and depth < 3:
            for j, a in enumerate(args):
                if a.startswith("-") and not a.startswith("--") and "c" in a[1:] and j + 1 < len(args):
                    check(args[j + 1], depth + 1)
                    break
            continue
        if prog != "claude":
            continue
        starts = "--bg" in args
        resumes = [a for a in args if a in ("--resume", "-r") or a.startswith("--resume=")]
        if not (starts or resumes):
            continue
        if any(DV.search(a) for a in args):
            deny(REASON)
        for k, a in enumerate(args):
            ident = None
            if a.startswith("--resume="):
                ident = a.split("=", 1)[1]
            elif a in ("--resume", "-r") and k + 1 < len(args):
                ident = args[k + 1]
            if ident and DV.search(name_of(ident)):
                deny(REASON + f" (Session {ident} is listed as {name_of(ident)!r}.)")

check(cmd)
sys.exit(0)
PYEOF
