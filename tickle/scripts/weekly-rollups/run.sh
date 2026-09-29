#!/bin/bash
# weekly-rollups — each Monday, start ONE `[L0-OB] weekly rollups` lieutenant for the ISO week just ended.
#
# Ruled by Nelson on 2026-09-29 ("how will we know if the tickle job works?", then "alright go for it"; cross-session log
# 2026-09-29T02:56), given to the tickle lieutenant at 03:21. Until Nelson says credits are back, the job ships with
# `status: disabled` and the obsidian captain dispatches the lieutenant by hand ("we'll have to have agents handle those
# jobs until i can add credits"). This script is the whole job; the tickle trigger only picks the host and the time.
#
# The guards, in order. Each one records its reason on stdout (tickle keeps stdout per run):
#   1. Fleet pause: `_lib/pause-gate.sh weekly-rollups`. 1 = paused, skip (exit 0). Anything else non-zero = failed (exit 2).
#   2. Load: the 1-minute load average 10 or more = skip (exit 0).
#   3. No overwrite: if either rollup for the target week already exists, dispatch nothing (exit 0). This runs first
#      of the vault checks, so a rerun after a good week is always a quiet skip.
#   4. Live lieutenant: `claude agents --json` lists running sessions. A session whose name starts with
#      `[L0-OB] weekly rollups` (so a /rename that adds to the name still counts) that is busy, or idle but not
#      `state: done`, and started less than 24 hours ago, is at work: dispatch nothing (exit 0). One that is idle and
#      `done` is a finished lieutenant nobody stopped, and one at work for 24 hours or more is stuck; either still blocks
#      a second one, but loudly: queue item "Weekly rollup not started <week>" and exit 5. A listing that fails or
#      cannot be read is exit 2: a check we cannot make is never a pass. This runs before guard 5, so a lieutenant
#      still writing last week's files never causes a false "missed" item. A hand dispatch by the obsidian captain is
#      caught here too, because its lieutenant carries the same name.
#   5. Previous week: both rollups for the week before the target must exist. If either is missing, ONE queue item
#      "Weekly rollup missed <that week>" is filed for Nelson (never twice), and the run goes on.
#   6. Brief markers: the brief is the text between the two marker lines of the standing brief note. Each marker must
#      appear exactly once, on its own line, start before end, with non-blank text between. If not: dispatch nothing,
#      file "Weekly rollup not started <week>", exit 3 (a FAILED run, loud).
#   7. Substitution: the ONLY substitution is the literal `YYYY-Www`. `<date>`, `<n>`, `<reason>` pass through.
#   8. Dispatch: refused (queue item, exit 6) if a running Claude daemon holds ANTHROPIC_API_KEY, since a --bg session
#      takes the daemon's environment and would bill the key. Otherwise
#      `env -u ANTHROPIC_API_KEY claude --bg --agent lieutenant --name "[L0-OB] weekly rollups" -- <brief>`, from the
#      vault (a trusted workspace with no project config; /tmp and $HOME are not trusted). Then the dispatch is
#      CONFIRMED by listing agents again. A failed or unconfirmed dispatch files "Weekly rollup not started <week>" and
#      exits 4, never a quiet success. On success, a "not started" item for the week (from an earlier failed run) gets
#      a line under `## Response` and `needs: nothing`, and one "claim and release in one entry" line naming the
#      ruling is appended to the cross-session log (the job holds nothing once it exits; the lieutenant posts its own
#      claim and release for the files).
#
# Every `claude` call the job makes (the listing too) runs with ANTHROPIC_API_KEY unset: `claude agents` starts a
# Claude daemon when none is running, and that daemon would inherit the key.
#
# A real run holds a kernel lock (`/usr/bin/lockf` on ~/.local/state/weekly-rollups/run.lock) from start to end, so two
# overlapping runs can never both pass the live check. The lock dies with the process; a second run skips (exit 0).
# --dry-run takes no lock.
#
# Queue items the job files carry `session: "tickle weekly-rollups"`, the job's own identity. Every later failure for a
# week with a "not started" item adds a Response line with the new cause; a settled one is reopened (`needs: ruling`).
#
# THE API KEY. `env -u ANTHROPIC_API_KEY` keeps the key out of the CLI call, as the obsidian captain asked. It does NOT
# reach the lieutenant: a `claude --bg` session takes its environment from the Claude daemon, not from this shell
# (CLAUDE.md, measured 2026-09-29). So guard 8 refuses to dispatch while a running Claude daemon holds the key, and
# --dry-run reports it.
#
# --dry-run goes through every guard, prints what it would write and the exact dispatch command, and writes and
# dispatches NOTHING. It also reports what the dispatch depends on in THIS environment (which `claude`, its auth
# method, whether the dispatch directory is trusted, whether the Claude daemon holds the API key), so running it under
# launchd's environment proves that a scheduled run would find everything it needs.
#
# Exit codes: 0 = done or deliberately skipped (reason on stdout); 2 = a check failed or bad usage; 3 = the brief is
# broken; 4 = the dispatch failed; 5 = a finished or stuck lieutenant of the same name blocks the dispatch; 6 = the
# Claude daemon holds the API key. Every unexpected exit becomes 2 through the EXIT trap, as in pause-gate.sh.
#
# The queue item road: written straight to disk, created with noclobber so a second run never overwrites or duplicates
# it. Not through vault-mcp: a scheduled shell job has no MCP client, and a create-only write needs no `if_rev`.
#
# Test seams (environment): WR_VAULT (vault root), WR_LOADAVG (a fake 1-minute load), WR_CLAUDE (the claude binary),
# WR_DISPATCH_CWD (the dispatch directory), WR_CLAUDE_JSON (the file holding workspace trust), WR_CONFIRM_TRIES and
# WR_CONFIRM_SLEEP (how long to wait for the dispatched session to appear), WR_LOCK (the lock file), PAUSE_NOTE (passed
# to pause-gate.sh), and WR_TEST_DAEMON_KEY_PIDS (the pids guard 8 reports as holding the key, in place of the real
# scan; set, even empty, it REPLACES the scan, so it is for the tests only).
#
# Written for /bin/bash 3.2 (macOS): no associative arrays, no mapfile, no ${var,,}.

set -u
set -o pipefail

wr_ok=0
on_exit() {
  rc=$?
  [ "$wr_ok" = "1" ] && exit "$rc"
  [ "$rc" -eq 0 ] && exit 0
  echo "weekly-rollups: FAILED — unexpected exit $rc (rewritten to 2 so tickle records a failed run)" >&2
  exit 2
}
trap on_exit EXIT

# finish <code> <message>: the only way out. A deliberate exit keeps its code; stdout says why.
finish() {
  wr_ok=1
  if [ "$1" -eq 0 ]; then echo "weekly-rollups: $2"; else echo "weekly-rollups: FAILED — $2" >&2; fi
  exit "$1"
}

# HOME can be absent from a daemon environment; resolve it as pause-gate.sh does rather than trip `set -u`.
if [ -z "${HOME:-}" ]; then
  HOME=$(cd ~ 2>/dev/null && pwd) || HOME=""
  [ -n "$HOME" ] || HOME="/Users/nelson"
  export HOME
fi

# launchd hands jobs PATH=/usr/bin:/bin:/usr/sbin:/sbin; `claude` lives in Homebrew.
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"

JOB_ID="weekly-rollups"
LT_NAME="[L0-OB] weekly rollups"
RULING="Nelson's \"alright go for it\" (cross-session log 2026-09-29T02:56)"

orig_args=("$@")
dry=0
week=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    --week) shift; [ -n "${1:-}" ] || finish 2 "--week needs a value (YYYY-Www)"; week="$1" ;;
    --week=*) week="${1#--week=}"; [ -n "$week" ] || finish 2 "--week= needs a value (YYYY-Www)" ;;
    *) finish 2 "usage: run.sh [--dry-run] [--week YYYY-Www] (unknown argument: $1)" ;;
  esac
  shift
done

here=$(cd "$(dirname "$0")" && pwd -P) || finish 2 "cannot resolve the script directory"
PAUSE_GATE="$here/../_lib/pause-gate.sh"
VAULT="${WR_VAULT:-$HOME/obsidian}"
CLAUDE="${WR_CLAUDE:-claude}"
DISPATCH_CWD="${WR_DISPATCH_CWD:-$VAULT}"
CLAUDE_JSON="${WR_CLAUDE_JSON:-$HOME/.claude.json}"
LOCK_FILE="${WR_LOCK:-$HOME/.local/state/weekly-rollups/run.lock}"

SYS="$VAULT/00-09 System"
NB_DIR="$SYS/03 Agents/03.04 Records/Agent notebook/rollups"
XS_DIR="$SYS/03 Agents/03.16 Cross-session log/rollups"
XLOG="$SYS/03 Agents/03.16 Cross-session log/CROSS-SESSION.md"
BRIEF_NOTE="$SYS/03 Agents/03.05 Agents & skills/Weekly rollups — standing brief.md"
QUEUE_DIR="$SYS/00 System management/00.08 Operator's console/Open items"
MARK_START="<!-- weekly-rollups brief: start -->"
MARK_END="<!-- weekly-rollups brief: end -->"

say() { echo "weekly-rollups: $*"; }
iso_now() { date +%Y-%m-%dT%H:%M:%S%z | sed 's/\(..\)$/:\1/'; }
# cl: every claude call, with the API key unset (see the header).
cl() { env -u ANTHROPIC_API_KEY "$CLAUDE" "$@"; }

# A real run re-runs itself under a kernel lock. lockf exits 75 (EX_TEMPFAIL) only when the lock is held; this script
# never exits 75 itself.
if [ "$dry" != "1" ] && [ -z "${WR_LOCKED:-}" ]; then
  mkdir -p "$(dirname "$LOCK_FILE")" || finish 2 "cannot create the lock's folder for $LOCK_FILE"
  WR_LOCKED=1 /usr/bin/lockf -s -t 0 "$LOCK_FILE" /bin/bash "$0" ${orig_args[@]+"${orig_args[@]}"}
  lrc=$?
  case "$lrc" in
    0|2|3|4|5|6) wr_ok=1; exit "$lrc" ;;
    75) finish 0 "SKIPPED — another weekly-rollups run holds $LOCK_FILE" ;;
    *) finish 2 "lockf could not take the lock $LOCK_FILE (exit $lrc)" ;;
  esac
fi
[ "$dry" = "1" ] && say "DRY RUN — nothing is written and nothing is dispatched"

# ---- ISO week arithmetic (BSD date) ----
# monday_of YYYY-Www -> YYYY-MM-DD. Week 1 is the week holding 4 January.
monday_of() {
  g=${1%%-W*}; w=${1##*-W}; w=$((10#$w))
  j4dow=$(date -j -f %Y-%m-%d "$g-01-04" +%u) || return 1
  date -j -v-"$((j4dow - 1))"d -v+"$(((w - 1) * 7))"d -f %Y-%m-%d "$g-01-04" +%Y-%m-%d
}
week_of() { date -j -f %Y-%m-%d "$1" +%G-W%V; }

if [ -z "$week" ]; then
  week=$(date -v-7d +%G-W%V) || finish 2 "cannot compute last week's ISO week"
fi
printf '%s' "$week" | grep -Eq '^[0-9]{4}-W(0[1-9]|[1-4][0-9]|5[0-3])$' || finish 2 "bad week '$week' (want YYYY-Www)"
mon=$(monday_of "$week") || finish 2 "cannot find the Monday of $week"
[ "$(week_of "$mon")" = "$week" ] || finish 2 "week $week does not exist (its Monday $mon is in $(week_of "$mon"))"
prev=$(week_of "$(date -j -v-7d -f %Y-%m-%d "$mon" +%Y-%m-%d)") || finish 2 "cannot compute the week before $week"
say "target week $week (Monday $mon); previous week $prev"

nb_file() { echo "$NB_DIR/Agent rollup for $1.md"; }
xs_file() { echo "$XS_DIR/Cross-session rollup for $1.md"; }

is_ours() { grep -Eq '^[[:space:]]+by:[[:space:]]*"?tickle weekly-rollups"?[[:space:]]*$' "$1"; }
uuid7() { /usr/bin/perl -MTime::HiRes=time -e 'my $ms=int(time*1000); my @r=map{int rand 256}1..10; printf "%08x-%04x-7%03x-%04x-%04x%08x\n", $ms>>16, $ms&0xffff, ($r[0]<<4|$r[1]>>4)&0xfff, 0x8000|(($r[2]<<8|$r[3])&0x3fff), $r[4]<<8|$r[5], ($r[6]<<24|$r[7]<<16|$r[8]<<8|$r[9])'; }

is_closed() { grep -Eq '^status:[[:space:]]*"?archived/' "$1"; }

# respond <file> <needs> <line> — set `needs` and `modified` in the frontmatter, and put <line> at the end of the
# `## Response` section (before the next `## ` heading, or at the end of the file). Only on this job's own open items:
# returns 1, changing nothing, if the item is closed (`status: archived/…`; closing is Nelson's click). The new text is
# written to a hidden temp file in the same folder and moved over the note, so the swap is atomic; if the note changed
# while it was being rewritten (someone typing in it), the rewrite is dropped rather than written over their edit.
respond() {
  rf="$1"; rn="$2"; rl="$3"
  is_ours "$rf" || { say "WARNING: not touching $rf: it does not carry generated.by tickle weekly-rollups"; return 0; }
  is_closed "$rf" && return 1
  st=$(iso_now)
  m0=$(stat -f %m "$rf") || { say "WARNING: could not update $rf (cannot stat it)"; return 0; }
  tmpf=$(mktemp "$(dirname "$rf")/.weekly-rollups-respond.XXXXXX") || { say "WARNING: could not update $rf (no temp file)"; return 0; }
  if awk -v st="$st" -v nd="$rn" -v ln="- $st — $rl" '
      BEGIN { fm = 0; inr = 0; done = 0 }
      fm < 2 && /^---$/ { fm++; print; next }
      fm == 1 && /^needs:/ { print "needs: " nd; next }
      fm == 1 && /^modified:/ { print "modified: " st; next }
      fm >= 2 && /^## / { if (inr && !done) { print ln; print ""; done = 1 }; inr = ($0 == "## Response") }
      { print }
      END { if (!done) print ln }' "$rf" > "$tmpf" \
     && [ "$(stat -f %m "$rf")" = "$m0" ] && mv "$tmpf" "$rf"; then
    say "queue item updated (needs: $rn): $rf"
  else
    say "WARNING: could not update $rf (it changed while being rewritten, or the write failed); left as it was"
    /usr/bin/trash "$tmpf" 2>/dev/null || true
  fi
  return 0
}

# file_queue_item <missed|not started> <week> <why> [<title suffix>] — ONE item per kind and week, created, never
# overwritten. A repeat failure adds its cause to an open "not started" item; if that item is closed, a new one is filed
# with the date in its title. "missed" is not filed while an open "not started" item for that week already asks.
file_queue_item() {
  kind="$1"; qw="$2"; why="$3"; suffix="${4:-}"
  title="Weekly rollup $kind $qw$suffix"
  qf="$QUEUE_DIR/$title.md"
  ns_item="$QUEUE_DIR/Weekly rollup not started $qw.md"
  if [ "$kind" = missed ] && [ -e "$ns_item" ] && ! is_closed "$ns_item"; then
    say "not filing \"missed $qw\": the open item $ns_item already asks about that week"
    return 0
  fi
  if [ -e "$qf" ]; then
    if [ "$kind" = "not started" ]; then
      if is_closed "$qf"; then
        if [ -n "$suffix" ]; then say "queue item $qf is closed too; not filed again today"; return 0; fi
        file_queue_item "$kind" "$qw" "$why" " (again $(date +%Y-%m-%d))"
        return 0
      fi
      if [ "$dry" = "1" ]; then say "would add the new cause to queue item: $qf"; else respond "$qf" ruling "Failed again: $why"; fi
    else
      say "queue item already exists, not filed again: $qf"
    fi
    return 0
  fi
  stamp=$(iso_now)
  uid=$(uuid7) || finish 2 "cannot make a uid"
  body="---
type: Task/AgentTask
title: $title
description: \"The weekly rollups for $qw: $kind. The weekly-rollups tickle job found it; Nelson decides whether a lieutenant writes them now.\"
status: draft/proposed
needs: ruling
session: \"tickle weekly-rollups\"
generated:
  by: \"tickle weekly-rollups\"
  at: \"$stamp\"
created: $stamp
modified: $stamp
uid: $uid
tags: []
---

# $title

## Ask

The weekly-rollups tickle job, ruled by Nelson (\"alright go for it\", cross-session log 2026-09-29T02:56), reports: rollups for $qw $kind. $why

Expected:

- \`03 Agents/03.04 Records/Agent notebook/rollups/Agent rollup for $qw.md\`
- \`03 Agents/03.16 Cross-session log/rollups/Cross-session rollup for $qw.md\`

## Response
"
  if [ "$dry" = "1" ]; then
    say "would file queue item: $qf"
    return 0
  fi
  [ -d "$QUEUE_DIR" ] || finish 2 "queue folder missing: $QUEUE_DIR"
  if ! ( set -C; printf '%s' "$body" > "$qf" ) 2>/dev/null; then
    [ -e "$qf" ] && { say "queue item appeared meanwhile, not overwritten: $qf"; return 0; }
    finish 2 "could not write queue item $qf"
  fi
  say "filed queue item ($(wc -c < "$qf" | tr -d ' ') bytes): $qf"
}

# settle_not_started <week> — after a confirmed dispatch, close out this job's own "not started" item for the week.
settle_not_started() {
  nf="$QUEUE_DIR/Weekly rollup not started $1.md"
  [ -f "$nf" ] || return 0
  respond "$nf" nothing "${2:-The weekly-rollups job started the lieutenant for $1 after all.}" || true
}

# ---- 1. fleet pause ----
[ -x "$PAUSE_GATE" ] || finish 2 "pause gate missing or not executable: $PAUSE_GATE"
"$PAUSE_GATE" "$JOB_ID"
prc=$?
case "$prc" in
  0) say "pause: clear" ;;
  1) finish 0 "SKIPPED — the fleet is paused (pause-gate.sh exit 1)" ;;
  *) finish 2 "pause gate could not check the flag (exit $prc)" ;;
esac

# ---- 2. load ----
if [ -n "${WR_LOADAVG:-}" ]; then load="$WR_LOADAVG"; else
  load=$(sysctl -n vm.loadavg | awk '{print $2}') || finish 2 "cannot read the load average"
fi
printf '%s' "$load" | grep -Eq '^[0-9]+(\.[0-9]+)?$' || finish 2 "load average unreadable: '$load'"
if awk -v l="$load" 'BEGIN{exit !(l >= 10)}'; then
  finish 0 "SKIPPED — 1-minute load $load is 10 or more"
fi
say "load: $load"

# ---- 3. no overwrite ----
exists=""
[ -e "$(nb_file "$week")" ] && exists="$exists $(nb_file "$week")"
[ -e "$(xs_file "$week")" ] && exists="$exists $(xs_file "$week")"
if [ -n "$exists" ]; then
  [ "$dry" = "1" ] || settle_not_started "$week" "The rollups for $week now exist."
  finish 0 "SKIPPED — $week already has a rollup, nothing overwritten, nothing dispatched:$exists"
fi
say "target week $week: no rollup yet"

# ---- 4. live lieutenant ----
command -v "$CLAUDE" >/dev/null 2>&1 || finish 2 "claude not found on PATH ($PATH)"
agents=$(cl agents --json 2>/dev/null) || finish 2 "'claude agents --json' failed; cannot tell whether $LT_NAME is live"
now_ms=$(/usr/bin/perl -MTime::HiRes=time -e 'printf "%d", time*1000') || finish 2 "cannot read the clock"
counts=$(printf '%s' "$agents" | jq -r --arg n "$LT_NAME" --argjson now "$now_ms" '
  [.[] | select((.name // "") | startswith($n))] as $m
  | ($m | map(select(.status == "idle" and .state == "done"))) as $fin
  | ($m | map(select((.status == "idle" and .state == "done") | not) | select((.startedAt // $now) < ($now - 86400000)))) as $stuck
  | "\($m | length) \($fin | length) \($stuck | length)"') || finish 2 "cannot parse 'claude agents --json'"
printf '%s' "$counts" | grep -Eq '^[0-9]+ [0-9]+ [0-9]+$' || finish 2 "cannot read 'claude agents --json' (got '$counts')"
set -- $counts; live=$1; finished=$2; stuck=$3
if [ "$stuck" != "0" ]; then
  file_queue_item "not started" "$week" "A session named $LT_NAME has been at work for 24 hours or more ($stuck session(s)), perhaps waiting on a prompt nobody answers. The job never starts a second one of that name. Look at it with \`claude attach\`; stop it with \`claude stop\` if it is stuck, then run the job again."
  finish 5 "$LT_NAME has been at work for 24 hours or more ($stuck session(s)); look at it"
fi
if [ "$live" -gt "$finished" ]; then finish 0 "SKIPPED — $LT_NAME is live and at work (busy, or idle and not done); no second one started"; fi
if [ "$finished" != "0" ]; then
  file_queue_item "not started" "$week" "A session named $LT_NAME is still listed by \`claude agents\`, idle and done ($finished session(s)): a finished lieutenant nobody stopped. The job never starts a second one of that name. Stop it with \`claude stop\`, then run the job again."
  finish 5 "$LT_NAME is listed, idle and done ($finished session(s)); stop it, then rerun"
fi
say "live check: no $LT_NAME running"

# ---- 5. previous week's rollups ----
missing=""
[ -e "$(nb_file "$prev")" ] || missing="$missing notebook"
[ -e "$(xs_file "$prev")" ] || missing="$missing cross-session"
if [ -n "$missing" ]; then
  say "previous week $prev missing:$missing"
  file_queue_item missed "$prev" "Missing at the run for $week:$missing."
else
  say "previous week $prev: both rollups exist"
fi

# ---- 6. brief markers ----
[ -r "$BRIEF_NOTE" ] || { file_queue_item "not started" "$week" "The standing brief note could not be read, so no lieutenant was started."; finish 3 "standing brief unreadable: $BRIEF_NOTE"; }
note=$(cat "$BRIEF_NOTE") || finish 2 "cannot read the standing brief"
mk=$(printf '%s\n' "$note" | awk -v s="$MARK_START" -v e="$MARK_END" '
  $0 == s { ns++; if (!ls) ls = NR } $0 == e { ne++; if (!le) le = NR }
  END { print ns + 0, ne + 0, ls + 0, le + 0 }') || finish 2 "cannot scan the brief's markers"
# shellcheck disable=SC2086
set -- $mk; ns=$1; ne=$2; ls_=$3; le_=$4
if [ "$ns" != "1" ] || [ "$ne" != "1" ]; then
  file_queue_item "not started" "$week" "The standing brief's markers are broken (start line $ns times, end line $ne times; each must be once, on its own line), so no lieutenant was started."
  finish 3 "brief markers broken: start $ns, end $ne (each must appear exactly once on its own line)"
fi
if [ "$le_" -le "$((ls_ + 1))" ]; then
  file_queue_item "not started" "$week" "The standing brief's end marker is not after its start marker with text between, so no lieutenant was started."
  finish 3 "brief markers out of order or empty (start line $ls_, end line $le_)"
fi
raw=$(printf '%s\n' "$note" | sed -n "$((ls_ + 1)),$((le_ - 1))p") || finish 2 "cannot extract the brief"
if ! printf '%s' "$raw" | grep -q '[^[:space:]]'; then
  file_queue_item "not started" "$week" "The standing brief is blank between its markers, so no lieutenant was started."
  finish 3 "brief is blank between the markers"
fi
say "brief: lines $((ls_ + 1))-$((le_ - 1)) of the standing brief"

# ---- 7. substitution: YYYY-Www only ----
brief=$(printf '%s' "$raw" | awk -v w="$week" '{ gsub(/YYYY-Www/, w); print }') || finish 2 "substitution failed"
say "brief: $(printf '%s' "$raw" | grep -oF 'YYYY-Www' | wc -l | tr -d ' ') placeholders set to $week"

# ---- 8. dispatch ----
[ -d "$DISPATCH_CWD" ] || finish 2 "dispatch directory missing: $DISPATCH_CWD"
[ -d "$VAULT" ] || finish 2 "vault missing: $VAULT"
trusted=$(jq -r --arg d "$DISPATCH_CWD" '.projects[$d].hasTrustDialogAccepted // false' "$CLAUDE_JSON" 2>/dev/null) || trusted="unknown"
[ "$trusted" = "true" ] || finish 2 "dispatch directory is not a trusted workspace ($trusted): $DISPATCH_CWD — a background session there would stop at the trust prompt"

claim_line="Claim and release in one entry: dispatched \`$LT_NAME\` for $week, for $RULING. The job holds nothing now; the lieutenant claims and releases \`Agent rollup for $week.md\` and \`Cross-session rollup for $week.md\` itself. — tickle weekly-rollups"

# daemon_key_pids: running Claude daemons whose environment holds ANTHROPIC_API_KEY.
daemon_key_pids() {
  for dp in $(ps -axo pid=,command= | awk '$2 ~ /(^|\/)claude$/ && $3 == "daemon" && $4 == "run" {print $1}'); do
    ps eww -o command= -p "$dp" 2>/dev/null | tr ' ' '\n' | grep -q '^ANTHROPIC_API_KEY=' && echo "$dp"
  done
  return 0
}
if [ -n "${WR_TEST_DAEMON_KEY_PIDS+set}" ]; then keyed="$WR_TEST_DAEMON_KEY_PIDS"; else keyed=$(daemon_key_pids | tr '\n' ' '); fi
keyed=$(printf '%s' "$keyed" | sed 's/ *$//')

cmd=(env -u ANTHROPIC_API_KEY "$CLAUDE" --bg --agent lieutenant --name "$LT_NAME" -- "$brief")

if [ "$dry" = "1" ]; then
  say "environment: claude = $(command -v "$CLAUDE"); PATH = $PATH"
  auth=$(cl auth status 2>/dev/null | jq -r '"\(.loggedIn) \(.authMethod)"' 2>/dev/null) || auth="unknown"
  say "environment: auth (API key unset) = $auth; dispatch directory trusted = $trusted"
  if [ -n "$keyed" ]; then
    say "environment: Claude daemon pid(s) $keyed hold ANTHROPIC_API_KEY — a real run REFUSES to dispatch (exit 6) until they do not"
  else
    say "environment: no running Claude daemon holds ANTHROPIC_API_KEY"
  fi
  say "would run, from $DISPATCH_CWD:"
  printf '  cd %q &&' "$DISPATCH_CWD"; printf ' %q' "${cmd[@]}"; printf '\n'
  say "would append to $XLOG: $claim_line"
  finish 0 "DRY RUN complete — every guard passed; nothing dispatched"
fi

if [ -n "$keyed" ]; then
  file_queue_item "not started" "$week" "The running Claude daemon (pid $keyed) holds ANTHROPIC_API_KEY, and a \`claude --bg\` session takes the daemon's environment, so the lieutenant would bill the API key. The job refused to dispatch."
  finish 6 "Claude daemon pid(s) $keyed hold ANTHROPIC_API_KEY; refusing to dispatch"
fi

out=$(cd "$DISPATCH_CWD" && "${cmd[@]}" 2>&1)
drc=$?
say "dispatch output: $out"
if [ "$drc" -ne 0 ]; then
  file_queue_item "not started" "$week" "\`claude --bg\` exited $drc, so no lieutenant was started."
  finish 4 "claude --bg exited $drc"
fi

# The id `claude --bg` prints, read the way claude/bin/promote-session.sh reads it; the confirm matches that id, not a
# name, so a hand dispatch of the same name at the same moment can never confirm this one.
new_id=$(printf '%s' "$out" | tr -d '\r' | sed -E $'s/\x1b\\[[0-9;?]*[A-Za-z]//g' | awk '/^backgrounded/ {print $3; exit}') || true
if [ -z "$new_id" ]; then
  file_queue_item "not started" "$week" "\`claude --bg\` exited 0 but printed no \`backgrounded <id>\` line, so the job cannot confirm a lieutenant started. Output: $out"
  finish 4 "could not read the new session id from: $out"
fi
tries="${WR_CONFIRM_TRIES:-10}"; nap="${WR_CONFIRM_SLEEP:-3}"; seen=0; i=0
while [ "$i" -lt "$tries" ]; do
  n=$(cl agents --json 2>/dev/null | jq -r --arg id "$new_id" '[.[] | select(.id == $id or ((.sessionId // "") | startswith($id)))] | length' 2>/dev/null) || n=0
  [ "${n:-0}" -ge 1 ] 2>/dev/null && { seen=1; break; }
  i=$((i + 1)); [ "$i" -lt "$tries" ] && sleep "$nap"
done
if [ "$seen" != "1" ]; then
  file_queue_item "not started" "$week" "\`claude --bg\` returned 0, but its session $new_id did not appear in \`claude agents --json\`."
  finish 4 "claude --bg returned 0 but session $new_id did not appear in 'claude agents --json'"
fi
settle_not_started "$week"

stamp=$(date +%Y-%m-%dT%H:%M)
printf '\n## %s · tickle weekly-rollups — claim and release\n%s\n' "$stamp" "$claim_line" >> "$XLOG" || finish 2 "dispatched, but the claim line could not be appended to $XLOG"
finish 0 "dispatched $LT_NAME for $week"
