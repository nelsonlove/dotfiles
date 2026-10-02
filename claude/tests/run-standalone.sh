#!/usr/bin/env bash
# Run every claude/tests suite that needs no live session, no vault, no machine state and no wall-clock timing: the set CI runs on every pull request (.github/workflows/claude-tests.yml). The captain said yes to this job on 2026-09-29, after the review of #76 noted that nothing ran these suites unless someone started them by hand.
#
# EVERY file under claude/tests that git tracks or would track (not ignored: no .DS_Store, no caches), except the Markdown ones, is accounted for: a RUN command names it, a KNOWN_FAILING command names it, or SKIP gives its reason. The runner fails if a file is in none of them, or if a SKIP entry names a file that does not exist. The covered set is READ FROM the commands, not kept by hand, so removing a RUN row un-covers its file and the check fails.
#
# KNOWN_FAILING holds suites that fail on main today for a reason tracked in an issue. They run, and they must still FAIL: the day one passes, the runner fails and says to move it back to RUN.
#
# Run: bash claude/tests/run-standalone.sh                    (exit 0 only if all is well)
#      bash claude/tests/run-standalone.sh --accounting-only  (only the check that every file is accounted for)
set -u
only_accounting=0
case "${1:-}" in
  "") ;;
  --accounting-only) only_accounting=1 ;;
  *) echo "usage: run-standalone.sh [--accounting-only]" >&2; exit 2 ;;
esac
ROOT=$(cd "$(dirname "$0")/../.." && pwd -P)
cd "$ROOT" || exit 2
G=claude/hooks/accept-verb-guard.sh
AVG=claude/tests/accept-verb-guard

# The accept-verb-guard battery writes and reads the fixed directory /tmp/v3/cases (make-battery.py and run-battery.py). Two runs at once would corrupt each other, so the pair runs under a lock (an empty directory). A trap removes it on any exit, Ctrl-C included, so an interrupted run does not block the next one.
LOCK=/tmp/v3.run-standalone.lock
BATTERY='t=0; until mkdir "$LOCK" 2>/dev/null; do t=$((t + 1)); [ "$t" -lt 300 ] || { echo "run-standalone: $LOCK held for over 5 minutes" >&2; exit 1; }; sleep 1; done; trap "rmdir \"\$LOCK\" 2>/dev/null" EXIT; trap "exit 130" INT TERM; python3 claude/tests/accept-verb-guard/make-battery.py && python3 claude/tests/accept-verb-guard/run-battery.py "$G"'
export G LOCK

# name | command. Each runs in its own shell; its exit status is its verdict.
RUN=(
  "fleet-ranks/table-agrees|bash claude/tests/fleet-ranks/table-agrees.sh"
  "fleet-ranks/admirals-and-dv|bash claude/tests/fleet-ranks/admirals-and-dv.sh"
  "fleet-ranks/pause-flag-both-roads|bash claude/tests/fleet-ranks/pause-flag-both-roads.sh"
  "dv-tripwire|bash claude/tests/dv-tripwire/tripwire.sh"
  "cross-session-inject|bash claude/tests/cross-session-inject/disposition-text.sh"
  "accept-verb-guard battery|$BATTERY"
  "accept-verb-guard navigate|python3 $AVG/navigate-cases.py $G"
  "accept-verb-guard cli-tool|python3 $AVG/cli-tool-cases.py $G"
  "accept-verb-guard dispatcher|python3 $AVG/dispatcher-cases.py $G"
  "accept-verb-guard ob|python3 $AVG/ob-cases.py $G"
)
# name | command | issue | the text its failure must print. Each must FAIL WITH THAT TEXT: a pass means it is fixed and belongs in RUN again, and a failure with other text (a wrong argument, a missing tool) is a new failure, not the tracked one.
KNOWN_FAILING=(
  "accept-verb-guard verb-list-drift|bash $AVG/verb-list-drift.sh $G|#82|no verb list found"
)
# file | why it is not run here
SKIP=(
  "fleet-ranks/wake-and-promote.sh|needs a throwaway session id you dispatch yourself"
  "fleet-ranks/wake-two-roots.sh|needs a throwaway session id you dispatch yourself"
  "notify-session/notifier.sh|its matching-session cases need a throwaway session id"
  "fleet-ranks/status-dual-read.sh|its first section reads the live agent notebook, and must not pass without it"
  "xlog-follow/follow.sh|depends on poll timing between writes, like the timing suites; run it by hand"
  "accept-verb-guard/timing.py|fails on wall time; a shared CI runner's timing is not this machine's"
  "accept-verb-guard/property-timing.py|fails on growth measured in wall time; same reason"
  "accept-verb-guard/timing-floor.sh|fails on wall time against the hook's 10 s budget; same reason"
  "accept-verb-guard/prove-shared-lib-path.sh|reads ~/.claude/hooks and the tickle config on this machine"
)

printf 'bash for the suites: %s (%s)\n' "$(command -v bash)" "$(bash -c 'echo $BASH_VERSION')"

fails=0; ran=0
if [ "$only_accounting" = 0 ]; then
  for row in "${RUN[@]}"; do
    name=${row%%|*}; cmd=${row#*|}
    printf '\n##### %s\n' "$name"
    ran=$((ran + 1))
    if bash -c "$cmd"; then printf '===== PASS  %s\n' "$name"
    else fails=$((fails + 1)); printf '===== FAIL  %s\n' "$name"; fi
  done
  for row in "${KNOWN_FAILING[@]}"; do
    IFS='|' read -r name cmd issue want <<< "$row"
    printf '\n##### %s (known failing, %s)\n' "$name" "$issue"
    ran=$((ran + 1))
    if out=$(bash -c "$cmd" 2>&1); then fails=$((fails + 1)); printf '%s\n===== FAIL  %s now PASSES: %s looks fixed, so move it back to RUN\n' "$out" "$name" "$issue"
    else
      printf '%s\n' "$out"
      case "$out" in
        *"$want"*) printf '===== PASS  %s still fails as tracked in %s ("%s")\n' "$name" "$issue" "$want" ;;
        *) fails=$((fails + 1)); printf '===== FAIL  %s failed, but not with "%s": a new failure, not the one tracked in %s\n' "$name" "$want" "$issue" ;;
      esac
    fi
  done
fi

printf '\n##### accounting: every file is run, known failing, or skipped with a reason\n'
unaccounted=0
commands=""
for row in "${RUN[@]}"; do commands="$commands ${row#*|} "; done
for row in "${KNOWN_FAILING[@]}"; do IFS='|' read -r _ cmd _ _ <<< "$row"; commands="$commands $cmd "; done
while IFS= read -r f; do
  rel=${f#claude/tests/}
  hit=0
  case "$commands" in *"$f "*|*"$f\""*|*"$f;"*) hit=1 ;; esac
  for s in "${SKIP[@]}"; do [ "${s%%|*}" = "$rel" ] && hit=1; done
  if [ "$hit" = 0 ]; then unaccounted=$((unaccounted + 1)); printf 'FAIL  %s is not run, not known failing, and not skipped with a reason\n' "$rel"; fi
done < <(git ls-files --cached --others --exclude-standard -- claude/tests | grep -v -e '\.md$' -e '/run-standalone\.sh$' | sort -u)
for s in "${SKIP[@]}"; do
  [ -f "claude/tests/${s%%|*}" ] || { unaccounted=$((unaccounted + 1)); printf 'FAIL  %s is skipped but does not exist\n' "${s%%|*}"; }
  printf 'SKIP  %s — %s\n' "${s%%|*}" "${s#*|}"
done

printf '\n%s suites run, %s failed; %s files skipped on purpose; %s files unaccounted for\n' "$ran" "$fails" "${#SKIP[@]}" "$unaccounted"
[ "$fails" = 0 ] && [ "$unaccounted" = 0 ]
