#!/usr/bin/env python3
"""[test artifact — safe to delete] PROPERTY timing test: growth, not wall time.

WHY THIS EXISTS. This hook has been QUADRATIC FOUR TIMES — the quote-region builder, a per-hit rescan of
the region list, the leading-assignment stripping loop, and the heredoc-opener liveness scan. Every time,
every verdict case stayed green while the guard turned from slow into OPEN: the harness kills a hook that
runs past its declared timeout, the EXIT trap never runs, and every exit code but 2 reads as allow. Each
instance was caught by a human or a reviewer noticing, and then pinned by a case shaped like that one
instance. Four times says per-shape cases are not enough.

So this asserts the PROPERTY instead: for each payload shape, doubling the size must not much more than
double the time. A new quadratic in any shape fails here, whatever its shape, without anyone having to
have thought of it first.

THRESHOLD: time(4x) / time(1x) must be under 6.0. Linear would be 4.0; the margin absorbs process start-up
(which is a fixed cost and so makes small payloads look slower, biasing the ratio DOWN, not up) and a
loaded machine. Quadratic growth is 16.0, so the gap between pass and fail is wide — this test is not
trying to measure performance, only to catch a change of shape.
"""
import json, os, subprocess, sys, time

GUARD = sys.argv[1]
RATIO_LIMIT = 6.0
BASE = 200_000  # bytes at 1x; 4x is 800 KB, which is quick when linear and hopeless when not
ROAD = ' obsidian vault=obsidian command id=x'


def shape_dense_quotes(n):
    return "'command=a' " * (n // 12)


def shape_assignments(n):
    # F1: the leading VAR=value stripping loop, which copied the rest of the stage per substitution
    return "a=1 " * (n // 4) + ROAD


def shape_openers_and_quotes(n):
    # F2: many heredoc openers on one line, each asking a linear liveness question
    return ROAD + (" 'a' <<x" * (n // 8))


def shape_hits_and_regions(n):
    # the second quadratic: many road hits AND many quoted regions together
    return ("echo 'obsidian ' \n" * (n // 18)) + ROAD


def shape_vault_heredoc(n):
    line = "the note lives at ~/obsidian/00-09 System/x.md\n"
    return "cat <<EOF >> ~/obsidian/x.md\n" + line * (n // len(line)) + "EOF"


def shape_prose_with_road(n):
    return ("# obsidian command id=x is the road\n" * (n // 36)) + "echo done"


SHAPES = [
    ("dense quoted markers", shape_dense_quotes),
    ("leading VAR=value assignments", shape_assignments),
    ("heredoc openers + quotes", shape_openers_and_quotes),
    ("road hits + quoted regions", shape_hits_and_regions),
    ("an ordinary vault heredoc", shape_vault_heredoc),
    ("comment lines naming the road", shape_prose_with_road),
]


def run(body):
    payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": body}}).encode()
    t = time.time()
    r = subprocess.run([GUARD], input=payload, capture_output=True)
    return time.time() - t, r.returncode


try:
    print(f"load average now: {', '.join('%.2f' % x for x in os.getloadavg())}\n")
except Exception:
    pass
print(f'{"shape":<32} {"1x":>7} {"2x":>7} {"4x":>7} {"ratio":>7}  verdict')
fails = 0
for label, fn in SHAPES:
    times = []
    rcs = []
    for mult in (1, 2, 4):
        el, rc = run(fn(BASE * mult))
        times.append(el)
        rcs.append(rc)
    ratio = times[2] / times[0] if times[0] > 0 else 0
    same = len(set(rcs)) == 1
    ok = ratio <= RATIO_LIMIT and same
    if not ok:
        fails += 1
    note = f'rc={rcs[0]}' if same else f'VERDICT CHANGED WITH SIZE: {rcs}'
    print(f'{("PASS " if ok else "FAIL ") + label:<32} {times[0]:>6.2f}s {times[1]:>6.2f}s {times[2]:>6.2f}s '
          f'{ratio:>6.1f}x  {note}')
print(f'\n{len(SHAPES)} shapes, {fails} failed  (limit {RATIO_LIMIT}x for a 4x size increase; quadratic is 16x)')
sys.exit(1 if fails else 0)
