#!/usr/bin/env bash
# Package 8: below captain, the start hook injects RULINGS only (Nelson, 2026-09-29T02:13: "B and clear out the old entries, it's a loooong file", a one-week trial). Captains and admirals keep the whole delta. The hook is claude/hooks/cross-session-inject.py.
#
# THE POPULATION CASE FIRST, against the real log, read-only: the hook's own classifier over every real heading, with its properties asserted and its counts printed (the file moves while it is read, so counts are never asserted). Then fixtures under a temp HOME, with a temp log, temp job state and a stubbed `claude`, never the real state files.
#
# Run: bash claude/tests/cross-session-inject/rulings-only.sh   (prints the check count; exits non-zero on any failure)
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
HOOK="$HERE/../../hooks/cross-session-inject.py"
n=0; fails=0; skips=0
pass() { n=$((n + 1)); printf 'PASS  %s\n' "$1"; }
fail() { n=$((n + 1)); fails=$((fails + 1)); printf 'FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; }
has() { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "missing: $3" ;; esac; }
lacks() { case "$2" in *"$3"*) fail "$1" "present: $3" ;; *) pass "$1" ;; esac; }

echo "=== 1. the real log, read-only: the hook's classifier over every heading"
REAL_LOG="$HOME/obsidian/00-09 System/03 Agents/03.16 Cross-session log/CROSS-SESSION.md"
if [ -f "$REAL_LOG" ]; then
  pop=$(python3 - "$HOOK" "$REAL_LOG" <<'PY'
import importlib.util, re, sys
spec = importlib.util.spec_from_file_location("hook", sys.argv[1]); hook = importlib.util.module_from_spec(spec); spec.loader.exec_module(hook)
if not hasattr(hook, "is_ruling"): print("no-classifier"); sys.exit()
entries = hook.split_entries(open(sys.argv[2], errors="replace").read())
heads = [e.split("\n", 1)[0] for _, e in entries]
rul = [h for h in heads if hook.is_ruling(h)]
claims = [h for h in heads if re.search(r"—\s*(claim|release)\b", h)]
bad = [h for h in rul if re.search(r"—\s*(claim|release)\b", h)]
# False negatives: a heading whose kind (the text after "· author — ") names a ruling, and is not a claim or release, must read as a ruling.
def kind(h):
    m = re.search(r"·.*?\s[—–-]\s*(.*)$", h); return m.group(1) if m else ""
missed = [h for h in heads if re.search(r"\brulings?\b", kind(h), re.I) and not re.match(r"(claim|release)\b", kind(h), re.I) and not hook.is_ruling(h)]
for h in missed: print("      missed:", h[:120], file=sys.stderr)
print("entries=%d rulings=%d claims_or_releases=%d misread=%d missed=%d" % (len(heads), len(rul), len(claims), len(bad), len(missed)))
PY
)
  case "$pop" in
    no-classifier) fail "the hook has a ruling classifier (is_ruling)" "none on this hook" ;;
    *) printf '      %s\n' "$pop"
       entries=$(printf '%s' "$pop" | sed -E 's/.*entries=([0-9]+).*/\1/'); rulings=$(printf '%s' "$pop" | sed -E 's/.*rulings=([0-9]+).*/\1/'); misread=$(printf '%s' "$pop" | sed -E 's/.*misread=([0-9]+).*/\1/')
       if [ "$entries" -gt 50 ]; then pass "the population is real ($entries entries)"; else fail "the population is real" "only $entries entries"; fi
       if [ "$rulings" -gt 0 ]; then pass "real rulings are found ($rulings)"; else fail "real rulings are found" "none"; fi
       if [ "$misread" = 0 ]; then pass "no claim or release reads as a ruling"; else fail "no claim or release reads as a ruling" "$misread misread"; fi
       missed=$(printf '%s' "$pop" | sed -E 's/.*missed=([0-9]+).*/\1/')
       if [ "$missed" = 0 ]; then pass "no heading whose kind is a ruling is missed"; else fail "no heading whose kind is a ruling is missed" "$missed missed"; fi ;;
  esac
else
  n=$((n + 4)); skips=$((skips + 4)); printf 'SKIP  the real-log population (4 checks): no log at %s\n' "$REAL_LOG"
fi

# --- fixtures -------------------------------------------------------------------------------------------------
T=$(mktemp -d "${TMPDIR:-/tmp}/rulings-only.XXXXXX") || exit 1
trap '/usr/bin/trash "$T" 2>/dev/null || true' EXIT
H="$T/home"; LOGDIR="$H/obsidian/00-09 System/03 Agents/03.16 Cross-session log"; mkdir -p "$LOGDIR" "$H/.claude/jobs" "$T/stubbin"
LOG="$LOGDIR/CROSS-SESSION.md"
printf '#!/bin/sh\ncat "%s/listing.json" 2>/dev/null || echo "[]"\n' "$T" > "$T/stubbin/claude"; chmod +x "$T/stubbin/claude"
echo '[]' > "$T/listing.json"
now=$(date +%Y-%m-%dT%H:%M)
day=$(date +%Y-%m-%d)
mklog() {  # a log of mixed entries, stamped today so they fall inside the first-run window
  { printf -- '---\naudience: fleet\n---\n\n'
    printf '## %sT00:01 · [L0-CC] a — claim\nClaim one.\n\n' "$day"
    printf '## %sT00:02 · [A0] rear admiral — ruling\nNelson: "ruling one". The act.\n\n' "$day"
    printf '## %sT00:03 · [L0-CC] a — release\nRelease one.\n\n' "$day"
    printf '## %sT00:04 · [C1-OB] machinery — ruling: Nelson "two" (relayed)\n\n' "$day"
    printf '## %sT00:05 · [L0-OB] b — claim: for Nelson'"'"'s ruling of 00:02, a file\n\n' "$day"
  } > "$LOG"
}
sid() { printf '%s-0000-0000-0000-000000000000' "$1"; }
job() {  # job <8-hex id> <template>
  mkdir -p "$H/.claude/jobs/$1"; printf '{"template":"%s"}\n' "$2" > "$H/.claude/jobs/$1/state.json"
}
listing() {  # listing <8-hex id> <name>
  printf '[{"id":"%s","sessionId":"%s","name":"%s"}]\n' "$1" "$(sid "$1")" "$2" > "$T/listing.json"
}
inject() {  # inject <8-hex id>: the hook's additionalContext for that session
  printf '{"session_id":"%s"}' "$(sid "$1")" | HOME="$H" PATH="$T/stubbin:$PATH" python3 "$HOOK" \
    | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception: print("")'
}
seed() {  # seed <8-hex id> <stamp>: a later run, not a first one (a first run gets the newest rulings; section 5)
  mkdir -p "$H/.local/share/cross-session-hook"; printf '%s' "$2" > "$H/.local/share/cross-session-hook/$(sid "$1")"
}
state_of() { cat "$H/.local/share/cross-session-hook/$(sid "$1")" 2>/dev/null; }

echo
echo "=== 2. who gets what"
mklog; job aaaaaaaa lieutenant
out=$(inject aaaaaaaa)
has   "a lieutenant gets the rulings (the one ending '— ruling')" "$out" "ruling one"
has   "a lieutenant gets the rulings (the one with '— ruling:' mid-heading)" "$out" 'Nelson "two"'
lacks "a lieutenant does not get the claims" "$out" "Claim one."
lacks "a lieutenant does not get the releases" "$out" "Release one."
lacks "a claim that mentions a ruling is still a claim" "$out" "for Nelson's ruling of 00:02"
has   "the lieutenant's text says it is rulings only" "$out" "RULINGS ONLY"

mklog; job bbbbbbbb captain
out=$(inject bbbbbbbb)
has "a captain gets the claims too" "$out" "Claim one."
has "a captain gets the rulings" "$out" "ruling one"

mklog; job cccccccc claude; listing cccccccc "[A0] rear admiral"
out=$(inject cccccccc)
has "an admiral (by name, agent claude) gets everything" "$out" "Release one."

mklog; job dddddddd claude; listing dddddddd "[L0-CC] by name"
out=$(inject dddddddd)
lacks "a lieutenant known only by its name gets rulings only" "$out" "Claim one."

mklog; echo '[]' > "$T/listing.json"
out=$(inject eeeeeeee)
has "a session whose rank cannot be told gets everything (fail safe)" "$out" "Claim one."

mklog; job ffffffff commander
out=$(inject ffffffff)
lacks "a commander is below captain: rulings only" "$out" "Claim one."

echo
echo "=== 3. the cap, and the stamp never passes an unshown ruling"
# Ten long rulings (600 bytes each) and a claim after each: more than the ~3000-character cap in one start.
{ printf -- '---\naudience: fleet\n---\n\n'
  for i in 10 11 12 13 14 15 16 17 18 19; do
    printf '## %sT01:%s · [A0] rear admiral — ruling\nR%s %s\n\n' "$day" "$i" "$i" "$(python3 -c 'print("r" * 600)')"
    printf '## %sT01:%s · [L0-CC] a — claim\nC%s.\n\n' "$day" "$((i + 30))" "$i"
  done
} > "$LOG"
job 11111111 lieutenant; seed 11111111 "${day}T00:00"
seen=""; rounds=0; capped=ok
while [ "$rounds" -lt 12 ]; do
  out=$(inject 11111111); rounds=$((rounds + 1))
  body=$(printf '%s' "$out" | python3 -c 'import sys; t=sys.stdin.read(); print(len(t))')
  [ "$body" -le 4200 ] || capped="a start injected $body characters"
  new=$(printf '%s' "$out" | grep -oE '^R[0-9]+' | tr '\n' ' ')
  [ -n "$new" ] || break
  seen="$seen$new"
done
if [ "$capped" = ok ]; then pass "every start stays near the cap (about 3000 characters of rulings)"; else fail "every start stays near the cap" "$capped"; fi
all=$(printf '%s' "$seen" | tr ' ' '\n' | grep . | sort -u | tr '\n' ' ')
if [ "$all" = "R10 R11 R12 R13 R14 R15 R16 R17 R18 R19 " ]; then pass "over several starts every ruling is shown, none skipped ($rounds starts)"; else fail "every ruling is shown, none skipped" "shown: $all"; fi
if [ "$rounds" -gt 2 ]; then pass "the cap made it take more than one start"; else fail "the cap made it take more than one start" "$rounds starts"; fi
# Once every ruling is shown, the stamp passes the claims after them too (they are not meant to be read below captain).
st=$(state_of 11111111)
if [ "$st" = "${day}T01:49" ]; then pass "after the last ruling, the stamp moves past the trailing claims"; else fail "after the last ruling, the stamp moves past the trailing claims" "stamp $st"; fi

echo
echo "=== 4. ties, dash variants, and the channel list"
# Four long rulings in ONE minute, over the cap together: the stamp must not stall on the tie (it would reshow the first forever).
{ printf -- '---\naudience: fleet\n---\n\n'
  for i in 1 2 3 4; do printf '## %sT02:00 · [A0] rear admiral — ruling\nT%s %s\n\n' "$day" "$i" "$(python3 -c 'print("t" * 900)')"; done
  printf '## %sT02:05 · [A0] rear admiral — ruling\nT5 after the tie.\n\n' "$day"
} > "$LOG"
job 22222222 lieutenant; seed 22222222 "${day}T00:00"
seen=""; rounds=0
while [ "$rounds" -lt 8 ]; do
  out=$(inject 22222222); rounds=$((rounds + 1))
  new=$(printf '%s' "$out" | grep -oE '^T[0-9]+' | tr '\n' ' ')
  [ -n "$new" ] || break
  seen="$seen$new"
done
all=$(printf '%s' "$seen" | tr ' ' '\n' | grep . | sort -u | tr '\n' ' ')
if [ "$all" = "T1 T2 T3 T4 T5 " ]; then pass "rulings tied on one stamp over the cap are all shown, and the stamp moves on ($rounds starts)"; else fail "rulings tied on one stamp over the cap are all shown" "shown: $all in $rounds starts"; fi

{ printf -- '---\naudience: fleet\n---\n\n'
  printf '## %sT03:01 · [A0] rear admiral – ruling\nEN dash ruling.\n\n' "$day"
  printf '## %sT03:02 · [A0] rear admiral - ruling (relayed)\nHYPHEN ruling.\n\n' "$day"
  printf '## %sT03:03 · [L0-CC] a - claim: the pre-ruling file\nHYPHEN claim.\n\n' "$day"
  printf '## %sT03:04 · [A0] rear admiral—ruling\nNO SPACE ruling.\n\n' "$day"
  printf '## %sT03:05 · [A0] rear admiral — rulings: two of them\nPLURAL rulings.\n\n' "$day"
  printf '## %sT03:06 · [A0] rear admiral — ruling and release in one\nCOMBINED ruling.\n\n' "$day"
} > "$LOG"
job 33333333 lieutenant
out=$(inject 33333333)
has   "a ruling marked with an en dash is shown" "$out" "EN dash ruling."
has   "a ruling marked with a hyphen and a note is shown" "$out" "HYPHEN ruling."
lacks "a hyphen claim is still a claim" "$out" "HYPHEN claim."
has   "a ruling marked with an em dash and no space is shown" "$out" "NO SPACE ruling."
has   "a plural 'rulings:' is shown" "$out" "PLURAL rulings."
has   "a combined 'ruling and release in one' is shown" "$out" "COMBINED ruling."
has   "a lieutenant still gets the channel list" "$out" "Cross-session channels discovered"

echo
echo "=== 5. a FIRST run below captain gets the newest rulings, and the older ones are never paged later"
{ printf -- '---\naudience: fleet\n---\n\n'
  for i in 10 11 12 13 14 15 16 17 18 19; do
    printf '## %sT04:%s · [A0] rear admiral — ruling\nF%s %s\n\n' "$day" "$i" "$i" "$(python3 -c 'print("f" * 600)')"
  done
  printf '## %sT04:30 · [L0-CC] a — claim\nTrailing claim.\n\n' "$day"
} > "$LOG"
job 44444444 lieutenant
out=$(inject 44444444)
has   "a first run over the cap gets the newest ruling" "$out" "F19 "
lacks "a first run over the cap does not get the oldest ruling" "$out" "F10 "
first=$(printf '%s' "$out" | grep -oE '^F[0-9]+' | head -1)
if [ "$first" = F19 ]; then pass "a first run shows the newest ruling first"; else fail "a first run shows the newest ruling first" "first shown: $first"; fi
st=$(state_of 44444444)
if [ "$st" = "${day}T04:19" ]; then pass "a first run sets the stamp to the newest ruling"; else fail "a first run sets the stamp to the newest ruling" "stamp $st"; fi
printf '## %sT04:40 · [A0] rear admiral — ruling\nF40 later.\n\n' "$day" >> "$LOG"
out=$(inject 44444444)
has   "a second run gets the ruling after the stamp" "$out" "F40 later."
lacks "a second run does not page the older rulings" "$out" "F10 "
lacks "a second run does not reshow the first run's rulings" "$out" "F19 "

{ printf -- '---\naudience: fleet\n---\n\n'
  printf '## %sT05:01 · [A0] rear admiral — ruling\nSMALL one.\n\n' "$day"
  printf '## %sT05:02 · [L0-CC] a — claim\nClaim.\n\n' "$day"
  printf '## %sT05:03 · [A0] rear admiral — ruling\nSMALL two.\n\n' "$day"
} > "$LOG"
job 55555555 lieutenant
out=$(inject 55555555)
has "a first run under the cap gets every ruling (the older)" "$out" "SMALL one."
has "a first run under the cap gets every ruling (the newer)" "$out" "SMALL two."

EXPECTED=37
[ $((n)) = "$EXPECTED" ] || { fails=$((fails + 1)); echo "FAIL  the check count is $n, expected $EXPECTED"; }
printf '\n%s checks (expected %s), %s failed, %s skipped\n' "$n" "$EXPECTED" "$fails" "$skips"
[ "$fails" = 0 ] || exit 1
