#!/usr/bin/env python3
"""[test artifact — safe to delete] the inversion's timing floor and cap behaviour.

Fails on TIME as well as verdict, because a guard that answers too slowly is an OPEN guard: the harness
kills it, the EXIT trap never runs, and every exit code but 2 reads as allow. The 5.0 s limit is half the
10 s the guard declares for itself, leaving room for a loaded machine.
"""
import json, subprocess, sys, time

GUARD = sys.argv[1]
LIMIT = 5.0
CAP = 5 * 1024 * 1024
fails = 0
n = 0


def run(label, payload: bytes, want_rc, want_under=LIMIT, note=""):
    global fails, n
    n += 1
    t = time.time()
    r = subprocess.run([GUARD], input=payload, capture_output=True)
    el = time.time() - t
    ok = r.returncode == want_rc and (want_under is None or el <= want_under)
    print(f'{"PASS" if ok else "FAIL"}  {label:<52} rc={r.returncode} '
          f'{"(wanted %s)" % want_rc if r.returncode != want_rc else ""} {el:.2f}s'
          f'{" limit %.1fs" % want_under if want_under else ""}  {note}')
    if not ok:
        fails += 1


def payload(body: str) -> bytes:
    return json.dumps({"tool_name": "Bash", "tool_input": {"command": body}}).encode()


dense_unit = "'command=a' "
road = ' obsidian vault=obsidian command id="quickadd:choice:x"'

# dense markers, no road at all: the fast path must exit at once however large it is
run("10 MB, dense quotes, NO road", payload(dense_unit * (10_000_000 // len(dense_unit))), 0)
# under the cap WITH a road: the full read must happen, and inside the floor
under = "x" * (4 * 1024 * 1024) + road
run("4 MB with a real call (under the cap)", payload(under), 2)
# just over the cap WITH a road: refused unread, and fast
over = "x" * (CAP + 1000) + road
run("5 MB + with a real call (over the cap)", payload(over), 2, 3.0, "must refuse unread")
# over the cap with a road shape only in a heredoc BODY: the fast path sees a candidate, so the cap
# refuses it — a false refusal the header must name rather than hide
body = "cat <<EOF >> /tmp/x.md\n" + ("prose line\n" * 100) + "obsidian command id=x\n" + ("y" * (CAP + 1000)) + "\nEOF"
run("over the cap, road only inside a heredoc body", payload(body), 2, 3.0, "NAMED: the cap cannot read it")
# an ordinary huge write with no road: must pass, and fast
plain = "cat <<EOF >> ~/obsidian/x.md\n" + ("the note lives at ~/obsidian/00-09 System/x.md\n" * 200_000) + "EOF"
run("10 MB ordinary vault heredoc, no road", payload(plain), 0, 3.0)
print(f"\n{n} timing cases, {fails} failed")
sys.exit(1 if fails else 0)
