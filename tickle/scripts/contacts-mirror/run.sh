#!/bin/bash
# contacts-mirror — the tickle wrapper: the gates, then mirror.py. Ruled by Nelson 2026-09-30 ("a plus job", cross-session log 05:50). Ships disabled.
#
# Gates, in order, each recorded on stdout: the fleet pause (`_lib/pause-gate.sh contacts-mirror`: 1 = paused, skip; anything else non-zero = failed); the fleet load gate (the 5-minute load under 8 AND fewer than 20 live sessions, Nelson's "a", log 2026-09-30T05:32; this local copy is replaced by `claude/bin/fleet-gate` when that lands, per dotfiles issue #103); a fresh vault backup (the obsidian ship's condition: the obsidian-backup job ran successfully in the last 30 minutes). The tickle trigger also runs `_lib/gated.sh <host> contacts-mirror`, so a paused fleet is recorded by tickle as a skipped check; the pause check here covers a run by hand. Then `mirror.py` with the arguments given to this script.
#
# Exit codes: 0 done or skipped with a reason; 2 a check failed; 3 the reader failed. Every unexpected exit becomes 2, as in pause-gate.sh.
set -u
cm_ok=0
on_exit() { rc=$?; [ "$cm_ok" = 1 ] && exit "$rc"; [ "$rc" -eq 0 ] && exit 0; echo "contacts-mirror: FAILED — unexpected exit $rc (rewritten to 2)" >&2; exit 2; }
trap on_exit EXIT
finish() { cm_ok=1; if [ "$1" -eq 0 ]; then echo "contacts-mirror: $2"; else echo "contacts-mirror: FAILED — $2" >&2; fi; exit "$1"; }

if [ -z "${HOME:-}" ]; then HOME=$(cd ~ 2>/dev/null && pwd) || HOME=/Users/nelson; export HOME; fi
export PATH="/opt/homebrew/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
here=$(cd "$(dirname "$0")" && pwd -P) || finish 2 "cannot resolve the script directory"

# ---- the fleet pause
"$here/../_lib/pause-gate.sh" contacts-mirror
prc=$?
case "$prc" in
  0) ;;
  1) finish 0 "SKIPPED — the fleet is paused" ;;
  *) finish 2 "the pause gate could not check the flag (exit $prc)" ;;
esac

# ---- the fleet load gate
load5="${CM_LOAD5:-$(sysctl -n vm.loadavg | awk '{print $3}')}"
printf '%s' "$load5" | grep -Eq '^[0-9]+(\.[0-9]+)?$' || finish 2 "cannot read the 5-minute load ('$load5')"
if [ -n "${CM_SESSIONS:-}" ]; then sessions="$CM_SESSIONS"; else
  sessions=$(env -u ANTHROPIC_API_KEY /usr/bin/perl -e 'alarm shift; exec @ARGV or exit 127' 60 claude agents --json 2>/dev/null | /usr/bin/jq length 2>/dev/null) || sessions=""
fi
printf '%s' "$sessions" | grep -Eq '^[0-9]+$' || finish 2 "cannot count the live sessions"
awk -v l="$load5" 'BEGIN{exit !(l >= 8)}' && finish 0 "SKIPPED — the 5-minute load $load5 is 8 or more"
[ "$sessions" -lt 20 ] || finish 0 "SKIPPED — $sessions live sessions (20 or more)"
echo "contacts-mirror: gates: pause clear, load5 $load5, $sessions sessions"

# ---- a fresh backup (skipped for a --target-dir run, which never touches the vault). The backup job commits only when
# the vault changed, so a quiet vault has old commits: the check is the backup JOB's last successful run, from tickle's
# own history, within 30 minutes.
case " $* " in *" --target-dir "*) ;; *)
  hist="${CM_BACKUP_HISTORY:-$HOME/Library/Application Support/tickle/runs/obsidian-backup/history.jsonl}"
  last=$(grep '"type":"run"' "$hist" 2>/dev/null | grep '"status":"success"' | tail -1 | /usr/bin/jq -r .ts 2>/dev/null) || last=""
  [ -n "$last" ] || finish 2 "cannot find a successful obsidian-backup run in $hist"
  when=$(date -j -f %Y-%m-%dT%H:%M:%S "${last%??????}" +%s 2>/dev/null) || finish 2 "cannot read the backup run time '$last'"
  age=$(( $(date +%s) - when ))
  [ "$age" -lt 1800 ] || finish 0 "SKIPPED — the last successful vault backup ran $((age / 60)) minutes ago (the obsidian ship asks for a fresh one)"
esac

cm_ok=1
/usr/bin/python3 "$here/mirror.py" "$@"
exit $?
