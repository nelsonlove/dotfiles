#!/bin/bash
# Tests for weekly-rollups/run.sh. Run: bash tickle/scripts/weekly-rollups/tests/run-tests.sh
#
# Every case runs against a throwaway vault under /tmp and a stub `claude` that records its calls and never reaches
# the real CLI, the real fleet or the API. No live session id and no real vault path is used. Each case runs under
# `env -i` with launchd's PATH, so nothing leaks in from the session that runs the tests.
set -u

here=$(cd "$(dirname "$0")" && pwd -P)
RUN="$here/../run.sh"
pass=0; fail=0; failed=""

ROOT=$(mktemp -d /tmp/weekly-rollups-tests.XXXXXX)
trap '/usr/bin/trash "$ROOT" 2>/dev/null' EXIT

BRIEF_BODY='You are `[L0-OB] weekly rollups`, for the ISO week **YYYY-Www**.
Write `Agent rollup for YYYY-Www.md`.
Strike as `~~text~~ — done <date>, [[work item]]` or `— no object: <reason>`.
Report `<n> spec notes read`.
A --- line is a legal body line.
---'

# new_case: a fresh vault, stub and pause note. Sets V, S, Q.
new_case() {
  C=$(mktemp -d "$ROOT/case.XXXXXX")
  V="$C/vault"; S="$C/stub"
  SYS="$V/00-09 System"
  mkdir -p "$SYS/03 Agents/03.04 Records/Agent notebook/rollups" "$SYS/03 Agents/03.16 Cross-session log/rollups" \
           "$SYS/03 Agents/03.05 Agents & skills" "$SYS/00 System management/00.08 Operator's console/Open items" "$S" "$C/dotfiles"
  Q="$SYS/00 System management/00.08 Operator's console/Open items"
  NB="$SYS/03 Agents/03.04 Records/Agent notebook/rollups"
  XS="$SYS/03 Agents/03.16 Cross-session log/rollups"
  XLOG="$SYS/03 Agents/03.16 Cross-session log/CROSS-SESSION.md"
  BN="$SYS/03 Agents/03.05 Agents & skills/Weekly rollups — standing brief.md"
  : > "$XLOG"
  printf -- '---\ntitle: brief\n---\n\n# Brief\n\n<!-- weekly-rollups brief: start -->\n%s\n<!-- weekly-rollups brief: end -->\n\n## History\n' "$BRIEF_BODY" > "$BN"
  # previous week (2026-W39) complete by default
  : > "$NB/Agent rollup for 2026-W39.md"; : > "$XS/Cross-session rollup for 2026-W39.md"
  printf -- '---\npaused: false\n---\n' > "$C/Pause.md"
  printf '{"projects":{"%s":{"hasTrustDialogAccepted":true}}}' "$C/dotfiles" > "$C/claude.json"
  echo '[]' > "$S/agents.json"; echo 0 > "$S/agents_rc"; echo 0 > "$S/bg_rc"; echo 1 > "$S/bg_registers"
  cat > "$S/claude" <<'STUB'
#!/bin/bash
S=$(dirname "$0")
printf '%s\n' "$*" >> "$S/calls"
[ -n "${ANTHROPIC_API_KEY:-}" ] && echo "KEY_LEAKED on: $1" >> "$S/calls"
case "$1" in
  agents) rc=$(cat "$S/agents_rc"); [ "$rc" = 0 ] && cat "$S/agents.json"; exit "$rc" ;;
  auth) echo '{"loggedIn":true,"authMethod":"claude.ai"}'; exit 0 ;;
  --bg)
    pwd > "$S/bg_cwd"
    shift; while [ "$#" -gt 1 ]; do shift; done; printf '%s' "$1" > "$S/bg_prompt"
    case "$(cat "$S/bg_registers")" in
      1) echo '[{"id":"deadbeef","name":"[L0-OB] weekly rollups","pid":1,"status":"busy","state":"working"}]' > "$S/agents.json" ;;
      other) echo '[{"id":"cafef00d","name":"[L0-OB] weekly rollups","pid":2,"status":"busy","state":"working"}]' > "$S/agents.json" ;;
    esac
    if [ "$(cat "$S/bg_registers")" = noid ]; then echo "started"; else echo "backgrounded session deadbeef"; fi
    exit "$(cat "$S/bg_rc")" ;;
esac
exit 0
STUB
  chmod +x "$S/claude"
}

# go [args...]: run the job in a launchd-like environment. Sets OUT and RC.
go() {
  OUT=$(env -i HOME="$C" USER=nelson LOGNAME=nelson PATH=/usr/bin:/bin:/usr/sbin:/sbin TMPDIR=/tmp \
        ANTHROPIC_API_KEY=sk-test-should-be-unset \
        WR_VAULT="$V" WR_CLAUDE="$S/claude" WR_DISPATCH_CWD="$C/dotfiles" WR_CLAUDE_JSON="$C/claude.json" \
        WR_LOADAVG="${LOAD:-1.00}" WR_LOCK="${LOCKPATH:-$C/lock/run.lock}" WR_TEST_DAEMON_KEY_PIDS="${KEYED:-}" WR_CONFIRM_TRIES=2 WR_CONFIRM_SLEEP=0 PAUSE_NOTE="$C/Pause.md" \
        /bin/bash "$RUN" "$@" 2>&1)
  RC=$?
}

check() { # check <name> <condition...>
  name="$1"; shift
  if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); failed="$failed\n  - $name"; printf 'FAIL %s\n---\n%s\n---\n' "$name" "$OUT"; fi
}
dispatched() { [ -f "$S/bg_prompt" ]; }
not_dispatched() { [ ! -f "$S/bg_prompt" ]; }
out_has() { printf '%s' "$OUT" | grep -qF -- "$1"; }
queue_count() { ls "$Q" | wc -l | tr -d ' '; }

# 1. Happy path: dispatch, substitution, angle forms untouched, key unset, trusted cwd, claim line.
new_case; go --week 2026-W40
check "happy: exit 0" [ "$RC" = 0 ]
check "happy: dispatched" dispatched
check "subst: week filled" grep -qF '**2026-W40**' "$S/bg_prompt"
check "subst: no placeholder left" bash -c "! grep -qF 'YYYY-Www' '$S/bg_prompt'"
check "subst: <date> untouched" grep -qF '— done <date>, [[work item]]' "$S/bg_prompt"
check "subst: <reason> untouched" grep -qF '— no object: <reason>' "$S/bg_prompt"
check "subst: <n> untouched" grep -qF 'Report `<n> spec notes read`' "$S/bg_prompt"
check "subst: --- body line kept" grep -qx -- '---' "$S/bg_prompt"
check "subst: markers not in brief" bash -c "! grep -qF 'weekly-rollups brief:' '$S/bg_prompt'"
check "every claude call: API key unset" bash -c "! grep -qF KEY_LEAKED '$S/calls'"
check "dispatch: agent, name, --" grep -qF -- "--bg --agent lieutenant --name [L0-OB] weekly rollups -- " "$S/calls"
check "dispatch: from trusted cwd" [ "$(cat "$S/bg_cwd")" = "$C/dotfiles" ]
check "claim: one claim-and-release entry" [ "$(grep -c 'tickle weekly-rollups — claim and release' "$XLOG")" = 1 ]
check "claim: names the ruling" grep -qF 'alright go for it' "$XLOG"
check "happy: no queue item" [ "$(queue_count)" = 0 ]

# 2. Dry run: every guard, prints the command, writes and dispatches nothing.
new_case; /usr/bin/trash "$NB/Agent rollup for 2026-W39.md"
before=$(find "$V" -type f -exec md5 -q {} \; | sort | md5 -q)
go --dry-run --week 2026-W40
after=$(find "$V" -type f -exec md5 -q {} \; | sort | md5 -q)
check "dry: exit 0" [ "$RC" = 0 ]
check "dry: nothing dispatched" not_dispatched
check "dry: vault unchanged" [ "$before" = "$after" ]
check "dry: would file queue item" out_has "would file queue item"
check "dry: prints command" out_has "env -u ANTHROPIC_API_KEY"
check "dry: reports auth and trust" out_has "dispatch directory trusted = true"
check "dry: complete" out_has "DRY RUN complete"
check "dry: command has --" out_has "weekly\\ rollups -- "

# 3. Paused: skip, record, no dispatch.
new_case; printf -- '---\npaused: true\npaused-by: test\n---\n' > "$C/Pause.md"; go --week 2026-W40
check "paused: exit 0" [ "$RC" = 0 ]; check "paused: reason" out_has "fleet is paused"; check "paused: no dispatch" not_dispatched

# 4. Pause flag unreadable: loud.
new_case; printf 'no frontmatter\n' > "$C/Pause.md"; go --week 2026-W40
check "pause bad: exit 2" [ "$RC" = 2 ]; check "pause bad: no dispatch" not_dispatched

# 5. Load gate: 10.00 skips, 9.99 runs.
new_case; LOAD=10.00 go --week 2026-W40
check "load 10: exit 0" [ "$RC" = 0 ]; check "load 10: reason" out_has "load 10.00 is 10 or more"; check "load 10: no dispatch" not_dispatched
new_case; LOAD=9.99 go --week 2026-W40
check "load 9.99: dispatched" dispatched

# 6. Previous week missing: ONE queue item, dispatch goes on; a second run files no second item.
new_case; /usr/bin/trash "$XS/Cross-session rollup for 2026-W39.md"; go --week 2026-W40
check "prev missing: dispatched" dispatched
check "prev missing: one item" [ "$(queue_count)" = 1 ]
check "prev missing: title" [ -f "$Q/Weekly rollup missed 2026-W39.md" ]
check "prev missing: names what" grep -qF 'cross-session' "$Q/Weekly rollup missed 2026-W39.md"
check "prev missing: frontmatter" grep -qx 'needs: ruling' "$Q/Weekly rollup missed 2026-W39.md"
cp "$Q/Weekly rollup missed 2026-W39.md" "$C/item.bak"
echo '[]' > "$S/agents.json"; go --week 2026-W40
check "prev missing: rerun keeps one item" [ "$(queue_count)" = 1 ]
check "prev missing: item not overwritten" cmp -s "$C/item.bak" "$Q/Weekly rollup missed 2026-W39.md"

# 7. No overwrite: either target rollup existing stops the dispatch.
new_case; echo keep > "$NB/Agent rollup for 2026-W40.md"; go --week 2026-W40
check "exists nb: exit 0" [ "$RC" = 0 ]; check "exists nb: no dispatch" not_dispatched
check "exists nb: untouched" [ "$(cat "$NB/Agent rollup for 2026-W40.md")" = keep ]
new_case; echo keep > "$XS/Cross-session rollup for 2026-W40.md"; go --week 2026-W40
check "exists xs: no dispatch" not_dispatched

# 8. Brief markers: missing, duplicated, not on own line, out of order -> exit 3, no dispatch, queue item.
new_case; sed -i '' '/brief: end -->/d' "$BN"; go --week 2026-W40
check "marker missing: exit 3" [ "$RC" = 3 ]; check "marker missing: no dispatch" not_dispatched
check "marker missing: queue item" [ -f "$Q/Weekly rollup not started 2026-W40.md" ]
new_case; printf '<!-- weekly-rollups brief: start -->\n' >> "$BN"; go --week 2026-W40
check "marker twice: exit 3" [ "$RC" = 3 ]; check "marker twice: no dispatch" not_dispatched
new_case; sed -i '' 's/^<!-- weekly-rollups brief: start -->$/text <!-- weekly-rollups brief: start -->/' "$BN"; go --week 2026-W40
check "marker inline: exit 3" [ "$RC" = 3 ]
new_case; printf -- '---\n---\n<!-- weekly-rollups brief: start -->\n  \n\n<!-- weekly-rollups brief: end -->\n' > "$BN"; go --week 2026-W40
check "blank brief: exit 3" [ "$RC" = 3 ]; check "blank brief: no dispatch" not_dispatched
new_case; printf -- '---\n---\n<!-- weekly-rollups brief: end -->\nx\n<!-- weekly-rollups brief: start -->\n' > "$BN"; go --week 2026-W40
check "marker order: exit 3" [ "$RC" = 3 ]; check "marker order: no dispatch" not_dispatched

# 9. Live lieutenant: no second one.
new_case; echo '[{"name":"[L0-OB] weekly rollups","pid":42,"status":"busy","state":"working"}]' > "$S/agents.json"; go --week 2026-W40
check "live busy: exit 0" [ "$RC" = 0 ]; check "live busy: reason" out_has "live and at work"; check "live busy: no dispatch" not_dispatched
new_case; echo '[{"name":"[L0-OB] weekly rollups","pid":42,"status":"idle","state":"blocked"}]' > "$S/agents.json"; go --week 2026-W40
check "live blocked: exit 0" [ "$RC" = 0 ]; check "live blocked: no dispatch" not_dispatched; check "live blocked: no item" [ "$(queue_count)" = 0 ]
new_case; echo '[{"name":"[L0-OB] weekly rollups","pid":42,"status":"idle","state":"done"}]' > "$S/agents.json"; go --week 2026-W40
check "live idle: exit 5" [ "$RC" = 5 ]; check "live idle: no dispatch" not_dispatched
check "live idle: queue item" grep -qF 'claude stop' "$Q/Weekly rollup not started 2026-W40.md"
check "item session is the job" grep -qxF 'session: "tickle weekly-rollups"' "$Q/Weekly rollup not started 2026-W40.md"
new_case; /usr/bin/trash "$NB/Agent rollup for 2026-W39.md"; echo '[{"name":"[L0-OB] weekly rollups","pid":42,"status":"busy","state":"working"}]' > "$S/agents.json"; go --week 2026-W40
check "live busy: no false missed item" [ "$(queue_count)" = 0 ]
new_case; echo '[{"name":"[L0-OB] monthly rollups","pid":42,"status":"busy","state":"working"}]' > "$S/agents.json"; go --week 2026-W40
check "live: other name does not block" dispatched
new_case; echo '[{"name":"[L0-OB] weekly rollups 2026-W40","pid":42,"status":"busy","state":"working"}]' > "$S/agents.json"; go --week 2026-W40
check "live: renamed session still blocks" not_dispatched
old=$(( ($(date +%s) - 90000) * 1000 ))
new_case; echo "[{\"name\":\"[L0-OB] weekly rollups\",\"pid\":42,\"status\":\"idle\",\"state\":\"blocked\",\"startedAt\":$old}]" > "$S/agents.json"; go --week 2026-W40
check "stuck: exit 5" [ "$RC" = 5 ]; check "stuck: no dispatch" not_dispatched; check "stuck: queue item" grep -qF '24 hours' "$Q/Weekly rollup not started 2026-W40.md"
new_case; echo '' > "$S/agents.json"; go --week 2026-W40
check "empty listing: exit 2" [ "$RC" = 2 ]; check "empty listing: no dispatch" not_dispatched; check "empty listing: no item" [ "$(queue_count)" = 0 ]
new_case; echo 1 > "$S/bg_rc"; go --week 2026-W40; echo 2 > "$S/bg_rc"; echo '[]' > "$S/agents.json"; go --week 2026-W40
check "repeat failure: new cause recorded" grep -qF 'Failed again: `claude --bg` exited 2' "$Q/Weekly rollup not started 2026-W40.md"
check "repeat failure: still one item" [ "$(queue_count)" = 1 ]
new_case; KEYED=4242 go --week 2026-W40
check "daemon key: exit 6" [ "$RC" = 6 ]; check "daemon key: no dispatch" not_dispatched; check "daemon key: queue item" grep -qF 'ANTHROPIC_API_KEY' "$Q/Weekly rollup not started 2026-W40.md"
new_case; KEYED=4242 go --dry-run --week 2026-W40
check "daemon key dry: reported" out_has "REFUSES to dispatch"

# 10. Failures are loud: listing fails, dispatch fails, dispatch returns 0 but no session appears, untrusted cwd.
new_case; echo 1 > "$S/agents_rc"; go --week 2026-W40
check "agents fail: exit 2" [ "$RC" = 2 ]; check "agents fail: no dispatch" not_dispatched
new_case; echo 1 > "$S/bg_rc"; go --week 2026-W40
check "bg fail: exit 4" [ "$RC" = 4 ]; check "bg fail: no claim" [ ! -s "$XLOG" ]
check "bg fail: queue item" grep -qx 'needs: ruling' "$Q/Weekly rollup not started 2026-W40.md"
echo 0 > "$S/bg_rc"; echo '[]' > "$S/agents.json"; /usr/bin/trash "$S/bg_prompt"; go --week 2026-W40
check "rerun ok: exit 0" [ "$RC" = 0 ]; check "rerun ok: dispatched" dispatched
check "rerun ok: item settled" grep -qx 'needs: nothing' "$Q/Weekly rollup not started 2026-W40.md"
check "rerun ok: response line" grep -qF 'started the lieutenant for 2026-W40 after all' "$Q/Weekly rollup not started 2026-W40.md"
echo 1 > "$S/bg_rc"; echo '[]' > "$S/agents.json"; /usr/bin/trash "$S/bg_prompt"; go --week 2026-W40
check "fail again: reopened" grep -qx 'needs: ruling' "$Q/Weekly rollup not started 2026-W40.md"
check "fail again: response line" grep -qF 'Failed again:' "$Q/Weekly rollup not started 2026-W40.md"

# 10b. A Response line lands under ## Response, not after a later section.
new_case; echo 1 > "$S/bg_rc"; go --week 2026-W40
printf '\n## History\n\n- added by hand\n' >> "$Q/Weekly rollup not started 2026-W40.md"
echo 0 > "$S/bg_rc"; echo '[]' > "$S/agents.json"; go --week 2026-W40
under_response() { awk '/^## Response/{r=1;next} /^## /{r=0} r && /after all/{f=1} END{exit !f}' "$Q/Weekly rollup not started 2026-W40.md"; }
check "response placement" under_response
check "history kept last" [ "$(tail -1 "$Q/Weekly rollup not started 2026-W40.md")" = "- added by hand" ]

# 10c. Lock: a run holding the lock makes a second run skip; a leftover lock file with no holder does not block.
new_case; mkdir -p "$C/lock"; /usr/bin/lockf -s -t 0 "$C/lock/run.lock" sleep 30 & holder=$!; sleep 1; go --week 2026-W40
check "lock held: exit 0" [ "$RC" = 0 ]; check "lock held: reason" out_has "another weekly-rollups run"; check "lock held: no dispatch" not_dispatched
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
new_case; mkdir -p "$C/lock"; : > "$C/lock/run.lock"; go --week 2026-W40
check "leftover lock file: dispatched" dispatched

# 10d. Queue items: UUIDv7 uid, and an item whose quotes a tool removed is still the job's own.
new_case; echo 1 > "$S/bg_rc"; go --week 2026-W40
check "uid v7" grep -Eq '^uid: [0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' "$Q/Weekly rollup not started 2026-W40.md"
sed -i '' 's/^  by: "tickle weekly-rollups"$/  by: tickle weekly-rollups/' "$Q/Weekly rollup not started 2026-W40.md"
echo 0 > "$S/bg_rc"; echo '[]' > "$S/agents.json"; go --week 2026-W40
check "unquoted by: still settled" grep -qx 'needs: nothing' "$Q/Weekly rollup not started 2026-W40.md"
new_case; echo 0 > "$S/bg_registers"; go --week 2026-W40
check "bg silent: exit 4" [ "$RC" = 4 ]; check "bg silent: no claim" [ ! -s "$XLOG" ]
check "bg silent: queue item" [ -f "$Q/Weekly rollup not started 2026-W40.md" ]
new_case; echo '{"projects":{}}' > "$C/claude.json"; go --week 2026-W40
check "untrusted: exit 2" [ "$RC" = 2 ]; check "untrusted: no dispatch" not_dispatched

# 10e. Confirm by id: a same-name session with another id does not confirm; no id printed is a failure.
new_case; echo other > "$S/bg_registers"; go --week 2026-W40
check "other id: exit 4" [ "$RC" = 4 ]; check "other id: no claim" [ ! -s "$XLOG" ]
new_case; echo noid > "$S/bg_registers"; go --week 2026-W40
check "no id: exit 4" [ "$RC" = 4 ]; check "no id: queue item" grep -qF 'backgrounded <id>' "$Q/Weekly rollup not started 2026-W40.md"

# 10f. Guard 3 settles an open "not started" item once the week's rollups exist.
new_case; echo 1 > "$S/bg_rc"; go --week 2026-W40; : > "$NB/Agent rollup for 2026-W40.md"; go --week 2026-W40
check "exists: settles item" grep -qx 'needs: nothing' "$Q/Weekly rollup not started 2026-W40.md"
check "exists: says why" grep -qF 'The rollups for 2026-W40 now exist.' "$Q/Weekly rollup not started 2026-W40.md"

# 10g. No "missed" item while an open "not started" item asks about the same week.
new_case; /usr/bin/trash "$NB/Agent rollup for 2026-W39.md" "$XS/Cross-session rollup for 2026-W39.md"
echo 1 > "$S/bg_rc"; go --week 2026-W39; echo 0 > "$S/bg_rc"; echo '[]' > "$S/agents.json"; go --week 2026-W40
check "no double ask: the not-started item is there" [ -f "$Q/Weekly rollup not started 2026-W39.md" ]
check "no double ask" [ ! -e "$Q/Weekly rollup missed 2026-W39.md" ]

# 10h. A closed item is never reopened; a new failure files a dated item.
new_case; echo 1 > "$S/bg_rc"; go --week 2026-W40
sed -i '' 's|^status: draft/proposed$|status: archived/done|' "$Q/Weekly rollup not started 2026-W40.md"
cp "$Q/Weekly rollup not started 2026-W40.md" "$C/closed.bak"; echo '[]' > "$S/agents.json"; go --week 2026-W40
check "closed: untouched" cmp -s "$C/closed.bak" "$Q/Weekly rollup not started 2026-W40.md"
check "closed: dated item filed" [ -f "$Q/Weekly rollup not started 2026-W40 (again $(date +%Y-%m-%d)).md" ]

# 10i. A lock that cannot be taken for any reason but "held" is a failed run.
new_case; mkdir -p "$C/ro"; chmod 500 "$C/ro"; LOCKPATH="$C/ro/run.lock" go --week 2026-W40; chmod 700 "$C/ro"
check "lock unusable: exit 2" [ "$RC" = 2 ]; check "lock unusable: says so" out_has "lockf could not take the lock"; check "lock unusable: no dispatch" not_dispatched

# 11. Week arithmetic and bad input.
new_case; go --dry-run --week 2027-W01
check "year edge: prev is 2026-W53" out_has "previous week 2026-W53"
new_case; go --dry-run --week 2026-W40
check "W40 Monday" out_has "Monday 2026-09-28"
new_case; go --dry-run --week 2025-W53
check "no W53 in 2025: exit 2" [ "$RC" = 2 ]
new_case; go --week 26-W4
check "bad week: exit 2" [ "$RC" = 2 ]
new_case; go --week=
check "empty --week=: exit 2" [ "$RC" = 2 ]; check "empty --week=: no dispatch" not_dispatched
new_case; go --week
check "empty --week: exit 2" [ "$RC" = 2 ]; check "empty --week: no dispatch" not_dispatched
new_case; go --bogus
check "bad arg: exit 2" [ "$RC" = 2 ]

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ] || { printf 'failed:%b\n' "$failed"; exit 1; }
