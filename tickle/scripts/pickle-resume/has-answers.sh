#!/usr/bin/env bash
# Gate: run iff there's an answered request that is OURS (workflow=pickle-ask),
# actionable (has a session_id to resume OR an ops_handoff to rebuild from),
# unprocessed, and not claimed by a live session.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/bin:/bin:$PATH"
STATE="$HOME/.claude/pickle-state"; PROC="$STATE/processed"; CLAIMS="$STATE/claims"
mkdir -p "$PROC" "$CLAIMS"
claim_live() { local c="$CLAIMS/$1"; [ -e "$c" ] || return 1; local a=$(( $(date +%s) - $(stat -f %m "$c" 2>/dev/null || echo 0) )); [ "$a" -lt 90 ]; }
meta_get() { printf '%s' "$1" | python3 -c "import sys,json;print(json.load(sys.stdin).get('metadata',{}).get('$2',''))" 2>/dev/null || true; }
ids=$(pickle inbox --status answered --json 2>/dev/null | python3 -c 'import sys,json;[print(r["id"]) for r in json.load(sys.stdin).get("requests",[])]' 2>/dev/null || true)
for id in $ids; do
  [ -e "$PROC/$id" ] && continue
  claim_live "$id" && continue
  meta=$(pickle show --json "$id" 2>/dev/null || echo '{}')
  [ "$(meta_get "$meta" workflow)" = "pickle-ask" ] || continue
  sid=$(meta_get "$meta" session_id); handoff=$(meta_get "$meta" ops_handoff)
  [ -n "$sid" ] || [ -n "$handoff" ] || continue        # need something to act on
  printf '{"run":true,"reason":"pickle %s answered (actionable)","event_id":"%s"}\n' "$id" "$id"
  exit 0
done
exit 1
