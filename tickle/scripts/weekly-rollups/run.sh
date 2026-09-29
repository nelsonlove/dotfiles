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
#   3. Live lieutenant: `claude agents --json` lists running sessions, busy or idle. A session named
#      `[L0-OB] weekly rollups` that is busy is at work: dispatch nothing (exit 0). One that is only idle is a finished
#      lieutenant nobody stopped; it still blocks a second one, but loudly: queue item "Weekly rollup not started
#      <week>" and exit 5. A listing that fails is exit 2: a check we cannot make is never a pass. This guard runs
#      before guard 4 so a lieutenant still writing last week's files never causes a false "missed" item.
#   4. Previous week: both rollups for the week before the target must exist. If either is missing, ONE queue item
#      "Weekly rollup missed <that week>" is filed for Nelson (never twice), and the run goes on.
#   5. No overwrite: if either rollup for the target week already exists, dispatch nothing (exit 0).
#   6. Brief markers: the brief is the text between the two marker lines of the standing brief note. Each marker must
#      appear exactly once, on its own line, start before end, with non-blank text between. If not: dispatch nothing,
#      file "Weekly rollup not started <week>", exit 3 (a FAILED run, loud).
#   7. Substitution: the ONLY substitution is the literal `YYYY-Www`. `<date>`, `<n>`, `<reason>` pass through.
#   8. Dispatch: `env -u ANTHROPIC_API_KEY claude --bg --agent lieutenant --name "[L0-OB] weekly rollups" -- <brief>`,
#      from the dotfiles checkout (a trusted workspace; /tmp and $HOME are not). Then the dispatch is CONFIRMED by
#      listing agents again. A failed or unconfirmed dispatch files "Weekly rollup not started <week>" and exits 4,
#      never a quiet success. On success, a "not started" item for the week (from an earlier failed run) gets a
#      Response line and `needs: nothing`, and one claim line naming the ruling is appended to the cross-session
#      log; the lieutenant posts its own release when it ends (standing brief, "At the end").
#
# THE API KEY. `env -u ANTHROPIC_API_KEY` keeps the key out of the CLI call, as the obsidian captain asked. It does NOT
# reach the lieutenant: a `claude --bg` session takes its environment from the Claude daemon, not from this shell
# (CLAUDE.md, measured 2026-09-29). Which account the lieutenant bills is the Claude daemon's, so --dry-run reports
# whether a running Claude daemon holds the key.
#
# --dry-run goes through every guard, prints what it would write and the exact dispatch command, and writes and
# dispatches NOTHING. It also reports what the dispatch depends on in THIS environment (which `claude`, its auth
# method, whether the dispatch directory is trusted), so running it under launchd's environment proves condition (d).
#
# Exit codes: 0 = done or deliberately skipped (reason on stdout); 2 = a check failed or bad usage; 3 = the brief is
# broken; 4 = the dispatch failed; 5 = an idle lieutenant of the same name blocks the dispatch. Every unexpected exit becomes 2 through the EXIT trap, as in pause-gate.sh.
#
# The queue item road: written straight to disk, created with noclobber so a second run never overwrites or duplicates
# it. Not through vault-mcp: a scheduled shell job has no MCP client, and a create-only write needs no `if_rev`.
#
# Test seams (environment): WR_VAULT (vault root), WR_LOADAVG (a fake 1-minute load), WR_CLAUDE (the claude binary),
# WR_DISPATCH_CWD (the dispatch directory), WR_CLAUDE_JSON (the file holding workspace trust), WR_CONFIRM_TRIES and
# WR_CONFIRM_SLEEP (how long to wait for the dispatched session to appear), PAUSE_NOTE (passed to pause-gate.sh).
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

dry=0
week=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    --week) shift; week="${1:-}" ;;
    --week=*) week="${1#--week=}" ;;
    *) finish 2 "usage: run.sh [--dry-run] [--week YYYY-Www] (unknown argument: $1)" ;;
  esac
  shift
done

here=$(cd "$(dirname "$0")" && pwd -P) || finish 2 "cannot resolve the script directory"
PAUSE_GATE="$here/../_lib/pause-gate.sh"
VAULT="${WR_VAULT:-$HOME/obsidian}"
CLAUDE="${WR_CLAUDE:-claude}"
DISPATCH_CWD="${WR_DISPATCH_CWD:-$HOME/repos/system/dotfiles}"
CLAUDE_JSON="${WR_CLAUDE_JSON:-$HOME/.claude.json}"

SYS="$VAULT/00-09 System"
NB_DIR="$SYS/03 Agents/03.04 Records/Agent notebook/rollups"
XS_DIR="$SYS/03 Agents/03.16 Cross-session log/rollups"
XLOG="$SYS/03 Agents/03.16 Cross-session log/CROSS-SESSION.md"
BRIEF_NOTE="$SYS/03 Agents/03.05 Agents & skills/Weekly rollups — standing brief.md"
QUEUE_DIR="$SYS/00 System management/00.08 Operator's console/Open items"
MARK_START="<!-- weekly-rollups brief: start -->"
MARK_END="<!-- weekly-rollups brief: end -->"

say() { echo "weekly-rollups: $*"; }
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

# file_queue_item <missed|not started> <week> <why> — ONE item per kind and week, created, never overwritten.
file_queue_item() {
  kind="$1"; qw="$2"; why="$3"
  title="Weekly rollup $kind $qw"
  qf="$QUEUE_DIR/$title.md"
  if [ -e "$qf" ]; then say "queue item already exists, not filed again: $qf"; return 0; fi
  stamp=$(date +%Y-%m-%dT%H:%M:%S%z | sed 's/\(..\)$/:\1/')
  uid=$(uuidgen | tr 'A-Z' 'a-z')
  body="---
type: Task/AgentTask
title: $title
description: \"The weekly rollups for $qw: $kind. The weekly-rollups tickle job found it; Nelson decides whether a lieutenant writes them now.\"
status: draft/proposed
needs: ruling
session: \"[L0-MA] tickle\"
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
  grep -qxF '  by: "tickle weekly-rollups"' "$nf" || { say "not touching $nf: not written by this job"; return 0; }
  st=$(date +%Y-%m-%dT%H:%M:%S%z | sed 's/\(..\)$/:\1/')
  tmpf="$nf.tmp.$$"
  awk -v st="$st" 'BEGIN{fm=0} /^---$/{fm++} fm==1 && /^needs:/{print "needs: nothing"; next} fm==1 && /^modified:/{print "modified: " st; next} {print}' "$nf" > "$tmpf" \
    && printf -- '- %s — The weekly-rollups job started the lieutenant for %s after all.\n' "$st" "$1" >> "$tmpf" \
    && mv "$tmpf" "$nf" || { say "WARNING: could not settle $nf"; return 0; }
  say "settled queue item: $nf"
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

# ---- 3. live lieutenant ----
command -v "$CLAUDE" >/dev/null 2>&1 || finish 2 "claude not found on PATH ($PATH)"
agents=$("$CLAUDE" agents --json 2>/dev/null) || finish 2 "'claude agents --json' failed; cannot tell whether $LT_NAME is live"
live=$(printf '%s' "$agents" | jq -r --arg n "$LT_NAME" '[.[] | select(.name == $n)] | length') || finish 2 "cannot parse 'claude agents --json'"
busy=$(printf '%s' "$agents" | jq -r --arg n "$LT_NAME" '[.[] | select(.name == $n and .status == "busy")] | length') || finish 2 "cannot parse 'claude agents --json'"
if [ "$busy" != "0" ]; then finish 0 "SKIPPED — $LT_NAME is live and busy; no second one started"; fi
if [ "$live" != "0" ]; then
  file_queue_item "not started" "$week" "A session named $LT_NAME is still listed by \`claude agents\` and idle ($live session(s)): a finished lieutenant nobody stopped. The job never starts a second one of that name. Stop it with \`claude stop\`, then run the job again."
  finish 5 "$LT_NAME is listed but idle ($live session(s)); stop it, then rerun"
fi
say "live check: no $LT_NAME running"

# ---- 4. previous week's rollups ----
missing=""
[ -e "$(nb_file "$prev")" ] || missing="$missing notebook"
[ -e "$(xs_file "$prev")" ] || missing="$missing cross-session"
if [ -n "$missing" ]; then
  say "previous week $prev missing:$missing"
  file_queue_item missed "$prev" "Missing at the run for $week:$missing."
else
  say "previous week $prev: both rollups exist"
fi

# ---- 5. no overwrite ----
exists=""
[ -e "$(nb_file "$week")" ] && exists="$exists $(nb_file "$week")"
[ -e "$(xs_file "$week")" ] && exists="$exists $(xs_file "$week")"
[ -z "$exists" ] || finish 0 "SKIPPED — $week already has a rollup, nothing overwritten, nothing dispatched:$exists"
say "target week $week: no rollup yet"

# ---- 6. brief markers ----
[ -r "$BRIEF_NOTE" ] || { file_queue_item "not started" "$week" "The standing brief note could not be read, so no lieutenant was started."; finish 3 "standing brief unreadable: $BRIEF_NOTE"; }
ns=$(grep -cxF -- "$MARK_START" "$BRIEF_NOTE")
ne=$(grep -cxF -- "$MARK_END" "$BRIEF_NOTE")
if [ "$ns" != "1" ] || [ "$ne" != "1" ]; then
  file_queue_item "not started" "$week" "The standing brief's markers are broken (start line $ns times, end line $ne times; each must be once, on its own line), so no lieutenant was started."
  finish 3 "brief markers broken: start $ns, end $ne (each must appear exactly once on its own line)"
fi
ls_=$(grep -nxF -- "$MARK_START" "$BRIEF_NOTE" | cut -d: -f1)
le_=$(grep -nxF -- "$MARK_END" "$BRIEF_NOTE" | cut -d: -f1)
if [ "$le_" -le "$((ls_ + 1))" ]; then
  file_queue_item "not started" "$week" "The standing brief's end marker is not after its start marker with text between, so no lieutenant was started."
  finish 3 "brief markers out of order or empty (start line $ls_, end line $le_)"
fi
raw=$(sed -n "$((ls_ + 1)),$((le_ - 1))p" "$BRIEF_NOTE") || finish 2 "cannot extract the brief"
if ! printf '%s' "$raw" | grep -q '[^[:space:]]'; then
  file_queue_item "not started" "$week" "The standing brief is blank between its markers, so no lieutenant was started."
  finish 3 "brief is blank between the markers"
fi
say "brief: lines $((ls_ + 1))-$((le_ - 1)) of the standing brief"

# ---- 7. substitution: YYYY-Www only ----
brief=$(printf '%s' "$raw" | awk -v w="$week" '{ gsub(/YYYY-Www/, w); print }') || finish 2 "substitution failed"
printf '%s' "$brief" | grep -qF 'YYYY-Www' && finish 2 "placeholder left after substitution"
say "brief: $(printf '%s' "$raw" | grep -oF 'YYYY-Www' | wc -l | tr -d ' ') placeholders set to $week"

# ---- 8. dispatch ----
[ -d "$DISPATCH_CWD" ] || finish 2 "dispatch directory missing: $DISPATCH_CWD"
trusted=$(jq -r --arg d "$DISPATCH_CWD" '.projects[$d].hasTrustDialogAccepted // false' "$CLAUDE_JSON" 2>/dev/null) || trusted="unknown"
[ "$trusted" = "true" ] || finish 2 "dispatch directory is not a trusted workspace ($trusted): $DISPATCH_CWD — a background session there would stop at the trust prompt"

claim_line="Dispatched \`$LT_NAME\` for $week, for $RULING: it writes \`Agent rollup for $week.md\` and \`Cross-session rollup for $week.md\` and runs the spec Steps sweep; the lieutenant posts the release. — tickle weekly-rollups"

if [ "$dry" = "1" ]; then
  say "environment: claude = $(command -v "$CLAUDE"); PATH = $PATH"
  auth=$(env -u ANTHROPIC_API_KEY "$CLAUDE" auth status 2>/dev/null | jq -r '"\(.loggedIn) \(.authMethod)"' 2>/dev/null) || auth="unknown"
  say "environment: auth (API key unset) = $auth; dispatch directory trusted = $trusted"
  dpids=$(ps -axo pid=,command= | awk '$0 ~ /claude daemon run/ && $0 !~ /awk/ {print $1}')
  if [ -z "$dpids" ]; then
    say "environment: no Claude daemon running; claude --bg would start one from THIS environment (API key unset)"
  else
    for dp in $dpids; do
      k=$(ps eww -o command= -p "$dp" 2>/dev/null | tr ' ' '\n' | grep -c '^ANTHROPIC_API_KEY=')
      say "environment: Claude daemon pid $dp holds ANTHROPIC_API_KEY: $([ "${k:-0}" -gt 0 ] && echo YES || echo no) (a --bg session takes its environment from it)"
    done
  fi
  say "would run, from $DISPATCH_CWD:"
  printf '  cd %q && env -u ANTHROPIC_API_KEY %q --bg --agent lieutenant --name %q -- %q\n' "$DISPATCH_CWD" "$CLAUDE" "$LT_NAME" "$brief"
  say "would append to $XLOG: $claim_line"
  finish 0 "DRY RUN complete — every guard passed; nothing dispatched"
fi

out=$(cd "$DISPATCH_CWD" && env -u ANTHROPIC_API_KEY "$CLAUDE" --bg --agent lieutenant --name "$LT_NAME" -- "$brief" 2>&1)
drc=$?
say "dispatch output: $out"
if [ "$drc" -ne 0 ]; then
  file_queue_item "not started" "$week" "\`claude --bg\` exited $drc, so no lieutenant was started."
  finish 4 "claude --bg exited $drc"
fi

tries="${WR_CONFIRM_TRIES:-10}"; nap="${WR_CONFIRM_SLEEP:-3}"; seen=0; i=0
while [ "$i" -lt "$tries" ]; do
  n=$("$CLAUDE" agents --json 2>/dev/null | jq -r --arg n "$LT_NAME" '[.[] | select(.name == $n)] | length' 2>/dev/null) || n=0
  [ "${n:-0}" -ge 1 ] 2>/dev/null && { seen=1; break; }
  i=$((i + 1)); sleep "$nap"
done
if [ "$seen" != "1" ]; then
  file_queue_item "not started" "$week" "\`claude --bg\` returned 0, but no session named $LT_NAME appeared in \`claude agents --json\`."
  finish 4 "claude --bg returned 0 but no session named $LT_NAME appeared in 'claude agents --json'"
fi
settle_not_started "$week"

stamp=$(date +%Y-%m-%dT%H:%M)
printf '\n## %s · tickle weekly-rollups — claim\n%s\n' "$stamp" "$claim_line" >> "$XLOG" || finish 2 "dispatched, but the claim line could not be appended to $XLOG"
finish 0 "dispatched $LT_NAME for $week"
