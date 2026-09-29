#!/usr/bin/env bash
# Run every claude/tests suite that needs no live session, no vault and no machine state: the set CI runs on
# every pull request (.github/workflows/claude-tests.yml). The captain said yes to this job on 2026-09-29, after
# the review of #76 noted that nothing ran these suites unless someone started them by hand.
#
# EVERY test file under claude/tests is named below, either in RUN or in SKIP with its reason, and the runner
# fails if a file is in neither. So a new suite cannot be forgotten: it must be run here or excluded on purpose.
#
# Run: bash claude/tests/run-standalone.sh    (exit 0 only if every suite passed and every file is accounted for)
#      bash claude/tests/run-standalone.sh --accounting-only    (only the check that every file is listed)
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd -P)
cd "$ROOT" || exit 2
G=claude/hooks/accept-verb-guard.sh
AVG=claude/tests/accept-verb-guard

# name | command. Each suite runs in its own shell; its exit status is its verdict.
RUN=(
  "fleet-ranks/table-agrees|bash claude/tests/fleet-ranks/table-agrees.sh"
  "fleet-ranks/admirals-and-dv|bash claude/tests/fleet-ranks/admirals-and-dv.sh"
  "fleet-ranks/pause-flag-both-roads|bash claude/tests/fleet-ranks/pause-flag-both-roads.sh"
  "dv-tripwire|bash claude/tests/dv-tripwire/tripwire.sh"
  "cross-session-inject|bash claude/tests/cross-session-inject/disposition-text.sh"
  "xlog-follow|bash claude/tests/xlog-follow/follow.sh"
  "accept-verb-guard battery|python3 $AVG/make-battery.py && python3 $AVG/run-battery.py $G"
  "accept-verb-guard navigate|python3 $AVG/navigate-cases.py $G"
  "accept-verb-guard cli-tool|python3 $AVG/cli-tool-cases.py $G"
  "accept-verb-guard dispatcher|python3 $AVG/dispatcher-cases.py $G"
  "accept-verb-guard ob|python3 $AVG/ob-cases.py $G"
)
# The files each RUN entry covers, for the accounting below.
COVERED=(
  fleet-ranks/table-agrees.sh fleet-ranks/admirals-and-dv.sh fleet-ranks/pause-flag-both-roads.sh
  dv-tripwire/tripwire.sh cross-session-inject/disposition-text.sh xlog-follow/follow.sh
  accept-verb-guard/make-battery.py accept-verb-guard/run-battery.py accept-verb-guard/navigate-cases.py
  accept-verb-guard/cli-tool-cases.py accept-verb-guard/dispatcher-cases.py accept-verb-guard/ob-cases.py
)
# file | why it is not run here
SKIP=(
  "fleet-ranks/wake-and-promote.sh|needs a throwaway session id you dispatch yourself"
  "fleet-ranks/wake-two-roots.sh|needs a throwaway session id you dispatch yourself"
  "notify-session/notifier.sh|its matching-session cases need a throwaway session id"
  "fleet-ranks/status-dual-read.sh|its first section reads the live agent notebook, and must not pass without it"
  "accept-verb-guard/timing.py|fails on wall time; a shared CI runner's timing is not this machine's"
  "accept-verb-guard/property-timing.py|fails on growth measured in wall time; same reason"
  "accept-verb-guard/timing-floor.sh|fails on wall time against the hook's 10 s budget; same reason"
  "accept-verb-guard/prove-shared-lib-path.sh|reads ~/.claude/hooks and the tickle config on this machine"
  "accept-verb-guard/verb-list-drift.sh|STALE, fails on main: it reads qw(...) verb lists that the guard lost in 51b7bf0; reported to the guard's owner"
)

only_accounting=0; [ "${1:-}" = "--accounting-only" ] && only_accounting=1
fails=0; ran=0
for row in "${RUN[@]}"; do
  [ "$only_accounting" = 1 ] && break
  name=${row%%|*}; cmd=${row#*|}
  printf '\n##### %s\n' "$name"
  ran=$((ran + 1))
  if bash -c "$cmd"; then printf '===== PASS  %s\n' "$name"
  else fails=$((fails + 1)); printf '===== FAIL  %s\n' "$name"; fi
done

printf '\n##### accounting: every test file is run or skipped on purpose\n'
unaccounted=0
while IFS= read -r f; do
  rel=${f#claude/tests/}
  hit=0
  for c in "${COVERED[@]}"; do [ "$c" = "$rel" ] && hit=1; done
  for s in "${SKIP[@]}"; do [ "${s%%|*}" = "$rel" ] && hit=1; done
  if [ "$hit" = 0 ]; then unaccounted=$((unaccounted + 1)); printf 'FAIL  %s is neither run nor skipped with a reason\n' "$rel"; fi
done < <(find claude/tests -type f \( -name '*.sh' -o -name '*.py' \) ! -name run-standalone.sh | sort)
# And the other way: a name here that no longer exists is a stale list, not a pass.
for c in "${COVERED[@]}"; do [ -f "claude/tests/$c" ] || { unaccounted=$((unaccounted + 1)); printf 'FAIL  %s is listed but does not exist\n' "$c"; }; done
for s in "${SKIP[@]}"; do [ -f "claude/tests/${s%%|*}" ] || { unaccounted=$((unaccounted + 1)); printf 'FAIL  %s is listed but does not exist\n' "${s%%|*}"; }; done
for s in "${SKIP[@]}"; do printf 'SKIP  %s — %s\n' "${s%%|*}" "${s#*|}"; done
[ "$unaccounted" = 0 ] || fails=$((fails + 1))

printf '\n%s suites run, %s skipped on purpose, %s failed\n' "$ran" "${#SKIP[@]}" "$fails"
[ "$fails" = 0 ]
