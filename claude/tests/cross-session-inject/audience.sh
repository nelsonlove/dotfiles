#!/usr/bin/env bash
# The audience filter in the start hook (Nelson, 2026-09-30, "a for all", on `01.65 Operator's console/Decide who sees each ruling — the filer and its chain by default.md`). Below captain, a ruling is shown when its heading's `· for: <label>` names this session or a session under it (the chain is the notebook entries' `reports-to`), when its `· ships:` holds this session's ship, when it says `· fleet`, or when it carries no mark at all (fail-open). An `[L0]` is not reached by `ships:`. Labels are matched, never ids, with former labels from the registry's `formerNames` and from the rename ledger that `claude/bin/rename-notebook.sh` writes.
#
# THE POPULATION CASE FIRST, against the real log, read-only: the marks are counted and printed (never asserted: the file moves while it is read), and every heading that carries a mark and whose kind is a ruling must read as a ruling. Then fixtures under a temp HOME: a temp log, temp notebook roots, a temp session registry, temp job state and a stubbed `claude`; never the real ones.
#
# Run: bash claude/tests/cross-session-inject/audience.sh   (prints the check count; exits non-zero on any failure)
# To watch it fail on another hook: HOOK=/path/to/cross-session-inject.py bash claude/tests/cross-session-inject/audience.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
HOOK="${HOOK:-$HERE/../../hooks/cross-session-inject.py}"
n=0; fails=0; skips=0
pass() { n=$((n + 1)); printf 'PASS  %s\n' "$1"; }
fail() { n=$((n + 1)); fails=$((fails + 1)); printf 'FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; }
has() { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "missing: $3" ;; esac; }
lacks() { case "$2" in *"$3"*) fail "$1" "present: $3" ;; *) pass "$1" ;; esac; }

echo "=== 1. the real log, read-only: the audience marks, and marked rulings read as rulings"
REAL_LOG="$HOME/obsidian/00-09 System/03 Agents/03.16 Cross-session log/CROSS-SESSION.md"
if [ -f "$REAL_LOG" ]; then
  pop=$(python3 - "$HOOK" "$REAL_LOG" <<'PY'
import importlib.util, re, sys
spec = importlib.util.spec_from_file_location("hook", sys.argv[1]); hook = importlib.util.module_from_spec(spec); spec.loader.exec_module(hook)
entries = hook.split_entries(open(sys.argv[2], errors="replace").read())
heads = [e.split("\n", 1)[0] for _, e in entries]
f = sum(1 for h in heads if re.search(r"\s·\s*for:", h)); s = sum(1 for h in heads if re.search(r"\s·\s*ships?:", h)); fl = sum(1 for h in heads if re.search(r"\s·\s*fleet\s*$|\s·\s*fleet\s·|ships?:[^·]*\bfleet\b", h))
def kind(h):
    m = re.search(r"·.*?\s[—–-]\s*(.*)$", h); return m.group(1) if m else ""
marked = [h for h in heads if re.search(r"\s·\s*(for:|ships?:|fleet)", h) and re.match(r"rulings?\b", kind(h), re.I)]
missed = [h for h in marked if not hook.is_ruling(h)]
for h in missed: print("      missed:", h[:120], file=sys.stderr)
print("entries=%d for=%d ships=%d fleet=%d marked_rulings=%d missed=%d" % (len(heads), f, s, fl, len(marked), len(missed)))
PY
)
  printf '      %s\n' "$pop"
  entries=$(printf '%s' "$pop" | sed -E 's/.*entries=([0-9]+).*/\1/'); missed=$(printf '%s' "$pop" | sed -E 's/.*missed=([0-9]+).*/\1/')
  if [ "${entries:-0}" -gt 50 ] 2>/dev/null; then pass "the population is real ($entries entries)"; else fail "the population is real" "$pop"; fi
  if [ "$missed" = 0 ]; then pass "every marked ruling in the real log reads as a ruling"; else fail "every marked ruling in the real log reads as a ruling" "$missed missed"; fi
else
  n=$((n + 2)); skips=$((skips + 2)); printf 'SKIP  the real-log population (2 checks): no log at %s\n' "$REAL_LOG"
fi

# --- fixtures -------------------------------------------------------------------------------------------------
T=$(mktemp -d "${TMPDIR:-/tmp}/audience.XXXXXX") || exit 1
trap '/usr/bin/trash "$T" 2>/dev/null || true' EXIT
H="$T/home"; AG="$H/obsidian/00-09 System/03 Agents"; LOGDIR="$AG/03.16 Cross-session log"
NB="$AG/03.04 Records/Agent notebook/2026-09"; AR="$AG/03.09 Archive/Agent notebook/2026-09"
mkdir -p "$LOGDIR" "$NB" "$AR" "$H/.claude/jobs" "$H/.claude/sessions" "$T/stubbin"
LOG="$LOGDIR/CROSS-SESSION.md"
printf '#!/bin/sh\ncat "%s/listing.json" 2>/dev/null || echo "[]"\n' "$T" > "$T/stubbin/claude"; chmod +x "$T/stubbin/claude"
echo '[]' > "$T/listing.json"
day=$(date -v-1d +%Y-%m-%d)  # yesterday: every fixture stamp is in the past, whatever the hour, so the clamp to now never touches them
sid() { printf '%s-0000-0000-0000-000000000000' "$1"; }
job() { mkdir -p "$H/.claude/jobs/$1"; printf '{"template":"%s"}\n' "$2" > "$H/.claude/jobs/$1/state.json"; }
reg() {  # reg <8-hex id> <name> [former name]: one registry row, as ~/.claude/sessions/<pid>.json holds it
  if [ -n "${3:-}" ]; then fm=$(printf '[{"name":"%s","until":1,"sessionId":"%s"}]' "$3" "$(sid "$1")"); else fm='[]'; fi
  printf '{"pid":1,"sessionId":"%s","name":"%s","formerNames":%s}\n' "$(sid "$1")" "$2" "$fm" > "$H/.claude/sessions/$1.json"
}
entry() {  # entry <dir> <stamp HHMM> <bare name> <session label> <reports-to>: one notebook entry
  printf -- '---\ntype: Event/AgentNotebookEntry\nsession: "%s"\nstatus: draft/running\nreports-to: "%s"\n---\n\n## What happened\n' "$4" "$5" > "$1/Agent session 2026-09-30T$2 $3.md"
}
seed() { mkdir -p "$H/.local/share/cross-session-hook"; printf '%s' "$2" > "$H/.local/share/cross-session-hook/$(sid "$1")"; }
state_of() { cat "$H/.local/share/cross-session-hook/$(sid "$1")" 2>/dev/null; }
inject() {
  printf '{"session_id":"%s"}' "$(sid "$1")" | HOME="$H" PATH="$T/stubbin:$PATH" python3 "$HOOK" \
    | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception: print("")'
}
# THE TREE: [A0] rear admiral <- [C0-CC] claude code <- [C1-CC] plugins <- [L0-CC] worker; and [C1-OB] spec on the obsidian ship.
entry "$NB" 0100 "rear admiral" "[A0] rear admiral" ""
entry "$NB" 0101 "claude code" "[C0-CC] claude code" "[A0] rear admiral"
entry "$NB" 0102 "plugins" "[C1-CC] plugins" "[C0-CC] claude code"
entry "$AR" 0103 "worker" "[L0-CC] worker" "[C1-CC] plugins"
entry "$NB" 0104 "spec" "[C1-OB] spec" "[C0-OB] obsidian"
entry "$NB" 0105 "stranger" "[L0-CC] stranger" "[C1-CC] plugins"
job 11111111 commander;  reg 11111111 "[C1-CC] plugins"
job 22222222 lieutenant; reg 22222222 "[L0-CC] worker"
job 33333333 commander;  reg 33333333 "[C1-OB] spec"
r() { printf '## %sT%s · [A0] rear admiral — ruling%s\n%s\n\n' "$day" "$1" "$2" "$3"; }
{ printf -- '---\naudience: fleet\n---\n\n'
  r 00:10 " · for: [C1-CC] plugins" "RULE-FOR-PLUGINS"
  r 00:11 " · for: [L0-CC] worker" "RULE-FOR-WORKER"
  r 00:12 " · for: [C0-CC] claude code" "RULE-FOR-CAPTAIN"
  r 00:13 " · ships: CC" "RULE-SHIPS-CC"
  r 00:14 " · ships: OB, HS" "RULE-SHIPS-OB-HS"
  r 00:15 " · fleet" "RULE-FLEET"
  r 00:16 "" "RULE-NO-MARK"
  r 00:17 " · ships: fleet" "RULE-SHIPS-FLEET"
  r 00:18 " · ships: HS" "RULE-SHIPS-HS naming [L0-CC] worker in its body"
  r 00:19 " · for: [C1-OB] spec" "RULE-FOR-SPEC"
} > "$LOG"

echo
echo "=== 2. a commander on CC: for-self, for-subordinate, not for-superior, ships, fleet, no mark"
seed 11111111 "${day}T00:00"; out=$(inject 11111111)
has   "for: itself reaches it" "$out" "RULE-FOR-PLUGINS"
has   "for: a subordinate (worker, in the archive root) reaches its superior" "$out" "RULE-FOR-WORKER"
lacks "for: its superior does NOT reach it" "$out" "RULE-FOR-CAPTAIN"
has   "ships: CC reaches a CC session" "$out" "RULE-SHIPS-CC"
lacks "ships: OB, HS does not reach a CC session" "$out" "RULE-SHIPS-OB-HS"
has   "fleet reaches it" "$out" "RULE-FLEET"
has   "ships: fleet reaches it" "$out" "RULE-SHIPS-FLEET"
has   "a ruling with no mark reaches it (fail-open)" "$out" "RULE-NO-MARK"
lacks "for: a session on another ship does not reach it" "$out" "RULE-FOR-SPEC"
has   "the header says how many were left out" "$out" "for other sessions or ships were left out"

echo
echo "=== 3. a commander on OB: ships match by list"
seed 33333333 "${day}T00:00"; out=$(inject 33333333)
has   "ships: OB, HS reaches an OB session" "$out" "RULE-SHIPS-OB-HS"
lacks "ships: CC does not reach an OB session" "$out" "RULE-SHIPS-CC"
has   "for: itself reaches the OB commander" "$out" "RULE-FOR-SPEC"

echo
echo "=== 4. a lieutenant: ships do not reach it; fleet, no mark, for-self and naming it do"
seed 22222222 "${day}T00:00"; out=$(inject 22222222)
has   "for: itself reaches the lieutenant" "$out" "RULE-FOR-WORKER"
lacks "ships: its own ship does NOT reach a lieutenant" "$out" "RULE-SHIPS-CC"
has   "fleet reaches a lieutenant" "$out" "RULE-FLEET"
has   "no mark reaches a lieutenant" "$out" "RULE-NO-MARK"
has   "a ruling that names the lieutenant reaches it, whatever its ship mark" "$out" "RULE-SHIPS-HS"
lacks "for: its superior does NOT reach a lieutenant" "$out" "RULE-FOR-PLUGINS"
has   "the lieutenant's header says ships do not reach it" "$out" "marks do not reach you"

echo
echo "=== 5. former labels: the registry's formerNames, one rename in the ledger, and two in a row"
job 44444444 lieutenant; reg 44444444 "[L0-CC] new name" "[L0-CC] old name"
job 55555555 lieutenant; reg 55555555 "[L0-CC] third"
job 66666666 lieutenant; reg 66666666 "[L0-CC] after"
{ printf -- '---\naudience: fleet\n---\n\n'
  printf '## %sT00:20 · [L0-CC] second — notebook entry renamed to match the session'"'"'s name\n\nRenamed `Agent session 2026-09-30T0100 first.md` to `Agent session 2026-09-30T0100 second.md` by `rename-notebook.sh` (sessionId %s): mv. The entry'"'"'s `session:` now reads `[L0-CC] second`.\n\n' "$day" "$(sid 55555555)"
  printf '## %sT00:21 · [L0-CC] third — notebook entry renamed to match the session'"'"'s name\n\nRenamed `Agent session 2026-09-30T0100 second.md` to `Agent session 2026-09-30T0100 third.md` by `rename-notebook.sh` (sessionId %s): mv.\n\n' "$day" "$(sid 55555555)"
  printf '## %sT00:22 · [L0-CC] after — notebook entry renamed to match the session'"'"'s name\n\nRenamed `Agent session 2026-09-30T0100 before.md` to `Agent session 2026-09-30T0100 after.md` by `rename-notebook.sh` (sessionId %s): mv.\n\n' "$day" "$(sid 66666666)"
  r 00:30 " · for: [L0-CC] old name" "RULE-FOR-OLD-NAME"
  r 00:31 " · for: [L0-CC] second" "RULE-FOR-SECOND"
  r 00:32 " · for: [L0-CC] first" "RULE-FOR-FIRST"
  r 00:33 " · for: [L0-CC] before" "RULE-FOR-BEFORE"
  r 00:34 " · for: [L0-CC] stranger" "RULE-FOR-STRANGER"
} > "$LOG"
seed 44444444 "${day}T00:00"; out=$(inject 44444444)
has   "a former label from the registry's formerNames matches" "$out" "RULE-FOR-OLD-NAME"
lacks "a stranger's for: does not reach it" "$out" "RULE-FOR-STRANGER"
seed 66666666 "${day}T00:00"; out=$(inject 66666666)
has   "one rename in the ledger: for: the old label reaches the renamed session (no registry former name)" "$out" "RULE-FOR-BEFORE"
seed 55555555 "${day}T00:00"; out=$(inject 55555555)
has   "two renames in a row: for: the middle label reaches the session" "$out" "RULE-FOR-SECOND"
has   "two renames in a row: for: the first label reaches the session" "$out" "RULE-FOR-FIRST"
lacks "two renames in a row: another session's old label does not" "$out" "RULE-FOR-BEFORE"

echo
echo "=== 6. a cyclic chain and a missing link: not shown by for:, the other rules still apply"
entry "$NB" 0110 "loop a" "[L0-CC] loop a" "[C2-CC] loop b"
entry "$NB" 0111 "loop b" "[C2-CC] loop b" "[L0-CC] loop a"
entry "$NB" 0112 "orphan" "[L0-CC] orphan" "[C1-CC] nobody"
{ printf -- '---\naudience: fleet\n---\n\n'
  r 00:40 " · for: [L0-CC] loop a" "RULE-FOR-LOOP"
  r 00:41 " · for: [L0-CC] orphan" "RULE-FOR-ORPHAN"
  r 00:42 " · for: [L0-CC] loop a · ships: CC" "RULE-LOOP-AND-SHIPS"
} > "$LOG"
seed 11111111 "${day}T00:00"; out=$(inject 11111111)
lacks "a cyclic chain does not reach an outside session (and the hook ends)" "$out" "RULE-FOR-LOOP"
lacks "a missing link does not reach it" "$out" "RULE-FOR-ORPHAN"
has   "a broken chain still lets ships: CC through" "$out" "RULE-LOOP-AND-SHIPS"

echo
echo "=== 7. the stamp: never past an unshown ruling FOR this session; past one that is not for it"
{ printf -- '---\naudience: fleet\n---\n\n'
  for i in 10 11 12 13 14 15; do
    printf '## %sT02:%s · [A0] rear admiral — ruling · for: [C1-CC] plugins\nMINE%s %s\n\n' "$day" "$i" "$i" "$(python3 -c 'print("m" * 900)')"
    printf '## %sT02:%s · [A0] rear admiral — ruling · for: [C1-OB] spec\nTHEIRS%s\n\n' "$day" "$((i + 20))" "$i"
  done
} > "$LOG"
seed 11111111 "${day}T00:00"; seen=""; rounds=0
while [ "$rounds" -lt 10 ]; do
  out=$(inject 11111111); rounds=$((rounds + 1))
  case "$out" in *THEIRS*) fail "a ruling for another session is never shown" "round $rounds"; break ;; esac
  new=$(printf '%s' "$out" | grep -oE '^MINE[0-9]+' | tr '\n' ' ')
  [ -n "$new" ] || break
  seen="$seen$new"
done
all=$(printf '%s' "$seen" | tr ' ' '\n' | grep . | sort -u | tr '\n' ' ')
if [ "$all" = "MINE10 MINE11 MINE12 MINE13 MINE14 MINE15 " ]; then pass "over several starts every ruling for it is shown, none skipped ($rounds starts)"; else fail "every ruling for it is shown, none skipped" "shown: $all"; fi
if [ "$rounds" -gt 2 ]; then pass "the cap made it take more than one start"; else fail "the cap made it take more than one start" "$rounds starts"; fi
st=$(state_of 11111111)
if [ "$st" = "${day}T02:35" ]; then pass "once its rulings are shown, the stamp passes the rulings not for it"; else fail "the stamp passes the rulings not for it" "stamp $st"; fi
# THE PROOF THE OTHER WAY, by property: random logs mixing rulings FOR this session, for others, unmarked, and claims, with random stamps (ties included) and random lengths across the cap. After every start, every ruling the filter keeps whose stamp is at or below the new stamp must have been shown at this start or an earlier one. If it fails, the seed is printed.
python3 - "$HOOK" "$H" "$T" "$(sid 11111111)" "$LOG" "$day" <<'PY2' && pass "random walks over mixed audiences: the stamp never passes a kept ruling unshown" || fail "random walks over mixed audiences: the stamp never passes a kept ruling unshown"
import json, os, random, subprocess, sys
hook, H, T, sid, log, day = sys.argv[1:7]
state = os.path.join(H, ".local/share/cross-session-hook", sid)
env = dict(os.environ, HOME=H, PATH=os.path.join(T, "stubbin") + ":" + os.environ["PATH"])
kinds = [" · for: [C1-CC] plugins", " · for: [L0-CC] worker", " · for: [C1-OB] spec", " · ships: OB", " · ships: CC", "", " · fleet"]
kept_kinds = {0, 1, 4, 5, 6}
for seed in range(6):
    rnd = random.Random(seed)
    rows = []
    with open(log, "w") as f:
        f.write("---\naudience: fleet\n---\n\n")
        for i in range(14):
            m = rnd.randint(0, 20)
            stamp = "%sT04:%02d" % (day, m)
            if rnd.random() < 0.25:
                f.write("## %s · [L0-CC] x — claim\nCLAIM\n\n" % stamp); continue
            k = rnd.randrange(len(kinds)); tag = "R%d_%d" % (seed, i)
            f.write("## %s · [A0] rear admiral — ruling%s\n%s %s\n\n" % (stamp, kinds[k], tag, "z" * rnd.randint(10, 1500)))
            if k in kept_kinds: rows.append((stamp, tag))
    with open(state, "w") as f: f.write("%sT03:59" % day)
    seen = set()
    for start in range(14):
        out = subprocess.run(["python3", hook], input=json.dumps({"session_id": sid}), capture_output=True, text=True, env=env).stdout
        ctx = json.loads(out)["hookSpecificOutput"]["additionalContext"] if out.strip() else ""
        seen |= {t for _, t in rows if t + " " in ctx}
        st = open(state).read().strip()
        lost = [t for s_, t in rows if s_ <= st and t not in seen]
        if lost:
            print("seed %d start %d: stamp %s passed unshown kept rulings %s" % (seed, start, st, lost)); sys.exit(1)
    if seen != {t for _, t in rows}:
        print("seed %d: never shown %s" % (seed, sorted({t for _, t in rows} - seen))); sys.exit(1)
PY2

echo
echo "=== 7b. the heading grammar (agreed with the obsidian ship, 2026-09-30): one check per case"
gram=$(python3 - "$HOOK" <<'PY2'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("hook", sys.argv[1]); hook = importlib.util.module_from_spec(spec); spec.loader.exec_module(hook)
if not hasattr(hook, "marks"): print("no-marks"); sys.exit()
h = "## 2026-09-30T05:00 · [A0] rear admiral — ruling"
cases = [
  ("fleet is canonical",                          h + " · fleet",                          ([], set(), True)),
  ("ships: fleet is accepted as fleet",           h + " · ships: fleet",                   ([], set(), True)),
  ("ships: comma-separated, spaces optional",     h + " · ships: PE,HH, ob",               ([], {"PE", "HH", "OB"}, False)),
  ("for: takes ONE label, a comma stays in it",   h + " · for: [L0-CC] a, b",              (["[L0-CC] a, b"], set(), False)),
  ("for: repeats for several labels",             h + " · for: [L0-CC] a · for: [C1-CC] b", (["[L0-CC] a", "[C1-CC] b"], set(), False)),
  ("segments combine as a union",                 h + " · for: [L0-CC] a · ships: MA · fleet", (["[L0-CC] a"], {"MA"}, True)),
  ("an unrecognised segment is ignored",          h + " · ships: MA · urgent",              ([], {"MA"}, False)),
  ("a lone typo (ship:) is no marker",            h + " · ship: PE",                       ([], set(), False)),
  ("a ships: value that is not a code goes to everyone", h + " · ships: MA (dotfiles)",   ([], set(), True)),
  ("ships: MA and CC is not a code list: everyone",   h + " · ships: MA and CC",         ([], set(), True)),
  ("no marker is no marker",                      h,                                       ([], set(), False)),
  ("a note in brackets before the marks",         h + " (correction) · ships: MA",         ([], {"MA"}, False)),
]
for name, head, want in cases:
    got = hook.marks(head)
    print(("ok " if (got[0], got[1], got[2]) == want else "BAD ") + name + ("" if (got[0], got[1], got[2]) == want else " -> %r" % (got,)))
PY2
)
case "$gram" in no-marks) fail "the hook has a heading-grammar parser (marks)" "none on this hook" ;;
  *) while IFS= read -r line; do case "$line" in "ok "*) pass "grammar: ${line#ok }" ;; *) fail "grammar: ${line#BAD }" ;; esac; done <<EOF
$gram
EOF
  ;; esac
job 99999999 lieutenant; reg 99999999 "[L0-CC] typo reader"
{ printf -- '---\naudience: fleet\n---\n\n'
  r 05:00 " · ship: PE" "RULE-TYPO-MARK"
  r 05:01 " · ships: PE" "RULE-SHIPS-PE"
  printf '## %sT05:02 · [L0-CC] x — claim · for: [L0-CC] typo reader\nCLAIM-FOR-ME\n\n' "$day"
} > "$LOG"
seed 99999999 "${day}T00:00"; out=$(inject 99999999)
has   "end to end: a heading whose only segment is a typo goes to everyone (fail-open for a slip)" "$out" "RULE-TYPO-MARK"
lacks "end to end: a correct ships: PE does not reach a CC lieutenant" "$out" "RULE-SHIPS-PE"
lacks "only ruling headings are read for marks: a claim marked for: this session is still a claim" "$out" "CLAIM-FOR-ME"

echo
echo "=== 7c. the review's fail-open cases: a slip or an unreadable record shows more, never less"
{ printf -- '---\naudience: fleet\n---\n\n'
  r 06:00 " · for: [L0-CC] nobody we know" "RULE-FOR-UNKNOWN-LABEL"
  r 06:01 " · for: \`[C1-CC] Plugins\`" "RULE-FOR-BACKTICKED-CASE"
  r 06:02 " · ships: MA (dotfiles)" "RULE-SHIPS-JUNK"
  r 06:03 " · for: [L0-CC] worker" "RULE-FOR-WORKER-AGAIN"
  r 06:04 " · ships: OBS" "RULE-SHIPS-UNKNOWN-CODE"
} > "$LOG"
seed 33333333 "${day}T00:00"; out=$(inject 33333333)
has   "a for: label the fleet has no record of goes to everyone (a slip)" "$out" "RULE-FOR-UNKNOWN-LABEL"
has   "a ships: value that is not a code goes to everyone" "$out" "RULE-SHIPS-JUNK"
has   "a ships: code the ship table does not know (OBS) goes to everyone" "$out" "RULE-SHIPS-UNKNOWN-CODE"
lacks "a known for: label on another ship still does not reach it" "$out" "RULE-FOR-WORKER-AGAIN"
seed 11111111 "${day}T00:00"; out=$(inject 11111111)
has   "a for: label in backticks and another case still matches" "$out" "RULE-FOR-BACKTICKED-CASE"
seed 22222222 "${day}T00:00"; out=$(inject 22222222)
has   "an unknown ship code reaches a lieutenant too (a slip is fleet-wide)" "$out" "RULE-SHIPS-UNKNOWN-CODE"
# The notebook cannot be read: both roots moved away for one run.
mv "$AG/03.04 Records" "$T/hide-records"; mv "$AG/03.09 Archive" "$T/hide-archive"
seed 33333333 "${day}T00:00"; out=$(inject 33333333)
mv "$T/hide-records" "$AG/03.04 Records"; mv "$T/hide-archive" "$AG/03.09 Archive"
has   "with the notebook unreadable, a for: ruling is shown (fail open)" "$out" "RULE-FOR-WORKER-AGAIN"
# A commander whose name carries no ship code is shown ships: rulings.
job abababab commander; reg abababab "[C1] shipless"
{ printf -- '---\naudience: fleet\n---\n\n'; r 06:10 " · ships: HS" "RULE-SHIPS-FOR-SHIPLESS"; } > "$LOG"
seed abababab "${day}T00:00"; out=$(inject abababab)
has   "a session whose name has no ship code is shown ships: rulings" "$out" "RULE-SHIPS-FOR-SHIPLESS"
# Naming is a whole label in the body, not inside a longer one and not the heading's author.
job cdcdcdcd lieutenant; reg cdcdcdcd "[L0-CC] dot"
{ printf -- '---\naudience: fleet\n---\n\n'
  r 06:20 " · ships: MA" "RULE-NAMES-LONGER: the [L0-CC] dotfiles session acts."
  printf '## %sT06:21 · [L0-CC] dot — ruling · ships: OB\nRULE-AUTHORED-BY-IT\n\n' "$day"
  r 06:22 " · ships: MA" "RULE-NAMES-IT: [L0-CC] dot acts."
} > "$LOG"
seed cdcdcdcd "${day}T00:00"; out=$(inject cdcdcdcd)
lacks "a longer label does not count as naming a shorter one" "$out" "RULE-NAMES-LONGER"
lacks "a ruling's author segment does not count as naming it" "$out" "RULE-AUTHORED-BY-IT"
has   "a body that names it whole reaches it" "$out" "RULE-NAMES-IT"

echo
echo "=== 7d. the ship table unreadable: every ships: ruling shown to every rank, and the calls stop after the first failure"
unit=$(HOME="$H" PATH="$T/stubbin:$PATH" python3 - "$HOOK" "$(sid 22222222)" <<'PY2'
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("hook", sys.argv[1]); hook = importlib.util.module_from_spec(spec); spec.loader.exec_module(hook)
if not hasattr(hook, "ShipTable"): print("no-table"); sys.exit()
hook.FLEET_RANKS = Path("/nonexistent/_fleet-ranks.sh")
aud = hook.Audience(sys.argv[2], 3, [])
e = "## 2026-09-30T05:00 · [A0] rear admiral — ruling · ships: HS\nbody"
print("l0-shown" if aud.shows(e) else "l0-hidden")
for i in range(5): aud.table.prime(["[L0-CC] x%d" % i])
print("calls=%d" % aud.table.calls)
PY2
)
case "$unit" in no-table) fail "the hook has a ship table" "none" ;; *)
  has "an unreadable table shows a ships: ruling to a lieutenant" "$unit" "l0-shown"
  has "after one failed call the table makes no more calls" "$unit" "calls=1" ;; esac

echo
echo "=== 7e. a renamed superior: its subordinates' reports-to still names the old label"
job efefefef commander; reg efefefef "[C1-CC] new boss"
entry "$NB" 0120 "sub" "[L0-CC] sub" "[C1-CC] old boss"
{ printf -- '---\naudience: fleet\n---\n\n'
  printf '## %sT07:00 · [C1-CC] new boss — notebook entry renamed to match the session'"'"'s name\n\nRenamed `Agent session 2026-09-30T0119 old boss.md` to `Agent session 2026-09-30T0119 new boss.md` by `rename-notebook.sh` (sessionId %s): mv.\n\n' "$day" "$(sid efefefef)"
  r 07:01 " · for: [L0-CC] sub" "RULE-FOR-SUB-OF-RENAMED"
} > "$LOG"
seed efefefef "${day}T00:00"; out=$(inject efefefef)
has "for: a subordinate whose reports-to is the superior's old label reaches the renamed superior" "$out" "RULE-FOR-SUB-OF-RENAMED"
unit=$(HOME="$H" PATH="$T/stubbin:$PATH" python3 - "$HOOK" "$(sid efefefef)" "$LOG" <<'PY2'
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("hook", sys.argv[1]); hook = importlib.util.module_from_spec(spec); spec.loader.exec_module(hook)
if not hasattr(hook, "ShipTable"): print("no-table"); sys.exit()
entries = hook.split_entries(open(sys.argv[3]).read())
aud = hook.Audience(sys.argv[2], 1, entries)
hook.FLEET_RANKS = Path("/nonexistent/_fleet-ranks.sh")
print("JOIN=%s dead=%s" % ("yes" if aud.is_me("[C1-CC] old boss") else "no", aud.table.dead))
PY2
)
has "with the ship table dead, a bare pre-rename name still joins its session (fail open)" "$unit" "JOIN=yes dead=True"

echo
echo "=== 8. a session whose own label cannot be told: nothing is filtered"
job 77777777 lieutenant
{ printf -- '---\naudience: fleet\n---\n\n'; r 03:00 " · for: [C1-OB] spec" "RULE-UNKNOWN-SELF"; } > "$LOG"
seed 77777777 "${day}T00:00"; out=$(inject 77777777)
has "an unnamed session below captain still gets a for: ruling (fail toward more reading)" "$out" "RULE-UNKNOWN-SELF"

echo
echo "=== 9. captains keep the full delta"
job 88888888 captain; reg 88888888 "[C0-OB] obsidian"
{ printf -- '---\naudience: fleet\n---\n\n'; r 03:10 " · for: [L0-CC] worker" "RULE-CAPTAIN-SEES"; } > "$LOG"
seed 88888888 "${day}T00:00"; out=$(inject 88888888)
has "a captain on another ship still gets a for: ruling" "$out" "RULE-CAPTAIN-SEES"

echo
printf '%d checks, %d failed, %d skipped\n' "$n" "$fails" "$skips"
[ "$fails" = 0 ]
