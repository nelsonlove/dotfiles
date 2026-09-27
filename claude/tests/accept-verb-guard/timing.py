#!/usr/bin/env python3
"""[test artifact — safe to delete] the narrowed guard's timing floor and cap.

Fails on TIME as well as verdict, because a guard that answers too slowly is an OPEN guard: the harness
kills it, the EXIT trap never runs, and every exit code but 2 reads as allow.

THE THIRD CASE GUARDS AGAINST A SPECIFIC FAILURE THAT HAPPENED TWICE. Both times a per-position question
was answered by walking a list from the start — first the quote-region builder, then the region lookup
inside the road scan — and both times every verdict case stayed green while the guard became quadratic. The
second time it was a live fail-open: 396 KB took 9.74 s against a 10 s timeout and 1 MB took 72 s. The
shape that exposes it is MANY ROAD HITS AND MANY QUOTED REGIONS IN ONE PAYLOAD; either alone stays linear.
If a third attempt reintroduces it, this case must go red rather than a reviewer finding it.
"""
import json, os, subprocess, sys, time

GUARD = sys.argv[1]
LIMIT = 5.0
CAP = 4 * 1024 * 1024
fails = 0
n = 0
try:
    print(f"load average now: {', '.join('%.2f' % x for x in os.getloadavg())}\n")
except Exception:
    pass


def run(label, body, want_rc, limit=LIMIT, note=""):
    global fails, n
    n += 1
    payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": body}}).encode()
    t = time.time()
    r = subprocess.run([GUARD], input=payload, capture_output=True)
    el = time.time() - t
    ok = r.returncode == want_rc and el <= limit
    print(f'{"PASS" if ok else "FAIL"}  {label:<54} rc={r.returncode}'
          f'{"" if r.returncode == want_rc else " (wanted %s)" % want_rc}  {el:.2f}s limit {limit}s  {note}')
    if not ok:
        fails += 1


run("4 MB dense quotes, no road", "'command=a' " * (4_000_000 // 12), 0)
run("1 MB with a real call at the front",
    'obsidian vault=obsidian command id=x ' + "y" * 1_000_000, 2)
# the quadratic shape: many road hits AND many quoted regions together
run("1 MB of road hits AND quoted regions (the quadratic shape)",
    ("echo 'obsidian ' \n" * (1_000_000 // 18)) + "\nobsidian command id=x", 2,
    note="guards the failure that recurred twice")
run("just over the cap with a road",
    "y" * (CAP + 1000) + "\nobsidian command id=x", 2, 3.0, "must refuse unread")
run("just over the cap with NO road", "y" * (CAP + 1000), 0, 3.0)
run("10 MB ordinary vault heredoc, no road",
    "cat <<EOF >> ~/obsidian/x.md\n" + ("the note lives at ~/obsidian/00-09 System/x.md\n" * 200_000) + "EOF", 0)
print(f"\n{n} timing cases, {fails} failed")
sys.exit(1 if fails else 0)
