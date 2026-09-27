#!/bin/bash
# [test artifact — safe to delete] accept-verb-guard: a case that fails on TIME, not on verdict.
#
# WHY THIS EXISTS. A hook killed by a harness timeout never reaches its EXIT trap, and anything but
# exit 2 reads as allow. So a slow matcher is not a slow guard, it is an OPEN guard — and it is the one
# class of regression where every verdict test in the battery still prints PASS while the guard has
# stopped guarding. Measured on 2026-09-27: a first cut of the v2.1 matcher answered the worst-case
# payload in 56 seconds. Nothing in the 39-case battery noticed, because all 39 verdicts were correct.
#
# THE THRESHOLD, and why this number. Anchored on the repo's own declared budget rather than invented.
# When this test was written, `accept-verb-guard.sh` had NO `timeout` field in claude/settings.json and so
# ran on Claude Code's undeclared default; the only stated opinion in the repo was its sibling on the same
# `Bash` matcher, `shell-move-safety.sh`, at `"timeout": 10`. As of build 930f26d the guard declares
# `"timeout": 10` itself, on both matchers, so the budget is now its own.
#
# So: 5 s. Half the declared 10 s budget, which leaves room for a loaded machine and a cold cache, and
# roughly twice a healthy build's worst case of 1-2 s, which leaves room for honest variation. It is a
# guard-rail against the 56-second class, NOT a model of the harness timeout — the point is to fail loudly
# long before anything is killed, because a kill is silent and reads as allow.
#
# WHAT DECLARING THE TIMEOUT DID NOT FIX, and the reason this test needs a third case. A timeout does not
# make a slow guard safe; it makes the kill deterministic. Measured on 930f26d, where the cost is linear at
# about 0.9 s/MB: 10 MB answers in 9.06 s, 12 MB in 9.90 s, and 16 MB in 13.32 s — past the declared 10 s,
# so a 16 MB payload is killed and reads as ALLOW. That is a bypass needing bulk and nothing else.
#
# The fix is a size cap that REFUSES. The guard's header rejects a cap because "a cap is a bypass — put the
# call after the cut and the guard never sees it", which is true only if exceeding the cap means allow. If
# exceeding it means refuse, a cap is fail-closed and the objection dissolves. When that lands, add a third
# case here: a payload just over the cap must refuse, and must refuse quickly.
#
# Needs perl's Time::HiRes for sub-second timing. perl is already a hard dependency of the guard
# itself, so this adds nothing new.
set -u
H="${1:?usage: timing-floor.sh <path to accept-verb-guard.sh>}"
THRESHOLD=5.0

tmp=$(mktemp -d -t accept-verb-timing) || { echo "no temp dir"; exit 2; }
trap 'rm -rf "$tmp"' EXIT

fails=0

# Payload A — the worst case the design admits: a verb IS named, so the guard cannot exit at the
# presence test, and then ~120,000 quoted markers each of which must have its value read and rejected.
# No real invocation anywhere, so every candidate must be examined before it can answer "allow".
python3 - "$tmp" <<'PY'
import json, sys
tmp = sys.argv[1]
head = "notes on verify current note in obsidian. "
unit = "echo 'command=abc' ; "          # a quoted marker that is data, not a call
body = head + unit * 120000
json.dump({"tool_name": "Bash", "tool_input": {"command": body}}, open(tmp + "/a.json", "w"))

# Payload B — 10 MB, with a REAL invocation at the front, so the answer is a refusal and the cost is
# dominated by reading the payload rather than by searching it.
big = "lorem ipsum dolor sit amet " * 400000
json.dump({"tool_name": "Bash",
           "tool_input": {"command": 'obsidian vault=obsidian command="Verify current note" ; echo ' + big}},
          open(tmp + "/b.json", "w"))
PY

timed() {  # $1 = payload, $2 = wanted rc, $3 = label; prints PASS/FAIL on BOTH verdict and time
  local f="$1" want="$2" label="$3"
  local size; size=$(perl -e 'printf "%.1f", (stat($ARGV[0]))[7]/1048576' "$f")
  local t0 t1 rc elapsed
  t0=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  "$H" < "$f" >/dev/null 2>&1; rc=$?
  t1=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  elapsed=$(perl -e 'printf "%.2f", $ARGV[1] - $ARGV[0]' "$t0" "$t1")
  local bad=""
  [ "$rc" = "$want" ] || bad="wrong verdict (wanted $want)"
  if perl -e 'exit(($ARGV[0] > $ARGV[1]) ? 0 : 1)' "$elapsed" "$THRESHOLD"; then
    [ -z "$bad" ] || bad="$bad; "
    bad="${bad}TOO SLOW (${elapsed}s > ${THRESHOLD}s) — a killed hook reads as ALLOW"
  fi
  if [ -z "$bad" ]; then
    printf 'PASS  [%s] rc=%s in %ss (%s MB)\n' "$label" "$rc" "$elapsed" "$size"
  else
    fails=$((fails + 1))
    printf 'FAIL  [%s] rc=%s in %ss (%s MB) — %s\n' "$label" "$rc" "$elapsed" "$size" "$bad"
  fi
}

printf -- '=== timing floor: threshold %ss\n' "$THRESHOLD"
timed "$tmp/a.json" 0 "worst case: a verb named, ~120,000 quoted markers, no real call"
timed "$tmp/b.json" 2 "10 MB with a real invocation at the front"

printf '\n2 timing cases, %s failed\n' "$fails"
[ "$fails" -eq 0 ]
