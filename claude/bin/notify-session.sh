#!/usr/bin/env bash
# notify-session.sh — tell a session that its queue item was verified or answered, and if nothing matches,
# tell the captain of the ship the note belongs to.
#
# WHAT NELSON ASKED FOR, 2026-09-27, through `[A0] rear admiral`: "get it built but we probably need a
# default session or a fallback for spinning up sessions when a match can't be found". The machine: when he
# verifies a queue note or answers a Decision, the verb tells the session whose `session:` key the note
# carries, so the work resumes without him carrying the message; and when no session matches, something is
# told instead of the ruling sitting unread.
#
# WHO CALLS IT: the Verify and Answer verbs, at the END of their write path, on the obsidian ship. One
# shell-out, argv and never a shell string, detached, and its exit status ignored — a notifier that can
# fail a verb is worse than a notifier that fails:
#
#     notify-session.sh --note <path> --event verified|answered --at <stamp> --words <his text>
#
# `--at` IS REQUIRED AND NEVER INVENTED. The verb takes the stamp at write time, which is the only moment
# that knows when the act happened; a missing or unparseable `--at` is a REFUSAL, not a default, because a
# notice that says the wrong time about the admiral's own ruling is worse than one that never arrives. This
# script's own log line is stamped from `date`, which is a different fact: when the notice was delivered.
#
# WHAT IT DOES, in order:
#   1. reads `session:` from the note's frontmatter, through the shared reader in `claude/lib/pause-flag.sh`;
#   2. resolves that display NAME to a live sessionId through `claude agents --json --all`;
#   3. writes a notice file at `~/.claude/notices/<sessionId>.md` — appended, never overwritten, because two
#      rulings can land before a session next runs;
#   4. if that session is STOPPED, wakes it with `--by "human:nelson"`;
#   5. if no session matches the name, notifies the CAPTAIN of the ship the note belongs to, the same way,
#      and the captain dispatches — this script NEVER dispatches;
#   6. writes one cross-session log line per act, in claim form.
#
# TWO CALLS WERE RULED BEFORE IT WAS BUILT, both in the queue note "Rule the two calls in the verified-item
# notifier before it is built", ruled 2026-09-27 by `[A0] rear admiral` inside Nelson's "get it built":
#
#   CALL 1 — may a verb wake a session with no rank behind it? YES, as `human:nelson`, "because the click is
#   his and the alternative is a ruling that sits unread". That is one arm in `rank_of_caller` in
#   `claude/bin/_fleet-ranks.sh`, at rank -2, above the rear admiral. The ruling states its own limit, and so
#   does this script: `--by` IS NOT AUTHENTICATED. It is a string a caller supplies, so a session that chose
#   to could pass it, exactly as one could already write a stamp or a name it did not earn. What it buys is
#   that the wake is ATTRIBUTED AND LOGGED in his name — the log line names the note and the verb — so a
#   wake nobody can account for is visible. What it cannot do is stop a session that decides to lie.
#
#   CALL 2 — does the fallback dispatch, or does the captain? THE CAPTAIN. "The script notifies the captain
#   (a notice on its file, plus a wake if it is stopped) with the note path and his words, and the captain
#   dispatches under the load gate with a rank answerable." Dispatching here would put a session on the
#   fleet with no rank having decided to, which is the one thing rule 19 exists to prevent, and no rank would
#   have checked the ruling is even executable. If the captain is itself stopped AND CANNOT BE WOKEN, this
#   falls back to the floating default session and LOGS THAT IT DID.
#
# THE SHIP MAP, from the note's path, verbatim from the ruling:
#   * `00-09 System/**`                              → `[C0-OB] obsidian`
#   * except `03 Agents/03.11`, `03.12`, `03.17`, `03.18` and the dotfiles repo → `[C0-CC] claude code`
#   * a repo slot under `07 Repositories`             → that repository's ship, floating if none
#   * anything else                                  → `[A0] rear admiral`
# NO SHIP INFERABLE MEANS THE REAR ADMIRAL, not the floating default. The floating default is only the
# fallback for a ship's captain that is stopped and cannot be woken, and that is the ruling's own wording
# rather than a summary of it.
#
# WHAT IT NEVER DOES: dispatch a session; invoke an accept verb (it is told that one happened, which is the
# opposite); write to the vault except the one cross-session log line; or fail a verb. `--dry-run` prints
# every act it would take and touches nothing, which is how its battery runs.
#
# Works under /bin/bash 3.2 (macOS). Needs jq and the claude CLI.

set -u
set -o pipefail

PROG=notify-session
FLEET_LOG="${NOTIFY_FLEET_LOG:-$HOME/obsidian/00-09 System/03 Agents/03.16 Cross-session log/CROSS-SESSION.md}"
NOTICES_DIR="${NOTIFY_NOTICES_DIR:-$HOME/.claude/notices}"
FLOATING_DEFAULT="${NOTIFY_FLOATING_DEFAULT:-[L0-FL] dotfiles}"
REAR_ADMIRAL="[A0] rear admiral"

script_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || script_dir=""
WAKE="${NOTIFY_WAKE_SCRIPT:-$script_dir/wake-session.sh}"

die() { printf '%s: %s\n' "$PROG" "$*" >&2; exit 2; }

note="" event="" at="" words="" dry_run=0
while [ $# -gt 0 ]; do
  case "$1" in
    --note)    [ $# -ge 2 ] || die "--note needs a value";  note="$2"; shift 2 ;;
    --event)   [ $# -ge 2 ] || die "--event needs a value"; event="$2"; shift 2 ;;
    --at)      [ $# -ge 2 ] || die "--at needs a value";    at="$2"; shift 2 ;;
    --words)   [ $# -ge 2 ] || die "--words needs a value"; words="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) sed -n '2,/^set -u$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument '$1'" ;;
  esac
done

[ -n "$note" ]  || die "--note is required: the path of the queue note that was $event"
[ -n "$event" ] || die "--event is required: verified or answered"
case "$event" in
  verified|answered) ;;
  *) die "--event must be 'verified' or 'answered', got '$event'" ;;
esac
# `--at` is the verb's own stamp, taken at write time. Refused rather than defaulted: see the header.
[ -n "$at" ] || die "--at is required and is never invented here; the verb takes the stamp at write time"
case "$at" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]*) ;;
  *) die "--at must be an ISO stamp like 2026-09-27T14:05 (got '$at'); a wrong time on his ruling is worse than no notice" ;;
esac
[ -n "$words" ] || words="(no words given)"

# --- the note's own session ------------------------------------------------------------------------
FLAG_LIB="$script_dir/../lib/pause-flag.sh"
[ -r "$FLAG_LIB" ] || die "the frontmatter reader is missing or unreadable at $FLAG_LIB"
bash -n "$FLAG_LIB" 2>/dev/null || die "the frontmatter reader at $FLAG_LIB does not parse; refusing rather than guessing at a note's session"
# shellcheck source=../lib/pause-flag.sh
. "$FLAG_LIB" || die "the frontmatter reader at $FLAG_LIB could not be sourced"
command -v read_frontmatter >/dev/null 2>&1 || die "the frontmatter reader parsed but defined nothing; refusing"

[ -e "$note" ] || die "no note at '$note'"
read_frontmatter "$note"
[ "$flag_state" = "read" ] || die "the note at '$note' has no readable frontmatter (${flag_reason:-$flag_state}), so it names no session"
target_name=$(fm_value session)

# --- the ship map ----------------------------------------------------------------------------------
# From the note's PATH, exactly as the ruling lays it out. The order matters: the Claude Code exceptions are
# tested before the obsidian rule that would otherwise claim them.
ship_captain_of_note() {
  case "$1" in
    */03\ Agents/03.11*|*/03\ Agents/03.12*|*/03\ Agents/03.17*|*/03\ Agents/03.18*) printf '[C0-CC] claude code' ;;
    */repos/system/dotfiles/*|*/dotfiles/*)                                          printf '[C0-CC] claude code' ;;
    */07\ Repositories/*)                                                            printf '' ;;   # a repo slot: its own ship, resolved below
    */00-09\ System/*)                                                               printf '[C0-OB] obsidian' ;;
    *)                                                                              printf '' ;;
  esac
}
captain=$(ship_captain_of_note "$note")

# --- the session listing ---------------------------------------------------------------------------
command -v jq >/dev/null 2>&1     || die "jq is required"
command -v claude >/dev/null 2>&1 || die "the claude CLI is required"
listing=$(claude agents --json --all 2>/dev/null) || listing=""
[ -n "$listing" ] || die "the session listing could not be read, so no notice can be addressed"

# id, sessionId and status for a display name; the newest row wins if a name recurs.
row_for_name() {  # $1 = display name; prints "<id>\t<sessionId>\t<status>" or nothing
  printf '%s' "$listing" | jq -r --arg n "$1" '.[] | select(.name == $n) | [.id, .sessionId, (.status // "stopped")] | @tsv' 2>/dev/null | tail -n 1
}

log_line() {  # $1 = the sentence, appended in claim form with a stamp from `date`
  if [ "$dry_run" = 1 ]; then printf 'DRY RUN would log: %s\n' "$1"; return 0; fi
  {
    printf '\n## %s · %s (the %s verb, on Nelson'\''s click) — record\n\n' "$(date '+%Y-%m-%dT%H:%M')" "$PROG" "$event"
    printf '%s\n' "$1"
  } >> "$FLEET_LOG" 2>/dev/null || printf '%s: the log line could not be written to %s\n' "$PROG" "$FLEET_LOG" >&2
}

write_notice() {  # $1 = sessionId, $2 = who it is addressed to (for the text)
  if [ "$dry_run" = 1 ]; then printf 'DRY RUN would write a notice for %s (%s) at %s/%s.md\n' "$2" "$1" "$NOTICES_DIR" "$1"; return 0; fi
  mkdir -p "$NOTICES_DIR" 2>/dev/null || { printf '%s: could not make %s\n' "$PROG" "$NOTICES_DIR" >&2; return 1; }
  {
    printf -- '- your item `%s` was %s at %s: %s\n' "$note" "$event" "$at" "$words"
  } >> "$NOTICES_DIR/$1.md" || { printf '%s: could not write the notice for %s\n' "$PROG" "$1" >&2; return 1; }
  return 0
}

wake_if_stopped() {  # $1 = sessionId, $2 = status, $3 = display name; returns 0 if awake or woken
  case "$2" in
    busy|idle) return 0 ;;   # already running: the notice is read on its next turn
  esac
  if [ "$dry_run" = 1 ]; then printf 'DRY RUN would wake %s (%s) with --by "human:nelson"\n' "$3" "$1"; return 0; fi
  [ -x "$WAKE" ] || { printf '%s: no wake script at %s\n' "$PROG" "$WAKE" >&2; return 1; }
  "$WAKE" --session "$1" --by "human:nelson" \
    --why "the $event verb on Nelson's click: $note" \
    --message "Your queue item \`$note\` was $event at $at. His words: $words. Read the note in full, then carry on from it." \
    >/dev/null 2>&1
}

# --- 1. the session the note names -----------------------------------------------------------------
if [ -n "$target_name" ]; then
  row=$(row_for_name "$target_name")
  if [ -n "$row" ]; then
    sid=$(printf '%s' "$row" | cut -f2)
    status=$(printf '%s' "$row" | cut -f3)
    write_notice "$sid" "$target_name" || true
    if wake_if_stopped "$sid" "$status" "$target_name"; then
      log_line "\`$note\` was $event at $at; the notice went to \`$target_name\` ($sid), which was $status, woken by the $event verb on Nelson's click."
    else
      log_line "\`$note\` was $event at $at; the notice went to \`$target_name\` ($sid), which was $status and could NOT be woken — it will read the notice when it next runs."
    fi
    exit 0
  fi
fi

# --- 2. nothing matched: the ship's captain, or the rear admiral ------------------------------------
if [ -z "$captain" ]; then
  # No ship inferable from the path — the ruling sends this to the rear admiral, NOT to the floating
  # default. The floating default is only the fallback for a captain that cannot be woken, below.
  captain="$REAR_ADMIRAL"
  why_captain="no ship could be inferred from the note's path"
else
  why_captain="the ship map"
fi

crow=$(row_for_name "$captain")
if [ -n "$crow" ]; then
  csid=$(printf '%s' "$crow" | cut -f2)
  cstatus=$(printf '%s' "$crow" | cut -f3)
  write_notice "$csid" "$captain" || true
  if wake_if_stopped "$csid" "$cstatus" "$captain"; then
    log_line "\`$note\` was $event at $at; no session matched \`${target_name:-(the note names none)}\`, so the notice went to \`$captain\` ($why_captain), which was $cstatus — the captain dispatches, this script does not."
    exit 0
  fi
  # The captain is stopped and could not be woken: the ruling's own fallback, and it must be logged AS one.
  frow=$(row_for_name "$FLOATING_DEFAULT")
  if [ -n "$frow" ]; then
    fsid=$(printf '%s' "$frow" | cut -f2)
    fstatus=$(printf '%s' "$frow" | cut -f3)
    write_notice "$fsid" "$FLOATING_DEFAULT" || true
    wake_if_stopped "$fsid" "$fstatus" "$FLOATING_DEFAULT" || true
    log_line "\`$note\` was $event at $at; no session matched, \`$captain\` is stopped and could NOT be woken, so this FELL BACK to the floating default \`$FLOATING_DEFAULT\` ($fsid) — logged as a fallback, per the ruling."
    exit 0
  fi
  log_line "\`$note\` was $event at $at; no session matched, \`$captain\` could not be woken, and the floating default \`$FLOATING_DEFAULT\` is not in the listing either — NOBODY was told, and this line is the only record."
  exit 0
fi

log_line "\`$note\` was $event at $at; no session matched \`${target_name:-(the note names none)}\` and \`$captain\` is not in the listing, so no notice could be addressed — this line is the only record."
exit 0
