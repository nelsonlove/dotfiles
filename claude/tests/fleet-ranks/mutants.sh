#!/usr/bin/env bash
# Mutation runner for `session-roster.sh`: breaks each guard in turn and requires the suite to notice.
#
# WHY THIS FILE EXISTS. Across eight review rounds on #71, three assertions in the roster suite were green for
# a reason that had nothing to do with the code they named: a fixture whose trigger line was indented so the
# bug it existed to catch never matched it; a fixture whose comment carried no apostrophe, so a greedy match
# and a first-match match gave the same answer; and a fixture with no indented `status:` in a test named for
# indented keys. Each was counted as coverage. None was found by reading — a reviewer found one, and the other
# two were found by running the mutation by hand, which is a thing that only happens when somebody remembers.
#
# `claude/tests/README.md` already requires proving a suite can FAIL. This makes that requirement executable:
# every guard worth having has a named mutant here, the runner applies each one to a COPY of the tree, and a
# mutant that does not turn the suite red is reported as an untested guard. A guard nobody has watched fail is
# a guard nobody has tested, and "I ran it by hand once" is not a property of the repository.
#
#   claude/tests/fleet-ranks/mutants.sh            # every mutant
#   claude/tests/fleet-ranks/mutants.sh <name>…    # only these
#
# ADDING A GUARD MEANS ADDING A MUTANT. A `mutant` block is: a name, a file, and a python snippet that breaks
# exactly one thing. Keep each one minimal — a mutant that breaks two things can pass for the wrong reason as
# easily as a test can.
set -u

HERE=$(cd "$(dirname "$0")" && pwd -P)
ROOT=$(cd "$HERE/../../.." && pwd -P)
SUITE_REL="claude/tests/fleet-ranks/session-roster.sh"

pass=0; fail=0; ran=0
WANT="$*"

# THE BASELINE COMES FIRST, and nothing is reported if it fails. A mutation runner proves that a BROKEN tree
# turns the suite red; that means nothing unless the UNBROKEN copy is green. The first version of this file
# copied `bin`, `lib` and `tests` and not `hooks`, so every hook mutant hit a missing file and every other
# mutant ran against a tree whose suite was failing about thirty checks on its own — and the runner called
# them all caught. It was the same "green for the wrong reason" defect it exists to catch, one level up, and
# it was found by asking why the numbers were so large rather than by reading the code.
baseline=$(mktemp -d -t rosterbase)
mkdir -p "$baseline/claude"
cp -R "$ROOT/claude/bin" "$ROOT/claude/lib" "$ROOT/claude/hooks" "$ROOT/claude/tests" "$baseline/claude/" 2>/dev/null
if ! ROSTER_REAL_AGENTS=/nonexistent bash "$baseline/$SUITE_REL" >"$baseline/out" 2>&1; then
  printf 'BASELINE FAILED: the unmutated copy does not pass, so no mutant result here means anything.\n'
  grep -E '^FAIL' "$baseline/out" | head -5
  rm -rf "$baseline"
  exit 2
fi
printf 'baseline: the unmutated copy passes (%s)\n\n' "$(tail -n 1 "$baseline/out")"
rm -rf "$baseline"

# Each mutant runs against a fresh copy of the repo's `claude/` tree, so a broken mutant can never leave the
# working tree damaged — the failure mode of running these in place, which is how a review round nearly ended
# with a half-reverted library on disk.
mutant() {  # mutant <name> <file-relative-to-root> <python-snippet>
  mu_name="$1"; mu_file="$2"; mu_code="$3"
  if [ -n "$WANT" ]; then
    case " $WANT " in *" $mu_name "*) ;; *) return 0 ;; esac
  fi
  ran=$((ran + 1))
  mu_tmp=$(mktemp -d -t rostermut)
  mkdir -p "$mu_tmp/claude"
  cp -R "$ROOT/claude/bin" "$ROOT/claude/lib" "$ROOT/claude/hooks" "$ROOT/claude/tests" "$mu_tmp/claude/" 2>/dev/null

  # EVERY EDIT IS CHECKED, not just the mutant as a whole. `rep` and `cut` raise when their anchor matches
  # nothing, so a multi-edit mutant whose second anchor has gone stale is reported STALE instead of passing on
  # the strength of its first. The ninth reviewer named this: a mutant that edits two things can be caught by
  # one of them and vouch for the other, which is the runner committing the defect it exists to find.
  if ! MU_PATH="$mu_tmp/$mu_file" python3 -c "
import os, pathlib, sys
p = pathlib.Path(os.environ['MU_PATH'])
s = p.read_text()
before = s

def rep(old, new):
    global s
    if old not in s:
        raise SystemExit('an anchor matched nothing: ' + repr(old[:60]))
    s = s.replace(old, new)

def cut(start_at, end_at):
    global s
    if start_at not in s or end_at not in s:
        raise SystemExit('a cut anchor matched nothing: ' + repr(start_at[:60]))
    a = s.index(start_at); b = s.index(end_at)
    s = s[:a] + s[b:]

$mu_code
if s == before:
    sys.stderr.write('the mutant changed nothing — its anchor has moved\n')
    sys.exit(3)
p.write_text(s)
" 2>"$mu_tmp/why"; then
    printf 'STALE %-46s %s\n' "$mu_name" "$(tr -d '\n' < "$mu_tmp/why")"
    fail=$((fail + 1)); rm -rf "$mu_tmp"; return 0
  fi

  # The real notebook is skipped here on purpose: this asks whether the FIXTURES catch the mutant, and the
  # live-corpus section costs about ninety seconds a run. A reviewer of this branch abandoned his own mutation
  # run after two of six mutants for exactly that reason, and judged the rest by reading.
  if ROSTER_REAL_AGENTS=/nonexistent bash "$mu_tmp/$SUITE_REL" >"$mu_tmp/out" 2>&1; then
    printf 'GREEN %-46s THE SUITE DID NOT NOTICE — this guard is untested\n' "$mu_name"
    fail=$((fail + 1))
  else
    printf 'red   %-46s %s\n' "$mu_name" "$(grep -cE '^FAIL' "$mu_tmp/out" || true) check(s) failed"
    pass=$((pass + 1))
  fi
  rm -rf "$mu_tmp"
}

# --- the hook: whose record it writes into ----------------------------------------------------------------
mutant hook-foreign-id claude/hooks/notebook-name-sync.sh '
rep("""  if [ -n "$rw_existing" ] && [ "$rw_existing" != "$sid" ]; then""",
              """  if false; then""")
'
mutant hook-duplicate-keys claude/hooks/notebook-name-sync.sh '
rep("""            END { exit (bad ? 1 : 0) }\x27 "$rw_entry" 2>/dev/null; then
    printf \x27notebook-name-sync: %s states session-id""",
              """            END { exit 0 }\x27 "$rw_entry" 2>/dev/null; then
    printf \x27notebook-name-sync: %s states session-id""")
'
mutant hook-backslash claude/hooks/notebook-name-sync.sh '
bs = chr(92); dq = chr(34); sq = chr(39)
old = "  case " + dq + "$rw_cwd" + dq + "   in *[" + bs + bs + "]*|*" + sq + dq + sq + "*|*[[:cntrl:]]*)"
new = "  case " + dq + "$rw_cwd" + dq + "   in *" + sq + bs + bs + sq + "*|*" + sq + dq + sq + "*)"
rep(old, new)
'

mutant hook-ownership-whole-file claude/hooks/notebook-name-sync.sh '
rep("""    if rc_fm_id "$rc_f" "$2"; then""",
              """    if grep -qE "^session-id[[:space:]]*:.*$2" "$rc_f" 2>/dev/null; then""")
'
mutant hook-candidate-order claude/hooks/notebook-name-sync.sh '
rep("""  printf \x27%s\x27 "$rc_mine"\n  printf \x27%s\x27 "$rc_rest" | sort -r""",
              """  printf \x27%s%s\x27 "$rc_mine" "$rc_rest\"""")
'

# --- the readers: which line of a record is the record --------------------------------------------------
mutant reader-indented-key claude/lib/session-roster.sh '
rep("""    | grep -E "^$2[[:space:]]*:" \\""", """    | grep -E "^[[:space:]]*$2[[:space:]]*:" \\""")
'
mutant reader-unclosed-block claude/lib/session-roster.sh '
rep("""END { if (!bad && closed) printf "%s", buf }""", """END { printf "%s", buf }""")
'
mutant reader-greedy-double-quote claude/lib/session-roster.sh '
rep("""sed -E \x27s/^"([^"]*)".*$/\\1/\x27""", """sed -E \x27s/^"(.*)".*$/\\1/\x27""")
'
mutant reader-greedy-single-quote claude/lib/session-roster.sh '
rep("""s/^\x27([^\x27]*)\x27.*\\$/\\1/""", """s/^\x27(.*)\x27.*\\$/\\1/""")
'
mutant status-indented-key claude/lib/session-status.sh '
rep("""| grep -E "^$2[[:space:]]*:" \\""", """| grep -E "^[[:space:]]*$2[[:space:]]*:" \\""")
rep("""| sed -E "s/^$2[[:space:]]*:[[:space:]]*//" \\""", """| sed -E "s/^[[:space:]]*$2[[:space:]]*:[[:space:]]*//" \\""")
'
mutant wake-index-indented-keys claude/bin/wake-session.sh '
for k in ("session", "session-status", "status"):
    rep("(match($0, \"^%s[ \\t]*:[ \\t]*\"))" % k, "(match($0, \"^[ \\t]*%s[ \\t]*:[ \\t]*\"))" % k)
rep("(match($0, \"^\" key \"[ \\t]*:[ \\t]*\"))", "(match($0, \"^[ \\t]*\" key \"[ \\t]*:[ \\t]*\"))")
'

# --- selection: which entry is the newest for an id -------------------------------------------------------
mutant selection-parsed-id claude/lib/session-roster.sh '
rep("""    roster_entry_may_be_id "$ros_f" "$ros_id" || continue""",
              """    roster_read "$ros_f"; [ "$roster_id" = "$ros_id" ] || continue""")
'
mutant selection-anchored claude/lib/session-roster.sh '
rep("""  grep -qE "^session-id[[:space:]]*:.*$2" "$1" 2>/dev/null""",
              """  grep -qE "^session-id[[:space:]]*:[[:space:]]*[\\"\x27]?$2[\\"\x27]?[[:space:]]*$" "$1" 2>/dev/null""")
'

# THE WHOLE-CAUSE COMPARISON. The de-duplication used to test a bare substring, so a filename that is a SUFFIX
# of another suppressed it and one name silently vanished from the reason. Fixed, and then pinned by nothing at
# all — which is the shape of mistake this whole runner exists to stop, made once more in the commit that
# corrected it.
mutant order-reason-substring claude/lib/session-roster.sh '
rep("""      case "; $roster_order_reason" in *"; $ros_cause"*) ;; *) roster_order_reason="${roster_order_reason:+$roster_order_reason; }$ros_cause" ;; esac
    elif""",
    """      case "$roster_order_reason" in *"${ros_f##*/} carries no timestamp"*) ;; *) roster_order_reason="${roster_order_reason:+$roster_order_reason; }$ros_cause" ;; esac
    elif""")
'

# --- the sweeper: what it would remove, and what it says about why ----------------------------------------
# BOTH LAYERS AT ONCE. `roster_state_for_id` guards the VERDICT and the reason chain guards the WORDS, and
# each alone is enough to stop the removal — so killing either one changes no output and a single-layer mutant
# reports "not caught" for a guard that is working. That is a property of a redundant pair, and the honest
# test of a redundant pair is to remove all of it: with both gone the fork fixture becomes `WOULD REMOVE`.
mutant sweep-both-safety-layers claude/bin/sweep-jobs.sh '
rep("""  [ "${roster_entry_unreadable:-0}" = 0 ] || return 0\n""", "")
rep("""  [ "${roster_entry_ambiguous:-0}" = 0 ] || return 0\n""", "")
cut("""      elif [ "${roster_entry_ambiguous:-0}" != 0 ]; then""",
    """      elif [ -n "$(roster_duplicate_key_in "$roster_entry")" ]; then""")
cut("""      elif [ "${roster_entry_unreadable:-0}" != 0 ]; then""",
    """      elif [ -z "$roster_pick_state" ]; then""")
'
mutant sweep-listing-any-array claude/bin/sweep-jobs.sh '
rep("""type == "array" and all(type == "object")""", """type == "array\"""")
'
mutant sweep-first-pid-only claude/bin/sweep-jobs.sh '
rep("""    if kill -0 "$sia_pid" 2>/dev/null; then sia_found=0; break; fi""",
              """    if kill -0 "$sia_pid" 2>/dev/null; then sia_found=0; fi; break""")
'
mutant sweep-one-reason claude/bin/sweep-jobs.sh '
rep("""reason="${roster_order_reason:-the entries for that id cannot be ordered}, so nothing was read\"""",
              """reason="two or more entries state that id, so nothing was read\"""")
'
mutant sweep-duplicate-as-missing claude/bin/sweep-jobs.sh '
cut("""      elif [ -n "$(roster_duplicate_key_in "$roster_entry")" ]; then""",
    """      elif [ "${roster_entry_unreadable:-0}" != 0 ]; then""")
'
mutant sweep-newest-label claude/bin/sweep-jobs.sh '
rep("""        evidence="$evidence entries-mentioning-id=${roster_entry_count:-0} first=${roster_entry:-none}\"""",
              """        evidence="$evidence entries-mentioning-id=${roster_entry_count:-0} newest=${roster_entry:-none}\"""")
'
# TWO MUTANTS, NOT ONE. The combined version deleted the `no-rows` line as well as changing the jq, and the
# single check it tripped was the no-rows one — so it was reported as caught while the @json expression it
# named was pinned by nothing at all. Reverting only the jq left the whole suite green. A mutant that edits two
# things can be caught by one of them and vouch for the other, which is the same "green for the wrong reason"
# defect this runner exists to find, wearing the runner own clothes.
mutant sweep-listing-status-jq claude/bin/sweep-jobs.sh '
rep("""if has("status") then (.status | @json) else "absent" end] | join(" | ")""",
              """.status // "none"] | join(",")""")
'
mutant sweep-listing-status-norows claude/bin/sweep-jobs.sh '
rep("""    [ "$ev_rows" != 0 ] || ev_stat="no-rows"\n""", "")
'

printf '\n%s mutant(s): %s caught, %s NOT caught\n' "$ran" "$pass" "$fail"
[ "$fail" = 0 ] || exit 1
