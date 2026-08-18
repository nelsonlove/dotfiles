#!/bin/bash
# shell-move-safety.sh — PreToolUse[Bash] guard for risky mv/rm/trash commands.
# From the recovered idea "Pre-rename/move/delete shell-safety hook" (Inbox ideas
# inventory 2026-08-08; ledger §4). Checks:
#   1. `rm` targeting vault/JD territories → deny (use /usr/bin/trash, per CLAUDE.md)
#   2. `mv A a` where names differ only by case → deny (APFS case-rename needs two steps)
#   3. mv/trash source path that only exists under a different Unicode normalization → deny
# Fail-open by design: parse trouble or unexpected input → allow silently.

input=$(cat)
cmd=$(printf '%s' "$input" | /usr/bin/python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("tool_input",{}).get("command",""))
except Exception: pass' 2>/dev/null) || exit 0

# Fast path: nothing move/delete-shaped in the command.
printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])(rm|mv|trash|/usr/bin/trash)([[:space:]]|$)' || exit 0

SAFETY_CMD="$cmd" /usr/bin/python3 - <<'PYEOF'
import sys, os, shlex, json, unicodedata

cmd = os.environ.get("SAFETY_CMD", "")
if "<<" in cmd:  # heredocs: appends etc. — out of scope, allow
    sys.exit(0)

def deny(reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason}}))
    sys.exit(0)

try:
    tokens = shlex.split(cmd, posix=True)
except ValueError:
    sys.exit(0)  # unparseable quoting — allow, the shell will complain

GUARDED = [os.path.expanduser(p) for p in ("~/obsidian", "~/obsidian-old", "~/Documents")]
SEP = {";", "&&", "||", "|", "&"}

# Split into simple commands
cmds, cur = [], []
for t in tokens:
    if t in SEP:
        if cur: cmds.append(cur); cur = []
    else:
        cur.append(t)
if cur: cmds.append(cur)

for c in cmds:
    if not c: continue
    prog = os.path.basename(c[0])
    args = [a for a in c[1:] if not a.startswith("-")]
    if prog == "rm":
        for a in args:
            p = os.path.abspath(os.path.expanduser(a))
            if any(p == g or p.startswith(g + os.sep) for g in GUARDED):
                deny(f"rm on a vault/JD path ({a}). House rule: use /usr/bin/trash (recoverable) instead of rm for vault and Documents territories.")
    elif prog in ("mv", "trash"):
        if prog == "mv" and len(args) >= 2:
            src, dst = args[-2], args[-1]
            if src != dst and src.lower() == dst.lower():
                deny(f"case-only rename ({src} -> {dst}) is unreliable on APFS through sync layers. Do it in two steps: mv to a temp name, then mv to the final name.")
        for a in args:
            if not os.path.lexists(os.path.expanduser(a)):
                for form in ("NFC", "NFD"):
                    alt = unicodedata.normalize(form, a)
                    if alt != a and os.path.lexists(os.path.expanduser(alt)):
                        deny(f"path {a!r} does not exist as written, but its Unicode {form}-normalized form does. Re-run with the normalized path (copy it from ls output) to avoid a silent miss.")

sys.exit(0)
PYEOF
exit 0
