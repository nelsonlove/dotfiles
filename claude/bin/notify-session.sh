#!/usr/bin/env bash
# notify-session.sh — tell a session that its queue item was verified or answered, and if nothing matches,
# tell the captain the caller names for it.
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
# THE LOG LINE SAYS WHAT HAPPENED, NOT WHAT WAS ATTEMPTED. The review of #63 found this script logging "the
# notice went to X … woken by the verified verb" in two cases where neither was true: an unwritable notices
# directory (the failure went to stderr, which the caller discards) and a session that was already RUNNING
# and therefore never woken, which is the common case rather than an edge. Both were fixed by making the two
# acts report their real outcome and by writing a different sentence for each combination. The stakes are
# exactly the log's: it is the only record the caller keeps, so a sentence that overstates the act is worse
# than no sentence at all.
#
# WHAT IT DOES, in order:
#   1. resolves the note to an ABSOLUTE path, because the record carries it and a relative path means
#      something different depending on where the verb was run from;
#   2. reads `session:` from the note's frontmatter, through the shared reader in `claude/lib/pause-flag.sh`;
#   3. resolves that display NAME to a live sessionId through `claude agents --json --all`, refusing a
#      sessionId that is not a full 36-character id — `--resume ""` silently starts a NEW session;
#   4. writes a notice file at `~/.claude/notices/<sessionId>.md` — appended, never overwritten, because two
#      rulings can land before a session next runs;
#   5. if that session is STOPPED, wakes it with `--by "human:nelson"`;
#   6. if no session matches the name, notifies the CAPTAIN of the ship the note belongs to, the same way,
#      and the captain dispatches — this script NEVER dispatches;
#   7. writes one cross-session log entry per act, in RULING form: his words and the act they caused.
#
# TWO CALLS WERE RULED BEFORE IT WAS BUILT, both in the queue note "Rule the two calls in the verified-item
# notifier before it is built", ruled 2026-09-27 by `[A0] rear admiral` inside Nelson's "get it built":
#
#   CALL 1 — may a verb wake a session with no rank behind it? YES, as `human:nelson`, "because the click is
#   his and the alternative is a ruling that sits unread". That is one arm in `rank_of_caller` in
#   `claude/bin/_fleet-ranks.sh`, at rank -2, above the rear admiral. The ruling states its own limit, and so
#   does this script: `--by` IS NOT AUTHENTICATED. It is a string a caller supplies, so a session that chose
#   to could pass it, exactly as one could already write a stamp or a name it did not earn. What it buys is
#   that the wake is ATTRIBUTED AND LOGGED in his name — the log entry names the note and the verb — so a
#   wake nobody can account for is visible. What it cannot do is stop a session that decides to lie.
#
#   CALL 2 — does the fallback dispatch, or does the captain? THE CAPTAIN. "The script notifies the captain
#   (a notice on its file, plus a wake if it is stopped) with the note path and his words, and the captain
#   dispatches under the load gate with a rank answerable." Dispatching here would put a session on the
#   fleet with no rank having decided to, which is the one thing rule 19 exists to prevent, and no rank would
#   have checked the ruling is even executable. If the captain is itself stopped AND CANNOT BE WOKEN, or is
#   not in the listing at all, this falls back to the floating default session and LOGS THAT IT DID.
#
# THE SHIP MAP IS NOT IN THIS SCRIPT, and that is Nelson's own call, 2026-09-27: "the ship stuff is specific
# to our vault and needs to be kept as policy in the vault, not shipped with the PR." He is right, and the
# reason is worth stating so nobody helpfully puts it back. Which captain holds which vault surface is a VAULT
# decision: it changes when a ship is added, when a scope moves between captains, when a repo slot changes
# hands — none of which is a change to this repository. A copy of that map compiled into a dotfiles script is
# a second source of truth that goes stale in silence, and the first version of it was already wrong in three
# ways by the time the review of #63 read it.
#
# SO THE CALLER SAYS WHO. `--captain "<display name>"` is the session to tell when no session matches the
# note, and this script takes that answer without deriving, checking or second-guessing it. The verb that
# calls this runs on the obsidian ship, inside the vault, where the policy lives; applying the policy is its
# job, and the policy note is the one place the map is written down.
#
# THE FLOATING DEFAULT IS POLICY TOO, so `--floating-default` names it and the caller passes it for the same
# reason. What this script still carries is one name only, `[A0] rear admiral` — and that is fleet machinery
# rather than vault policy: it is in the rank table beside the rank codes, it is the same on every ship, and
# it is the answer to "who holds what nobody else does".
#
# WITH NO `--captain`, THE REAR ADMIRAL. That is the ruled default for a note whose ship cannot be told, and
# it is the one fallback that needs no vault knowledge at all: the unruled goes to him. The record says which
# it was — a captain the caller named, or the default because none was given.
#
# WHAT IT NEVER DOES: dispatch a session; invoke an accept verb (it is told that one happened, which is the
# opposite); write to the vault except the one cross-session log entry; or fail a verb. `--dry-run` prints
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

note="" event="" at="" words="" captain="" dry_run=0
while [ $# -gt 0 ]; do
  case "$1" in
    --note)    [ $# -ge 2 ] || die "--note needs a value";  note="$2"; shift 2 ;;
    --event)   [ $# -ge 2 ] || die "--event needs a value"; event="$2"; shift 2 ;;
    --at)      [ $# -ge 2 ] || die "--at needs a value";    at="$2"; shift 2 ;;
    --words)   [ $# -ge 2 ] || die "--words needs a value"; words="$2"; shift 2 ;;
    # The session to tell when no session matches the note. The CALLER applies the vault's policy and passes
    # the answer; this script never derives it from a path. See the header.
    --captain) [ $# -ge 2 ] || die "--captain needs a value"; captain="$2"; shift 2 ;;
    # The fallback-of-the-fallback: the session to tell when the captain cannot be told at all. Also policy,
    # also the caller's to name, and the env form stays for the battery.
    --floating-default) [ $# -ge 2 ] || die "--floating-default needs a value"; FLOATING_DEFAULT="$2"; shift 2 ;;
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

[ -e "$note" ] || die "no note at '$note'"
# THE PATH IS RESOLVED BEFORE ANYTHING READS IT. The ship map matches on leading path segments, so a relative
# path fell through every arm and went to the rear admiral — and the verb's working directory is the vault
# root often enough for that to be the common case, not a corner. The record keeps the resolved path too: a
# relative path in the log means nothing to a session that reads it from somewhere else.
note_dir=$(cd "$(dirname "$note")" 2>/dev/null && pwd -P) || note_dir=""
[ -n "$note_dir" ] || die "the note's directory could not be resolved from '$note'"
note="$note_dir/$(basename "$note")"

# --- the note's own session ------------------------------------------------------------------------
# THE LIBRARY IS FOUND BY COUNTING ONE LEVEL, not by walking up to `.git`, and that is deliberate. The walk
# used by the hook and the tickle gate finds *a* repository, which on a machine with a repo above the caller
# can be a stranger's; this script sits at a known depth inside its own checkout (`bin/` beside `lib/`), so
# one level up is exact. The guards are the same three: readable, parses, and defines what is wanted.
FLAG_LIB="$script_dir/../lib/pause-flag.sh"
[ -r "$FLAG_LIB" ] || die "the frontmatter reader is missing or unreadable at $FLAG_LIB"
bash -n "$FLAG_LIB" 2>/dev/null || die "the frontmatter reader at $FLAG_LIB does not parse; refusing rather than guessing at a note's session"
# shellcheck source=../lib/pause-flag.sh
. "$FLAG_LIB" || die "the frontmatter reader at $FLAG_LIB could not be sourced"
command -v read_frontmatter >/dev/null 2>&1 || die "the frontmatter reader parsed but defined nothing; refusing"

read_frontmatter "$note"
[ "$flag_state" = "read" ] || die "the note at '$note' has no readable frontmatter (${flag_reason:-$flag_state}), so it names no session"
target_name=$(fm_value session)

# --- the ship map ----------------------------------------------------------------------------------
# WHERE THE CAPTAIN CAME FROM, for the record. Not a map — there is no map here any more, by Nelson's call
# above. Either the caller named one, or nobody did and the rear admiral holds it.
if [ -n "$captain" ]; then
  map_reason="named by the caller, which is where the vault's ship policy is applied"
else
  map_reason="no --captain was given, so the rear admiral holds it, which is the ruled default"
fi

# --- the session listing ---------------------------------------------------------------------------
command -v jq >/dev/null 2>&1     || die "jq is required"
command -v claude >/dev/null 2>&1 || die "the claude CLI is required"
listing=$(claude agents --json --all 2>/dev/null) || listing=""
[ -n "$listing" ] || die "the session listing could not be read, so no notice can be addressed"

# A FULL sessionId OR NOTHING. `wake-session.sh` refuses a short or empty id because `--resume ""` starts a
# NEW session rather than continuing one, and a notice written under an empty id lands at `<dir>/.md`, which
# the injecting hook never reads — so this script refuses the same shape. `null` in the JSON arrives here as
# an empty field through `@tsv`, which is exactly the case the review caught.
valid_sid() {  # $1 = a sessionId
  case "$1" in
    ????????-????-????-????-????????????) return 0 ;;
    *) return 1 ;;
  esac
}

# The rows for a display name, and how many there are: a name is not unique, and which row was taken is a
# fact the record must carry rather than swallow. `wake-session.sh` treats a name collision as a hazard worth
# stating (two sessions sharing a name share a reporting line); the same is true of a notice.
rows_for_name() {  # $1 = display name; prints one "<id>\t<sessionId>\t<status>" line per match
  printf '%s' "$listing" | jq -r --arg n "$1" '.[] | select(.name == $n) | [.id, .sessionId, (.status // "stopped")] | @tsv' 2>/dev/null
}
row_count=0
row_ids=""
row_line=""
row_sid=""
row_status=""
find_row() {  # $1 = display name; sets row_line, row_sid, row_status, row_count and row_ids. Never in $( ).
  row_line=""; row_sid=""; row_status=""; row_count=0; row_ids=""
  all_rows=$(rows_for_name "$1")
  [ -n "$all_rows" ] || return 0
  row_count=$(printf '%s\n' "$all_rows" | grep -c . || true)
  row_ids=$(printf '%s\n' "$all_rows" | cut -f1 | tr '\n' ' ')
  row_line=$(printf '%s' "$all_rows" | tail -n 1)
  row_sid=$(printf '%s' "$row_line" | cut -f2)
  row_status=$(printf '%s' "$row_line" | cut -f3)
}
ambiguity_note() {  # $1 = display name; the clause the record carries when a name matched more than once
  if [ "${row_count:-0}" -gt 1 ]; then
    printf ' The name `%s` matched %s rows (%s) and the LAST was taken, so this notice reached one of them and the others were not told.' "$1" "$row_count" "$(printf '%s' "$row_ids" | sed 's/ $//')"
  fi
}

# ONE APPEND, ONE write() CALL. Two `printf`s into the same `>>` are two writes, and a concurrent appender can
# land between the heading and the body — the fleet log is written by every session. A single heredoc has no
# such window, which is what `wake-session.sh` does and why.
#
# AND IT IS A RULING ENTRY, not a "record". `claude/CLAUDE.md` allows three kinds in that file since
# 2026-09-26 — a claim, a release, or a ruling, which is "Nelson's words and the act they caused" — and this
# is exactly the third: his words, and what the notifier did about them. The earlier heading said "record",
# which is not one of the three.
log_line() {  # $1 = the sentence describing the act
  if [ "$dry_run" = 1 ]; then printf 'DRY RUN would log: %s\n' "$1"; return 0; fi
  stamp=$(date '+%Y-%m-%dT%H:%M')
  cat <<EOF >> "$FLEET_LOG" 2>/dev/null || printf '%s: the log entry could not be written to %s\n' "$PROG" "$FLEET_LOG" >&2

## $stamp · $PROG (the $event verb, on Nelson's click) — ruling

Nelson $event \`$note\` at $at. His words: $words

$1
EOF
}

# `notice_ok` is 1 only when a notice was actually appended (or would be, on a dry run). Nothing downstream
# may say "the notice went to X" unless this says so.
notice_ok=0
write_notice() {  # $1 = sessionId, $2 = who it is addressed to (for the text)
  notice_ok=0
  if [ "$dry_run" = 1 ]; then
    printf 'DRY RUN would write a notice for %s (%s) at %s/%s.md\n' "$2" "$1" "$NOTICES_DIR" "$1"
    notice_ok=1; return 0
  fi
  mkdir -p "$NOTICES_DIR" 2>/dev/null || { printf '%s: could not make %s\n' "$PROG" "$NOTICES_DIR" >&2; return 1; }
  printf -- '- your item `%s` was %s at %s: %s\n' "$note" "$event" "$at" "$words" >> "$NOTICES_DIR/$1.md" \
    || { printf '%s: could not write the notice for %s\n' "$PROG" "$1" >&2; return 1; }
  notice_ok=1
  return 0
}

# `wake_state` is the WORD for what happened, and there are five of them. The old version returned 0 both for
# "already running" and for "woken", which is how the log came to say a running session had been woken.
wake_state=""
wake_if_stopped() {  # $1 = sessionId, $2 = status, $3 = display name
  case "$2" in
    busy|idle) wake_state="already-running"; return 0 ;;
  esac
  if [ "$dry_run" = 1 ]; then
    printf 'DRY RUN would wake %s (%s) with --by "human:nelson"\n' "$3" "$1"
    wake_state="would-wake"; return 0
  fi
  if [ ! -x "$WAKE" ]; then
    printf '%s: no wake script at %s\n' "$PROG" "$WAKE" >&2
    wake_state="no-wake-script"; return 1
  fi
  if "$WAKE" --session "$1" --by "human:nelson" \
      --why "the $event verb on Nelson's click: $note" \
      --message "Your queue item \`$note\` was $event at $at. His words: $words. Read the note in full, then carry on from it." \
      >/dev/null 2>&1; then
    wake_state="woken"; return 0
  fi
  wake_state="wake-refused"
  return 1
}

# The two acts, in one sentence each, saying only what happened. Every combination has its own words: there
# is no sentence here that can be true of two different outcomes.
outcome_clause() {  # $1 = display name, $2 = sessionId, $3 = status
  case "$notice_ok$wake_state" in
    1already-running) printf 'the notice was written for `%s` (%s), which is %s, so it reads it on its next turn — nothing was woken' "$1" "$2" "$3" ;;
    1woken)           printf 'the notice was written for `%s` (%s), which was stopped, and it was woken by this script as `human:nelson`' "$1" "$2" ;;
    1would-wake)      printf 'the notice would be written for `%s` (%s), which is stopped, and it would be woken as `human:nelson`' "$1" "$2" ;;
    1wake-refused)    printf 'the notice was written for `%s` (%s), which was stopped, but the wake was REFUSED, so the notice waits until something else starts it' "$1" "$2" ;;
    1no-wake-script)  printf 'the notice was written for `%s` (%s), which was stopped, but there is no wake script to run, so the notice waits' "$1" "$2" ;;
    0*)               printf 'NO NOTICE COULD BE WRITTEN for `%s` (%s) — the notices directory could not be written — and the wake outcome was `%s`; nothing reached it and this entry is the only record' "$1" "$2" "${wake_state:-not attempted}" ;;
    *)                printf 'the notice state for `%s` (%s) is `%s`/`%s`, which this script did not expect; treat this entry as an incomplete record' "$1" "$2" "$notice_ok" "$wake_state" ;;
  esac
}

deliver() {  # $1 = display name, $2 = sessionId, $3 = status; leaves the clause in `delivery`
  write_notice "$2" "$1" || true
  wake_if_stopped "$2" "$3" "$1" || true
  delivery=$(outcome_clause "$1" "$2" "$3")
}

# --- 1. the session the note names -----------------------------------------------------------------
target_problem=""
if [ -n "$target_name" ]; then
  find_row "$target_name"
  if [ -n "$row_line" ]; then
    sid="$row_sid"
    status="$row_status"
    ambiguity=$(ambiguity_note "$target_name")
    if valid_sid "$sid"; then
      deliver "$target_name" "$sid" "$status"
      log_line "$delivery.$ambiguity"
      exit 0
    fi
    # A row with no usable sessionId cannot be notified or woken, so this is treated as no match and the
    # captain is told instead — with the reason, because a listing that gives a null id is itself news.
    target_problem="the listing has a row for \`$target_name\` but its sessionId is unusable ('$sid'), so nothing could be addressed to it"
  fi
fi

# --- 2. nothing matched: the ship's captain, or the rear admiral ------------------------------------
if [ -z "$captain" ]; then
  # Nobody was named, so the rear admiral holds it — NOT the floating default, which is only the fallback for
  # a captain that cannot be woken, below. `map_reason` above already says which case this is.
  captain="$REAR_ADMIRAL"
fi
unmatched="no session matched \`${target_name:-(the note names none)}\`"
[ -z "$target_problem" ] || unmatched="$target_problem"

fall_back_to_floating() {  # $1 = the clause explaining why the captain could not be told
  find_row "$FLOATING_DEFAULT"
  if [ -n "$row_line" ]; then
    fsid="$row_sid"
    fstatus="$row_status"
    float_ambiguity=$(ambiguity_note "$FLOATING_DEFAULT")
    if valid_sid "$fsid"; then
      deliver "$FLOATING_DEFAULT" "$fsid" "$fstatus"
      log_line "$unmatched, and $1, so this FELL BACK to the floating default: $delivery — logged as a fallback, per the ruling.$float_ambiguity"
      return 0
    fi
  fi
  log_line "$unmatched, $1, and the floating default \`$FLOATING_DEFAULT\` could not be addressed either — NOBODY was told, and this entry is the only record."
  return 0
}

find_row "$captain"
if [ -n "$row_line" ]; then
  csid="$row_sid"
  cstatus="$row_status"
  captain_ambiguity=$(ambiguity_note "$captain")
  if valid_sid "$csid"; then
    deliver "$captain" "$csid" "$cstatus"
    case "$wake_state" in
      woken|already-running|would-wake)
        log_line "$unmatched, so the captain was told ($map_reason): $delivery — the captain dispatches, this script does not.$captain_ambiguity"
        exit 0 ;;
    esac
    # The captain is stopped and could not be woken: the ruling's own fallback, and it must be logged AS one.
    fall_back_to_floating "\`$captain\` ($map_reason) was stopped and could NOT be woken"
    exit 0
  fi
  fall_back_to_floating "the row for \`$captain\` ($map_reason) carries an unusable sessionId ('$csid')"
  exit 0
fi

# A CAPTAIN WITH NO ROW AT ALL also cannot be woken, which the first version of this script did not treat as
# the same case: it logged that nobody was told and never tried the fallback the ruling gives for exactly
# this. "Stopped and cannot be woken" and "not in the listing" have the same consequence, so they take the
# same road.
fall_back_to_floating "\`$captain\` ($map_reason) is not in the listing at all"
exit 0
