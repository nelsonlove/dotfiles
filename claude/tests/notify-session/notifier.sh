#!/usr/bin/env bash
# The notifier and its injecting hook, end to end, WITHOUT NOTIFYING ANYTHING REAL.
#
# HOW IT STAYS SAFE. Every notifier case passes `--dry-run`, so the script prints the acts it would take and
# writes nothing and wakes nobody; the notice directory, the fleet log and the wake script are all redirected
# to a temp dir through `NOTIFY_NOTICES_DIR`, `NOTIFY_FLEET_LOG` and `NOTIFY_WAKE_SCRIPT`; and the two cases
# that DO write a notice use a fake wake script that only records that it was called. No accept verb is
# invoked — this tests the machine that is TOLD one happened, which is the opposite — and no session is
# woken, dispatched or stopped.
#
# THE ONE THING IT CANNOT FAKE is the session listing, which comes from `claude agents --json --all`. So the
# cases that need a matching session take ONE THROWAWAY id you dispatch yourself, exactly as
# `claude/tests/fleet-ranks/wake-and-promote.sh` does, and never a live fleet id:
#
#     cd /tmp
#     claude --bg --agent lieutenant --name "[L0-FL] notifier battery target" \
#            "[test artifact — safe to delete] Do nothing. Reply standing-by and stop."
#     bash claude/tests/notify-session/notifier.sh <id>
#     claude stop <id>; claude rm <id>      # afterwards, and check the listing after
#
# A FIXTURE IS NEVER NAMED AS A RANK ABOVE A LIEUTENANT, widened by the captain on 2026-09-27 after a
# `[C0-CC] battery captain` throwaway appeared in the fleet view as a captain nobody had claimed. A throwaway
# is named for what it TESTS, as a lieutenant on its ship, and dispatched `--agent lieutenant`. Nothing here
# needs a captain-ranked session: the notifier reads a NAME out of a note and looks it up, so the rank of the
# session it finds never enters into it.
#
# Run with no arguments and the listing-dependent cases are SKIPPED and counted as skipped rather than
# passed, because a suite that silently tests less than it claims is worse than one that says so.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
ROOT=$(cd "$HERE/../../.." && pwd -P)
NOTIFY="$ROOT/claude/bin/notify-session.sh"
INJECT="$ROOT/claude/hooks/notice-inject.sh"
LT="${1:-}"   # one throwaway; there was a second for a captain-ranked row, and nothing here needs one
TMP=$(mktemp -d -t notifier-battery) || exit 1
trap 'rm -rf "$TMP"' EXIT
export NOTIFY_NOTICES_DIR="$TMP/notices"
export NOTIFY_FLEET_LOG="$TMP/log.md"
export NOTIFY_WAKE_SCRIPT="$TMP/fake-wake.sh"
# SEALED FROM THE REAL RECORDS since the dedupe and audience were added: the state file and the notebook roots (read for an
# ended lieutenant's entry) are temp directories, so this suite never reads the fleet's notebook or writes the real state.
export NOTIFY_STATE_DIR="$TMP/state"
export NOTIFY_AGENTS_DIR="$TMP/agents"
: > "$NOTIFY_FLEET_LOG"
mkdir -p "$NOTIFY_NOTICES_DIR"
cat > "$NOTIFY_WAKE_SCRIPT" <<'FAKE'
#!/usr/bin/env bash
# [test artifact] records that it was called, and with what; wakes nothing.
printf '%s\n' "$*" >> "$(dirname "$0")/wake-calls.log"
exit 0
FAKE
chmod +x "$NOTIFY_WAKE_SCRIPT"
n=0; fails=0; skips=0
pass() { n=$((n + 1)); printf 'PASS  %s\n' "$1"; }
fail() { n=$((n + 1)); fails=$((fails + 1)); printf 'FAIL  %-60s %s\n' "$1" "${2:-}"; }
skip() { n=$((n + 1)); skips=$((skips + 1)); printf 'SKIP  %-60s %s\n' "$1" "${2:-no throwaway ids given}"; }

note() {  # note <name> <session-value-or-empty> ; prints the path
  local f="$TMP/$1.md"
  if [ -n "${2:-}" ]; then
    printf -- '---\ntype: Task\nsession: "%s"\nstatus: verified\n---\n\n# %s\n' "$2" "$1" > "$f"
  else
    printf -- '---\ntype: Task\nstatus: verified\n---\n\n# %s\n' "$1" > "$f"
  fi
  printf '%s' "$f"
}

echo "=== the interface refuses what it must, and never invents a stamp"
NO_SESSION=$(note plain "")
for args in \
  "--event verified --at 2026-09-27T14:05 --words w" \
  "--note $NO_SESSION --at 2026-09-27T14:05 --words w" \
  "--note $NO_SESSION --event verified --words w" \
  "--note $NO_SESSION --event shouted --at 2026-09-27T14:05 --words w" \
  "--note $NO_SESSION --event verified --at yesterday --words w" \
  "--note $NO_SESSION --event verified --at 2026-9-27 --words w" \
  "--note /tmp/there-is-no-such-note.md --event verified --at 2026-09-27T14:05 --words w" ; do
  # shellcheck disable=SC2086
  if "$NOTIFY" $args --dry-run >/dev/null 2>&1; then
    fail "refuses: $args" "it was accepted"
  else
    pass "refuses: $args"
  fi
done
if "$NOTIFY" --note "$NO_SESSION" --event verified --at 2026-09-27T14:05 --words "his words" --dry-run >/dev/null 2>&1; then
  pass "accepts a complete call"
else
  fail "accepts a complete call" "it was refused"
fi

echo
echo "=== who is told when no session matches: the caller names it, this script never derives it"
# THE SHIP MAP LEFT THIS SCRIPT on Nelson's call of 2026-09-27 — "the ship stuff is specific to our vault and
# needs to be kept as policy in the vault, not shipped with the PR" — so these cases no longer assert a map.
# They assert the interface that replaced it: `--captain` is taken as given, and with none given the rear
# admiral holds it. The map itself is now tested where it lives, by whatever the vault's policy note binds.
captain_case() {  # captain_case <label> <expected fragment> [extra args...]
  # The label and the wanted text are SHIFTED OFF before "$@" is passed on. Without that they arrived as
  # arguments to the notifier, which refused them by name — five cases failing on the harness, not the code.
  local label="$1" want="$2" out
  shift 2
  printf -- '---\ntype: Task\nstatus: verified\n---\n' > "$TMP/no-match.md"
  out=$("$NOTIFY" --note "$TMP/no-match.md" --event verified --at 2026-09-27T14:05 --words w --dry-run "$@" 2>&1)
  case "$out" in
    *"$want"*) pass "$label" ;;
    *) fail "$label" "got: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-140)" ;;
  esac
}
captain_case "a captain the caller names is the one told"        "[C0-OB] obsidian"   --captain "[C0-OB] obsidian"
captain_case "another one, to show nothing is inferred"          "[C2-FL] vault-mcp-suite" --captain "[C2-FL] vault-mcp-suite"
captain_case "with no --captain, the rear admiral holds it"      "[A0] rear admiral"
captain_case "the record says the caller named it"               "named by the caller"     --captain "[C0-OB] obsidian"
captain_case "and says when nobody did"                          "no --captain was given"
# A NOTE'S PATH NO LONGER DECIDES ANYTHING, which is the point of the change and is worth one case of its own:
# the same note under a vault-shaped path still goes to whoever the caller named, and to the rear admiral when
# nobody was named. If a map ever creeps back in, this pair fails.
mkdir -p "$TMP/vault/00-09 System/03 Agents/03.12 Claude Code plugins"
printf -- '---\ntype: Task\nstatus: verified\n---\n' > "$TMP/vault/00-09 System/03 Agents/03.12 Claude Code plugins/x.md"
out=$("$NOTIFY" --note "$TMP/vault/00-09 System/03 Agents/03.12 Claude Code plugins/x.md" --event verified --at 2026-09-27T14:05 --words w --dry-run 2>&1)
case "$out" in
  *"[A0] rear admiral"*) pass "a vault-shaped path infers no captain by itself" ;;
  *) fail "a vault-shaped path infers no captain by itself" "got: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-140)" ;;
esac
out=$("$NOTIFY" --note "$TMP/vault/00-09 System/03 Agents/03.12 Claude Code plugins/x.md" --event verified --at 2026-09-27T14:05 --words w --captain "[C0-CC] claude code" --dry-run 2>&1)
case "$out" in
  *"[C0-CC] claude code"*) pass "and the caller's answer is used for that same note" ;;
  *) fail "and the caller's answer is used for that same note" "got: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-140)" ;;
esac

echo
echo "=== the notice file and the wake, with a throwaway session named in the note"
if [ -z "$LT" ]; then
  skip "a notice is written for the session the note names"
  skip "a stopped session is woken with --by human:nelson"
  skip "the log line names the note and the verb"
else
  lt_name=$(claude agents --json --all 2>/dev/null | jq -r --arg i "$LT" '.[] | select(.id == $i or .sessionId == $i) | .name' | head -n 1)
  lt_sid=$(claude agents --json --all 2>/dev/null | jq -r --arg i "$LT" '.[] | select(.id == $i or .sessionId == $i) | .sessionId' | head -n 1)
  if [ -z "$lt_name" ]; then
    skip "a notice is written for the session the note names" "the throwaway $LT is not in the listing"
    skip "a stopped session is woken with --by human:nelson" "the throwaway $LT is not in the listing"
    skip "the log line names the note and the verb" "the throwaway $LT is not in the listing"
  else
    n1=$(note addressed "$lt_name")
    "$NOTIFY" --note "$n1" --event verified --at 2026-09-27T14:05 --words "looks right to me" >/dev/null 2>&1
    if [ -s "$NOTIFY_NOTICES_DIR/$lt_sid.md" ]; then pass "a notice is written for the session the note names"
    else fail "a notice is written for the session the note names" "no file at $NOTIFY_NOTICES_DIR/$lt_sid.md"; fi
    if grep -q 'was verified at 2026-09-27T14:05: looks right to me' "$NOTIFY_NOTICES_DIR/$lt_sid.md" 2>/dev/null; then
      pass "the notice carries the event, the stamp and his words"
    else fail "the notice carries the event, the stamp and his words" "$(head -1 "$NOTIFY_NOTICES_DIR/$lt_sid.md" 2>/dev/null)"; fi
    # THE BRANCH IS DECIDED BY THE LISTING, AND EACH ONE IS ASSERTED. This case used to pass whichever way
    # it went — a wake call passed under one label and no wake call passed under another — which is a case
    # that cannot fail and therefore measures nothing. What the notifier promises is narrower and testable:
    # a RUNNING session is never woken, because its next turn reads the notice; a STOPPED one is woken, with
    # `--by human:nelson` and its FULL sessionId. To run the stopped branch: `claude stop <id>` and leave its
    # row in the listing (no `claude rm`), then run this again. The wake script here is a fake that records
    # its arguments, so neither branch wakes anything.
    lt_status=$(claude agents --json --all 2>/dev/null | jq -r --arg i "$LT" '.[] | select(.id == $i or .sessionId == $i) | (.status // "stopped")' | head -n 1)
    calls=$(cat "$TMP/wake-calls.log" 2>/dev/null || true)
    case "$lt_status" in
      busy|idle)
        if [ -z "$calls" ]; then pass "a running session is NOT woken (its next turn reads the notice)"
        else fail "a running session is NOT woken (its next turn reads the notice)" "the wake script was called: $calls"; fi
        skip "a stopped session is woken with --by human:nelson and its full sessionId" "the throwaway is $lt_status; stop it, keep its row, and run this again" ;;
      *)
        case "$calls" in
          *"--by human:nelson"*"$lt_sid"*|*"$lt_sid"*"--by human:nelson"*)
            pass "a stopped session is woken with --by human:nelson and its full sessionId" ;;
          *) fail "a stopped session is woken with --by human:nelson and its full sessionId" "the wake call was: ${calls:-(none)}" ;;
        esac
        skip "a running session is NOT woken (its next turn reads the notice)" "the throwaway is stopped; run this again while one is idle" ;;
    esac
    if grep -q "$n1" "$NOTIFY_FLEET_LOG" 2>/dev/null && grep -q 'verified verb' "$NOTIFY_FLEET_LOG" 2>/dev/null; then
      pass "the log line names the note and the verb"
    else fail "the log line names the note and the verb" "$(tail -2 "$NOTIFY_FLEET_LOG" 2>/dev/null | tr '\n' ' ')"; fi
  fi
fi

echo
echo "=== no session matches: the captain is told, and this script never dispatches"
n2=$(note unmatched "[L0-XX] a session that does not exist")
out=$("$NOTIFY" --note "$n2" --event answered --at 2026-09-27T14:05 --words "answered" --dry-run 2>&1)
case "$out" in
  *"[A0] rear admiral"*) pass "an unmapped path with no matching session goes to the rear admiral" ;;
  *) fail "an unmapped path with no matching session goes to the rear admiral" "$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-140)" ;;
esac
# NOT a grep for the word "dispatch": the log line legitimately says "the captain dispatches, this script
# does not", so matching the word failed on the script saying the right thing. What matters is that it never
# ISSUES one, so the test looks for the flags a dispatch would carry.
case "$out" in
  *--agent*|*"claude --bg"*) fail "it never dispatches" "the output carries dispatch flags" ;;
  *) pass "it never dispatches" ;;
esac

echo
echo
echo "=== the record says what HAPPENED, on a stub listing (the review of #63, findings 1, 3, 6, 7 and 8)"
# A STUB `claude` ON PATH. Everything above needs a live throwaway only because the listing comes from
# `claude agents --json --all`, and that is the one thing the battery cannot fake — until it fakes the CLI
# itself. A stub lets the cases the reviewer named actually run: a captain that IS in the listing, a captain
# that is NOT, a row whose sessionId is null, and a name that matches twice. It does not replace the live
# section above, which is the only proof that the real CLI's JSON parses; it covers the branches no fixture
# could reach. Nothing here dispatches, wakes or stops anything: the wake script is still the recorder.
STUBBIN="$TMP/stubbin"; mkdir -p "$STUBBIN"
stub_listing() {  # stub_listing <json>  — what the fake `claude agents --json --all` will print
  printf '%s' "$1" > "$TMP/listing.json"
  cat > "$STUBBIN/claude" <<'STUB'
#!/usr/bin/env bash
# [test artifact — safe to delete] a fake `claude` that only answers `agents --json --all`.
case "$*" in
  *agents*) cat "$(dirname "$0")/../listing.json" ;;
  *) exit 1 ;;
esac
STUB
  chmod +x "$STUBBIN/claude"
}
run_stubbed() {  # run_stubbed <note> [extra args...] — the notifier against the stub listing, for real
  note_path="$1"; shift
  PATH="$STUBBIN:$PATH" "$NOTIFY" --note "$note_path" --event verified --at 2026-09-27T14:05 --words "looks right to me" "$@" 2>&1
}
# THE LAST ENTRY, not the last N lines. `tail -n 8` spans two entries whenever one is six lines long, so a
# `not_in_log` assertion could read the PREVIOUS entry's words and fail on a sentence this case never wrote —
# which is exactly what happened the first time a live fixture ran before these stubbed cases. The window is
# the entry: everything after the newest `## ` heading.
log_tail() { awk '/^## /{buf=$0; next} {buf=buf" "$0} END{print buf}' "$NOTIFY_FLEET_LOG" 2>/dev/null; }
in_log() {  # in_log <label> <text that must be in the last entry>
  case "$(log_tail)" in
    *"$2"*) pass "$1" ;;
    *) fail "$1" "the entry says: $(log_tail | cut -c1-200)" ;;
  esac
}
not_in_log() {  # not_in_log <label> <text that must NOT be in the last entry>
  case "$(log_tail)" in
    *"$2"*) fail "$1" "the entry says: $(log_tail | cut -c1-200)" ;;
    *) pass "$1" ;;
  esac
}

SID_A="aaaaaaaa-1111-2222-3333-444444444444"
SID_B="bbbbbbbb-1111-2222-3333-444444444444"
CAPSID="cccccccc-1111-2222-3333-444444444444"
FLOATSID="dddddddd-1111-2222-3333-444444444444"

# A RUNNING SESSION IS NOT SAID TO HAVE BEEN WOKEN. This is finding 1's common case: the old script logged
# "which was idle, woken by the verified verb" for every live target, because the wake function returned 0
# both for "already running" and for "woken".
stub_listing "[{\"id\":\"aaa1\",\"sessionId\":\"$SID_A\",\"name\":\"[L0-CC] running one\",\"status\":\"idle\"}]"
n_run=$(note running_target "[L0-CC] running one")
run_stubbed "$n_run" >/dev/null
in_log     "a running target: the record says it reads it on its next turn" "reads it on its next turn"
not_in_log "a running target: the record does NOT claim a wake"            "and it was woken"
if [ -s "$NOTIFY_NOTICES_DIR/$SID_A.md" ]; then pass "a running target: the notice itself was written"
else fail "a running target: the notice itself was written" "no file for $SID_A"; fi

# A STOPPED SESSION IS WOKEN, and the record says so with the word that means it.
stub_listing "[{\"id\":\"aaa2\",\"sessionId\":\"$SID_B\",\"name\":\"[L0-CC] stopped one\",\"status\":null}]"
n_stop=$(note stopped_target "[L0-CC] stopped one")
run_stubbed "$n_stop" >/dev/null
in_log "a stopped target: the record says it was woken as human:nelson" "woken by this script as \`human:nelson\`"
if grep -q -- "--by human:nelson" "$TMP/wake-calls.log" 2>/dev/null; then pass "a stopped target: the wake carried --by human:nelson"
else fail "a stopped target: the wake carried --by human:nelson" "calls: $(cat "$TMP/wake-calls.log" 2>/dev/null | tr '\n' ' ')"; fi

# A NOTICE THAT COULD NOT BE WRITTEN IS NOT REPORTED AS DELIVERED — finding 1's other half, which the
# reviewer proved with an unwritable notices directory. The failure goes to stderr, which the real caller
# (the verb) discards, so the LOG is the only place it can show up.
UNWRITABLE="$TMP/unwritable"
mkdir -p "$UNWRITABLE"; : > "$UNWRITABLE/blocker"; chmod 500 "$UNWRITABLE"
# THE LISTING MUST HOLD THIS CASE'S OWN TARGET. First time round it still held the previous case's row, so the
# run fell through to the captain road and this assertion read an entry about something else entirely — the
# harness measuring a different thing from the one in its label, which is the disease the batteries keep
# finding. Every stubbed case sets its own listing immediately before it runs.
stub_listing "[{\"id\":\"aaa1\",\"sessionId\":\"$SID_A\",\"name\":\"[L0-CC] running one\",\"status\":\"idle\"}]"
out=$(NOTIFY_NOTICES_DIR="$UNWRITABLE/notices" PATH="$STUBBIN:$PATH" "$NOTIFY" --note "$n_run" --event verified --at 2026-09-27T14:05 --words w 2>&1)
in_log "an unwritable notices dir: the record says NO NOTICE COULD BE WRITTEN" "NO NOTICE COULD BE WRITTEN"
chmod 700 "$UNWRITABLE"

# A NULL sessionId IS NOT A PATH. `@tsv` renders JSON null as an empty field, so the notice used to land at
# `<dir>/.md`, which the injecting hook never reads, and the record said it had gone to the session.
stub_listing "[{\"id\":\"aaa3\",\"sessionId\":null,\"name\":\"[L0-CC] no sid\",\"status\":\"idle\"},{\"id\":\"cap1\",\"sessionId\":\"$CAPSID\",\"name\":\"[A0] rear admiral\",\"status\":\"idle\"}]"
n_null=$(note nullsid_target "[L0-CC] no sid")
run_stubbed "$n_null" >/dev/null
in_log "a null sessionId: the record names it as unusable" "sessionId is unusable"
if [ -e "$NOTIFY_NOTICES_DIR/.md" ]; then fail "a null sessionId: nothing is written to <dir>/.md" "the file exists"
else pass "a null sessionId: nothing is written to <dir>/.md"; fi
in_log "a null sessionId: the rear admiral is told instead" "[A0] rear admiral"

# A NAME THAT MATCHES TWICE is resolved, and the record SAYS a choice was made and names the rows.
stub_listing "[{\"id\":\"twin1\",\"sessionId\":\"$SID_A\",\"name\":\"[L0-CC] twice\",\"status\":\"idle\"},{\"id\":\"twin2\",\"sessionId\":\"$SID_B\",\"name\":\"[L0-CC] twice\",\"status\":\"idle\"}]"
n_twice=$(note twice_target "[L0-CC] twice")
run_stubbed "$n_twice" >/dev/null
in_log "a duplicate name: the record says two rows matched" "matched 2 rows"
in_log "a duplicate name: the record names both ids"        "twin1 twin2"

# THE NAMED CAPTAIN IS TOLD when no session matches, and told for real rather than in a dry run.
stub_listing "[{\"id\":\"cap2\",\"sessionId\":\"$CAPSID\",\"name\":\"[C0-CC] claude code\",\"status\":\"idle\"}]"
printf -- '---\ntype: Task\nsession: "[L0-CC] nobody home"\nstatus: verified\n---\n' > "$TMP/unmatched-note.md"
run_stubbed "$TMP/unmatched-note.md" --captain "[C0-CC] claude code" >/dev/null
in_log "no match: the captain the caller named is told"   "[C0-CC] claude code"
in_log "no match: the record says who named it"          "named by the caller"
in_log "no match: the record says the captain dispatches" "the captain dispatches, this script does not"

# A VAULT-RELATIVE PATH IS FOUND UNDER THE VAULT ROOT — the 2026-10-01 bug: the Request revision verb passed
# `00-09 System/…/<note>.md`, the script ran from elsewhere, and it died with "no note at". Run from a directory
# where the relative path does NOT exist, so only the vault-root road can find it.
export NOTIFY_VAULT_DIR="$TMP/vault"
mkdir -p "$NOTIFY_VAULT_DIR/00-09 System/01 Sub dir" "$TMP/elsewhere"
REL="00-09 System/01 Sub dir/vault relative.md"
printf -- '---\ntype: Task\nsession: "[L0-CC] running one"\nstatus: verified\n---\n' > "$NOTIFY_VAULT_DIR/$REL"
stub_listing "[{\"id\":\"aaa1\",\"sessionId\":\"$SID_A\",\"name\":\"[L0-CC] running one\",\"status\":\"idle\"}]"
: > "$NOTIFY_NOTICES_DIR/$SID_A.md"
out=$(cd "$TMP/elsewhere" && run_stubbed "$REL")
if [ -s "$NOTIFY_NOTICES_DIR/$SID_A.md" ]; then pass "a vault-relative path: the note is found and its filer told"
else fail "a vault-relative path: the note is found and its filer told" "$out"; fi

# A NOTE THAT CANNOT BE FOUND IS LOUD: the rear admiral gets a notice, not just a line on stderr.
stub_listing "[{\"id\":\"cap1\",\"sessionId\":\"$CAPSID\",\"name\":\"[A0] rear admiral\",\"status\":\"idle\"}]"
: > "$NOTIFY_NOTICES_DIR/$CAPSID.md"
out=$(cd "$TMP/elsewhere" && run_stubbed "00-09 System/no such note.md")
rc=$?
if [ "$rc" != 0 ]; then pass "a missing note: the script still fails"; else fail "a missing note: the script still fails" "exit 0"; fi
if grep -q 'no note at' "$NOTIFY_NOTICES_DIR/$CAPSID.md" 2>/dev/null; then pass "a missing note: the rear admiral gets a notice"
else fail "a missing note: the rear admiral gets a notice" "$out"; fi
unset NOTIFY_VAULT_DIR

# A CAPTAIN THAT IS NOT IN THE LISTING falls back to the floating default — finding 7. The old script logged
# "nobody was told" and never tried the fallback, although a captain with no row cannot be woken either.
stub_listing "[{\"id\":\"flo1\",\"sessionId\":\"$FLOATSID\",\"name\":\"[L0-FL] the floating one\",\"status\":\"idle\"}]"
out=$(PATH="$STUBBIN:$PATH" "$NOTIFY" --note "$TMP/unmatched-note.md" --event verified --at 2026-09-27T14:05 --words w --captain "[C0-CC] claude code" --floating-default "[L0-FL] the floating one" 2>&1)
in_log "an absent captain: it FELL BACK to the floating default" "FELL BACK to the floating default"
in_log "an absent captain: the fallback is logged as one"        "logged as a fallback, per the ruling"
if [ -s "$NOTIFY_NOTICES_DIR/$FLOATSID.md" ]; then pass "an absent captain: the floating default got the notice"
else fail "an absent captain: the floating default got the notice" "no file for $FLOATSID"; fi

# A RELATIVE NOTE PATH IS RESOLVED BEFORE ANYTHING READS IT — finding 6, and it still matters with the map
# gone: the RECORD carries the path, and a relative path in the fleet log means nothing to a session reading it
# from somewhere else. The verb's working directory is the vault root often enough for this to be ordinary.
stub_listing "[{\"id\":\"cap3\",\"sessionId\":\"$CAPSID\",\"name\":\"[C0-OB] obsidian\",\"status\":\"idle\"}]"
mkdir -p "$TMP/vault/00-09 System/01 System architecture"
printf -- '---\ntype: Task\nstatus: verified\n---\n' > "$TMP/vault/00-09 System/01 System architecture/rel.md"
out=$(cd "$TMP/vault" && PATH="$STUBBIN:$PATH" "$NOTIFY" --note "00-09 System/01 System architecture/rel.md" --event verified --at 2026-09-27T14:05 --words w --captain "[C0-OB] obsidian" 2>&1)
in_log "a relative note path is recorded as an absolute one" "$TMP/vault/00-09 System/01 System architecture/rel.md"
in_log "and the named captain is still the one told"         "[C0-OB] obsidian"

# THE THREE CASES THAT USED TO LIVE HERE tested the map's own arms — a repo slot, the dotfiles repo, and a
# folder merely NAMED `dotfiles` that the map used to claim. They went with the map, to the vault, where the
# policy that decides those is written down. Nothing in this script reads a path for a captain any more, and
# the pair of cases up in the interface section is what holds that.

# `--words` HAS A DEFAULT, and it is visible rather than empty.
# A DRY RUN CANNOT SHOW THIS. `log_line` prints only its sentence on a dry run, and his words live in the
# entry's own body, so the first version of this case asserted on output that never carries the value. It runs
# for real, against its own listing, and reads the entry.
stub_listing "[{\"id\":\"aaa1\",\"sessionId\":\"$SID_A\",\"name\":\"[L0-CC] running one\",\"status\":\"idle\"}]"
PATH="$STUBBIN:$PATH" "$NOTIFY" --note "$n_run" --event answered --at 2026-09-27T14:05 >/dev/null 2>&1
in_log "an omitted --words becomes '(no words given)'" "(no words given)"

# THE LOG ENTRY IS A RULING, which is one of the three kinds `claude/CLAUDE.md` allows in that file. It said
# "record" for a day, which is not one of them.
in_log "the entry is headed as a ruling" "— ruling"

echo "=== the injecting hook: it delivers, it clears, and it never blocks a turn"
hook_with() {  # hook_with <json>; prints stdout, and the exit code on the last line
  printf '%s' "$1" | "$INJECT" 2>/dev/null; printf 'rc=%s' "$?"
}
sid=deadbeef-0000-0000-0000-000000000000
printf -- '- your item `x.md` was verified at 2026-09-27T14:05: fine by me\n' > "$NOTIFY_NOTICES_DIR/$sid.md"
out=$(hook_with "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$sid\"}")
case "$out" in *"fine by me"*) pass "a waiting notice is injected on UserPromptSubmit" ;; *) fail "a waiting notice is injected on UserPromptSubmit" "$out" ;; esac
case "$out" in *rc=0*) pass "it exits 0 when it injects" ;; *) fail "it exits 0 when it injects" "$out" ;; esac
if [ -e "$NOTIFY_NOTICES_DIR/$sid.md" ]; then fail "the notice is cleared after it is injected" "the file is still there"; else pass "the notice is cleared after it is injected"; fi
out=$(hook_with "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$sid\"}")
case "$out" in rc=0) pass "a second turn injects nothing and still exits 0" ;; *) fail "a second turn injects nothing and still exits 0" "$out" ;; esac

printf -- '- a notice for a resume\n' > "$NOTIFY_NOTICES_DIR/$sid.md"
out=$(hook_with "{\"hook_event_name\":\"SessionStart\",\"source\":\"resume\",\"session_id\":\"$sid\"}")
case "$out" in *"a notice for a resume"*) pass "a resume injects the notice" ;; *) fail "a resume injects the notice" "$out" ;; esac
printf -- '- a notice that must NOT be injected on a fresh start\n' > "$NOTIFY_NOTICES_DIR/$sid.md"
out=$(hook_with "{\"hook_event_name\":\"SessionStart\",\"source\":\"startup\",\"session_id\":\"$sid\"}")
case "$out" in rc=0) pass "a fresh start injects nothing (and the notice is kept)" ;; *) fail "a fresh start injects nothing" "$out" ;; esac
if [ -s "$NOTIFY_NOTICES_DIR/$sid.md" ]; then pass "the notice survives a fresh start"; else fail "the notice survives a fresh start" "it was cleared"; fi

echo
# A SESSION ID IS NOT A PATH — finding 5. The hook DELETES what it prints, so a `../` in `session_id` printed
# an arbitrary file into the model's context and then removed it. Proven both ways: the victim survives, and
# nothing is printed.
VICTIM="$TMP/victim.md"
printf 'SECRET CONTENT\n' > "$VICTIM"
out=$(printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"../victim"}' | "$INJECT" 2>&1; printf 'rc=%s' "$?")
case "$out" in
  *"SECRET CONTENT"*) fail "a traversal session_id prints nothing" "it printed the file" ;;
  *) pass "a traversal session_id prints nothing" ;;
esac
if [ -f "$VICTIM" ]; then pass "a traversal session_id deletes nothing"; else fail "a traversal session_id deletes nothing" "the file is gone"; fi
for bad_sid in "" "short" "../victim" "aaaaaaaa-1111-2222-3333-44444444444" "gggggggg-1111-2222-3333-444444444444" "aaaaaaaa/1111/2222/3333/444444444444"; do
  printf '%s' "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$bad_sid\"}" | "$INJECT" >/dev/null 2>&1
  rc=$?
  if [ "$rc" = 0 ]; then pass "a malformed session_id ('$bad_sid') exits 0 and does nothing"
  else fail "a malformed session_id ('$bad_sid') exits 0 and does nothing" "rc=$rc"; fi
done

# A NOTICE IS NEVER LOST IN THE PRINT WINDOW — finding 4. The window itself is closed by construction: the
# file is MOVED ASIDE before it is read, so an append during the print lands in a fresh file that the next
# turn picks up. What can be tested from outside is the crash half of that design: a `.reading.<pid>` file
# left behind by a process that died mid-print must be delivered by the next run, not orphaned forever.
SID_STALE="eeeeeeee-1111-2222-3333-444444444444"
printf -- '- an older ruling nobody printed yet\n' > "$NOTIFY_NOTICES_DIR/$SID_STALE.md.reading.99999"
printf -- '- the ruling that arrived after it\n'  > "$NOTIFY_NOTICES_DIR/$SID_STALE.md"
out=$(printf '%s' "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$SID_STALE\"}" | "$INJECT" 2>&1)
case "$out" in
  *"an older ruling nobody printed yet"*) pass "a notice left behind by a dead run is delivered next turn" ;;
  *) fail "a notice left behind by a dead run is delivered next turn" "got: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-140)" ;;
esac
case "$out" in
  *"the ruling that arrived after it"*) pass "and the current notice is delivered with it, in order" ;;
  *) fail "and the current notice is delivered with it, in order" "got: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-140)" ;;
esac
if [ -e "$NOTIFY_NOTICES_DIR/$SID_STALE.md.reading.99999" ]; then fail "both are cleared afterwards" "the stale file is still there"
elif [ -e "$NOTIFY_NOTICES_DIR/$SID_STALE.md" ]; then fail "both are cleared afterwards" "the notice is still there"
else pass "both are cleared afterwards"; fi

echo "=== the hook fails OPEN on everything, because it must never block a turn"
for bad in '' 'not json' '{}' '{"hook_event_name":"UserPromptSubmit"}' '{"session_id":"x"}' \
           '{"hook_event_name":"PreToolUse","session_id":"'"$sid"'"}' '[1,2,3]'; do
  out=$(hook_with "$bad")
  case "$out" in *rc=0*) pass "fails open on: ${bad:-(empty)}" ;; *) fail "fails open on: ${bad:-(empty)}" "$out" ;; esac
done
chmod 000 "$NOTIFY_NOTICES_DIR/$sid.md" 2>/dev/null || true
out=$(hook_with "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$sid\"}")
case "$out" in *rc=0*) pass "fails open on an unreadable notice" ;; *) fail "fails open on an unreadable notice" "$out" ;; esac
chmod 644 "$NOTIFY_NOTICES_DIR/$sid.md" 2>/dev/null || true

printf '\n%s cases, %s failed, %s skipped\n' "$n" "$fails" "$skips"
[ "$fails" = 0 ] || exit 1
