#!/usr/bin/env bash
# wake-session.sh on a session whose job record is gone: read from its notebook entry, gated like any wake, resumed with its flags from where its transcript is.
#
# NOTHING HERE READS THE MACHINE OR THE FLEET. HOME is a temp dir; `claude` and `sysctl` are stubs on PATH; the notebook roots, the projects root, the jobs dir, the log and the Pause note are temp paths. The stub `claude` prints $STUB_LISTING for `claude agents`, which LACKS the target's row; for `claude --bg …` it records "<the directory it ran in>|<its arguments>" in $STUB_CALLS, adds the resumed row to the listing, and prints the CLI's own "backgrounded · <id>" line; for `claude stop` it records "stop <id>".
#
# Run: bash claude/tests/wake-post-rm/post-rm.sh   (prints the check count; exits non-zero on any failure)
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
BIN="$HERE/../../bin"
n=0; fails=0
pass() { n=$((n + 1)); printf 'PASS  %s\n' "$1"; }
fail() { n=$((n + 1)); fails=$((fails + 1)); printf 'FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; }
eq()  { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "got '$2', want '$3'"; fi; }
has() { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "missing '$3' in: $(printf '%s' "$2" | head -c 400)" ;; esac; }
lacks() { case "$2" in *"$3"*) fail "$1" "present: '$3'" ;; *) pass "$1" ;; esac; }
command -v jq >/dev/null 2>&1 || { echo "STOP  jq is not installed, and the script needs it"; exit 1; }

T=$(mktemp -d "${TMPDIR:-/tmp}/wake-post-rm.XXXXXX") || exit 1
trap '/usr/bin/trash "$T" 2>/dev/null || true' EXIT
T=$(cd "$T" && pwd -P)
mkdir -p "$T/home/.claude/agents" "$T/stubbin" "$T/jobs" "$T/nb/2026-09" "$T/ar" "$T/projects" "$T/work" "$T/other"
for d in captain commander lieutenant-commander lieutenant; do : > "$T/home/.claude/agents/$d.md"; done
printf -- '---\npaused: false\n---\n' > "$T/pause.md"
cat > "$T/stubbin/sysctl" <<'EOF'
#!/bin/sh
cat "$STUB_LOAD"
EOF
cat > "$T/stubbin/claude" <<'EOF'
#!/bin/sh
case "$1" in
  agents) cat "$STUB_LISTING"; exit 0 ;;
  stop) printf 'stop %s\n' "$2" >> "$STUB_CALLS"; exit 0 ;;
esac
printf '%s|%s\n' "$PWD" "$*" >> "$STUB_CALLS"
sid="" name=""
while [ $# -gt 0 ]; do
  case "$1" in --resume) sid="$2"; shift 2 ;; --name) name="$2"; shift 2 ;; *) shift ;; esac
done
new=${STUB_NEW_ID:-$(printf '%s' "$sid" | cut -c1-8)}
out_sid=${STUB_OUT_SID:-$sid}
if [ -n "${STUB_EMPTY_SID:-}" ]; then
  # The row shows first with no sessionId, and it is filled in two seconds later.
  jq -c --arg i "$new" --arg n "$name" '. + [{"id":$i,"sessionId":"","name":$n,"pid":99999,"status":"idle"}]' "$STUB_LISTING" > "$STUB_LISTING.new" && mv "$STUB_LISTING.new" "$STUB_LISTING"
  ( sleep 2; jq -c --arg i "$new" --arg s "$out_sid" 'map(if .id == $i then .sessionId = $s else . end)' "$STUB_LISTING" > "$STUB_LISTING.new2" && mv "$STUB_LISTING.new2" "$STUB_LISTING" ) >/dev/null 2>&1 &
else
  jq -c --arg i "$new" --arg s "$out_sid" --arg n "$name" '. + [{"id":$i,"sessionId":$s,"name":$n,"pid":99999,"status":"idle"}]' "$STUB_LISTING" > "$STUB_LISTING.new" && mv "$STUB_LISTING.new" "$STUB_LISTING"
fi
[ -z "${STUB_COPY_NOTE:-}" ] || printf 'note: background session %s keeps its own saved options, so the flags you passed started a copy as %s.\n' "$(printf '%s' "$sid" | cut -c1-8)" "$new"
printf 'backgrounded \302\267 %s \302\267 %s\n' "$new" "$name"
EOF
chmod +x "$T/stubbin/sysctl" "$T/stubbin/claude"
export STUB_LOAD="$T/load" STUB_LISTING="$T/listing.json" STUB_CALLS="$T/calls"
printf '{ 1.00 2.00 2.00 }\n' > "$T/load"

ID=11111111-2222-3333-4444-555555555555
ID2=66666666-7777-8888-9999-000000000000
entry() {  # entry <file stem> <session name> <session-id> <agent> <cwd>
  printf -- '---\ntitle: %s\nsession: "%s"\nsession-id: "%s"\nstatus: archived/ended\nreports-to: "[C0-CC] claude code"\nagent: "%s"\ncwd: "%s"\n---\n\n[test artifact — safe to delete]\n' "$1" "$2" "$3" "$4" "$5" > "$T/nb/2026-09/$1.md"
}
enc() { printf '%s' "$1" | sed -E 's/[^A-Za-z0-9-]/-/g'; }
# Written long ago: a transcript written in the last two minutes reads as a session that may be running (section 9).
transcript() { mkdir -p "$T/projects/$(enc "$1")"; : > "$T/projects/$(enc "$1")/$2.jsonl"; touch -t 202601010000 "$T/projects/$(enc "$1")/$2.jsonl"; }
reset() {  # a listing with one unrelated row, and no calls; the target's row is never in it
  printf '[{"id":"aaaaaaaa","sessionId":"aaaaaaaa-0000-0000-0000-000000000000","name":"[L0-CC] someone else","status":"idle"}]\n' > "$T/listing.json"
  : > "$T/calls"; : > "$T/log.md"
}
wake() {  # wake <session> [by] [extra args…]: sets $out and $rc
  local s="$1" by="${2:-[C0-CC] claude code}"; shift; [ $# -gt 0 ] && shift
  out=$(HOME="$T/home" PATH="$T/stubbin:$PATH" bash "$BIN/wake-session.sh" --session "$s" --by "$by" --why "post-rm test" \
    --jobs-dir "$T/jobs" --log "$T/log.md" --pause-note "$T/pause.md" --notebook-dir "$T/nb" --archive-dir "$T/ar" --projects-dir "$T/projects" \
    --message "hello" "$@" 2>&1); rc=$?
}

entry "Agent session 2026-09-30T0100" "[L0-CC] gone" "$ID" lieutenant "$T/work"
transcript "$T/work" "$ID"

echo "=== 1. found at the recorded cwd: resumed with its flags"
reset; wake "$ID"
eq  "the wake succeeds" "$rc" 0
ENDED="your entry $T/nb/2026-09/Agent session 2026-09-30T0100.md was ended while you were stopped; open a new entry that points at it, and do not reopen it"
eq  "the exact argv, run in the recorded cwd, with the ended-entry line" "$(head -n 1 "$T/calls")" "$T/work|--bg --resume $ID --agent lieutenant --name [L0-CC] gone hello $ENDED"
has "one log entry says the job record was gone" "$(cat "$T/log.md")" "whose job record was gone"
eq  "exactly one log entry" "$(grep -c '^## ' "$T/log.md")" 1
has "the done line names the same sessionId" "$out" "running again under the same sessionId"

echo
echo "=== 2. agent: claude passes no --agent"
entry "Agent session 2026-09-30T0200" "[L0-CC] plain" "$ID2" claude "$T/work"
transcript "$T/work" "$ID2"
reset; wake "$ID2"
eq  "the wake succeeds" "$rc" 0
case "$(head -n 1 "$T/calls")" in "$T/work|--bg --resume $ID2 --name [L0-CC] plain hello"*) pass "no --agent in the argv" ;; *) fail "no --agent in the argv" "got $(head -n 1 "$T/calls")" ;; esac

echo
echo "=== 3. the transcript elsewhere, nowhere, or in two places: refused, nothing run"
/usr/bin/trash "$T/projects/$(enc "$T/work")/$ID.jsonl"; transcript "$T/other" "$ID"
reset; wake "$ID"
has "elsewhere: refused, naming where it is" "$out" "is not under the recorded cwd"
has "elsewhere: and naming the recorded cwd" "$out" "'$T/work'"
eq  "elsewhere: nothing was run" "$(cat "$T/calls")" ""
transcript "$T/elsewhere-two" "$ID"
reset; wake "$ID"
has "two places: refused" "$out" "more than one place"
eq  "two places: nothing was run" "$(cat "$T/calls")" ""
/usr/bin/trash "$T/projects/$(enc "$T/other")/$ID.jsonl" "$T/projects/$(enc "$T/elsewhere-two")/$ID.jsonl"
reset; wake "$ID"
has "none: refused, since a resume would start a new session" "$out" "no transcript of $ID"
eq  "none: nothing was run" "$(cat "$T/calls")" ""
transcript "$T/work" "$ID"

echo
echo "=== 4. a short id with no row"
reset; wake "11111111"
has "a short id is refused and told to use the full id" "$out" "FULL 36-character sessionId"
eq  "nothing was run" "$(cat "$T/calls")" ""

echo
echo "=== 5. the dry run prints the exact command and runs nothing"
reset; wake "$ID" "[C0-CC] claude code" --dry-run
eq  "the dry run exits 0" "$rc" 0
has "it prints the command it would run, quoted" "$out" "(cd $(printf '%q' "$T/work") && claude --bg --resume $ID --agent lieutenant --name $(printf '%q' '[L0-CC] gone')"
has "and says nothing was touched" "$out" "dry run: nothing touched"
eq  "nothing was run" "$(cat "$T/calls")" ""
eq  "nothing was logged" "$(cat "$T/log.md")" ""

echo
echo "=== 6. every gate refuses before any resume"
printf '{ 1.00 9.00 2.00 }\n' > "$T/load"
reset; wake "$ID"
has "the fleet gate" "$out" "held by the fleet gate"
eq  "the fleet gate: nothing was run" "$(cat "$T/calls")" ""
printf '{ 1.00 2.00 2.00 }\n' > "$T/load"
reset; wake "$ID" "[C0-OB] obsidian"
has "the reporting line (a caller outside it)" "$out" "not in [C0-OB] obsidian's reporting line"
eq  "the reporting line: nothing was run" "$(cat "$T/calls")" ""
reset; wake "$ID" "[L0-CC] peer"
has "the rank line (a peer may not wake a peer)" "$out" "may only wake a session below its own rank"
printf -- '---\npaused: true\n---\n' > "$T/pause.md"
reset; wake "$ID"
if [ "$rc" != 0 ] && [ -z "$(cat "$T/calls")" ]; then pass "the pause gate refuses, and nothing was run"; else fail "the pause gate refuses, and nothing was run" "rc $rc, calls: $(cat "$T/calls")"; fi
printf -- '---\npaused: false\n---\n' > "$T/pause.md"
entry "Agent session 2026-09-30T0300" "[L0-DV] guarded" "22222222-3333-4444-5555-666666666666" lieutenant "$T/work"
transcript "$T/work" "22222222-3333-4444-5555-666666666666"
reset; wake "22222222-3333-4444-5555-666666666666"
has "the DV guard" "$out" "ship DV is guarded"
eq  "the DV guard: nothing was run" "$(cat "$T/calls")" ""

echo
echo "=== 7. a resume that comes back as another conversation, or as a copy, is stopped and refused"
reset; out=$(STUB_OUT_SID=99999999-0000-0000-0000-000000000000 HOME="$T/home" PATH="$T/stubbin:$PATH" bash "$BIN/wake-session.sh" --session "$ID" --by "[C0-CC] claude code" --why x \
  --jobs-dir "$T/jobs" --log "$T/log.md" --pause-note "$T/pause.md" --notebook-dir "$T/nb" --archive-dir "$T/ar" --projects-dir "$T/projects" --message hello 2>&1); rc=$?
has "another sessionId under the new id: refused" "$out" "a different conversation"
has "and that session is stopped" "$(cat "$T/calls")" "stop 11111111"
eq  "and nothing was logged" "$(cat "$T/log.md")" ""
reset; out=$(STUB_COPY_NOTE=1 STUB_NEW_ID=cccccccc HOME="$T/home" PATH="$T/stubbin:$PATH" bash "$BIN/wake-session.sh" --session "$ID" --by "[C0-CC] claude code" --why x \
  --jobs-dir "$T/jobs" --log "$T/log.md" --pause-note "$T/pause.md" --notebook-dir "$T/nb" --archive-dir "$T/ar" --projects-dir "$T/projects" --message hello 2>&1); rc=$?
has "a copy note: refused" "$out" "started a copy (cccccccc)"
has "and the copy is stopped" "$(cat "$T/calls")" "stop cccccccc"

echo
echo "=== 8. a record that cannot carry the resume is refused"
entry "Agent session 2026-09-30T0400" "[L0-CC] nocwd" "33333333-4444-5555-6666-777777777777" lieutenant ""
reset; wake "33333333-4444-5555-6666-777777777777"
has "an entry with no cwd is refused, naming the missing key" "$out" "lacks: cwd"
reset; wake "44444444-5555-6666-7777-888888888888"
has "a full id with no row and no entry is refused" "$out" "no notebook entry carries session-id"
entry "Agent session 2026-09-30T0500" "[C1-CC] wrongrank" "55555555-6666-7777-8888-999999999999" lieutenant "$T/work"
reset; wake "55555555-6666-7777-8888-999999999999"
has "an entry whose agent disagrees with its name's rank is refused" "$out" "disagrees with itself"
eq  "none of these ran anything" "$(cat "$T/calls")" ""

echo
echo "=== 9. what the review of #108 found"
# A transcript written just now: the session may be running with no job row, so it is not resumed.
touch "$T/projects/$(enc "$T/work")/$ID.jsonl"
reset; wake "$ID"
eq  "a transcript written just now: exit 3, not resumed" "$rc" 3
eq  "and nothing was run" "$(cat "$T/calls")" ""
touch -t 202601010000 "$T/projects/$(enc "$T/work")/$ID.jsonl"
# A copy at the recorded cwd AND another elsewhere is two places, not "here".
transcript "$T/other" "$ID"
reset; wake "$ID"
has "a copy at the cwd plus one elsewhere: refused as two places" "$out" "more than one place"
eq  "and nothing was run" "$(cat "$T/calls")" ""
/usr/bin/trash "$T/projects/$(enc "$T/other")/$ID.jsonl"
# The recorded cwd is gone.
entry "Agent session 2026-09-30T0600" "[L0-CC] gonecwd" "77777777-8888-9999-0000-111111111111" lieutenant "$T/removed-worktree"
transcript "$T/removed-worktree" "77777777-8888-9999-0000-111111111111"
reset; wake "77777777-8888-9999-0000-111111111111"
has "a recorded cwd that no longer exists is refused, saying so" "$out" "no longer exists"
# A row that shows first with no sessionId is waited for, not stopped as another conversation.
reset; out=$(STUB_EMPTY_SID=1 HOME="$T/home" PATH="$T/stubbin:$PATH" bash "$BIN/wake-session.sh" --session "$ID" --by "[C0-CC] claude code" --why x \
  --jobs-dir "$T/jobs" --log "$T/log.md" --pause-note "$T/pause.md" --notebook-dir "$T/nb" --archive-dir "$T/ar" --projects-dir "$T/projects" --message hello 2>&1); rc=$?
eq  "an empty sessionId at first: waited for, the wake succeeds" "$rc" 0
lacks "and nothing was stopped" "$(cat "$T/calls")" "stop "
# The listing lost the row but the job record is still there: flagless, never with flags.
mkdir -p "$T/jobs/11111111"; printf '{"template":"lieutenant"}\n' > "$T/jobs/11111111/state.json"
reset; wake "$ID"
eq  "a job record that still exists: the wake succeeds" "$rc" 0
case "$(head -n 1 "$T/calls")" in "$T/work|--bg --resume $ID hello"*) pass "and it resumes FLAGLESS, from the entry's cwd" ;; *) fail "and it resumes FLAGLESS, from the entry's cwd" "got $(head -n 1 "$T/calls")" ;; esac
has "and it says why" "$out" "its job record is still at"
/usr/bin/trash "$T/jobs/11111111"

EXPECTED=48
[ "$n" = "$EXPECTED" ] || { fails=$((fails + 1)); echo "FAIL  the check count is $n, expected $EXPECTED"; }
printf '\n%s checks (expected %s), %s failed\n' "$n" "$EXPECTED" "$fails"
[ "$fails" = 0 ] || exit 1
