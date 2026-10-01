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
# (That is the old call. The new one adds `--uid`, and two more events; see THE DEDUPE AND THE AUDIENCE below.)
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
#      something different depending on where the verb was run from; a relative path is tried under the vault
#      root first (`NOTIFY_VAULT_DIR`, default `~/obsidian`; never for a path with `..`), then from the working
#      directory;
#   2. reads the FIRST `session:` entry from the note's frontmatter (a list or a scalar), through the shared block reader in
#      `claude/lib/pause-flag.sh`; a free-text value and an ended lieutenant take the roads in THE DEDUPE AND THE AUDIENCE;
#   3. resolves that display NAME to a live sessionId through `claude agents --json --all`, refusing a
#      sessionId that is not a full 36-character id — `--resume ""` silently starts a NEW session;
#   4. writes a notice file at `~/.claude/notices/<sessionId>.md` — appended, never overwritten, because two
#      rulings can land before a session next runs;
#   5. if that session is STOPPED, wakes it with `--by "human:nelson"`;
#   6. if no session matches the name, notifies the CAPTAIN of the ship the note belongs to, the same way,
#      and the captain dispatches — this script NEVER dispatches;
#   7. writes one cross-session log entry per act, in RULING form: his words and the act they caused;
#   8. if it must refuse AFTER its arguments are valid (no note, no frontmatter, no listing, a wrong uid), tells
#      `[A0] rear admiral` by a notice (woken if stopped; once per failure), or, when the listing names no rear
#      admiral, appends the failure to the Agent friction log (`NOTIFY_FRICTION_LOG`), then exits 2 — because
#      the caller discards stderr, and on 2026-10-01 a revision request reached nobody that way.
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
# opposite); write to the vault except the one cross-session log entry, or, on the failure road of step 8 when no
# rear admiral can be addressed, one Agent friction log entry; or fail a verb. `--dry-run` prints
# every act it would take and touches nothing, which is how its battery runs.
#
# THE DEDUPE AND THE AUDIENCE, added on Nelson's "a" (all four picks), 2026-09-30, on `01.65 Operator's console/Tell the
# filing session when Nelson verifies, answers or asks for a revision.md`. Two roads call this script for the same act: the verb
# on his click, and the read-only listener in the vault-mcp plugin that sees every road (a hand edit, a verify from his phone
# through Sync). One act must give ONE alert, so each call carries the note's `uid` and the signal's identity:
#
#     notify-session.sh --note <path> --uid <note uid> --event verified|answered --at <the entry's at> [--words <text>]
#     notify-session.sh --note <path> --uid <note uid> --event revise    --signal <the callout's text> [--at <stamp>] [--words <text>]
#     notify-session.sh --note <path> --uid <note uid> --event for-agent --signal <the tag>            [--at <stamp>] [--words <text>]
#
# THE KEY. `verified` and `answered`: uid + event + `--at`, and `--at` is the `at:` of the `verified` entry (or of the answer),
# passed VERBATIM — the verb and the listener must pass the same string, offset included, or they are two keys. `revise` and
# `for-agent`: uid + event + the sha256 of `--signal`, which carries the callout's TEXT (for `revise`) or the TAG (for
# `for-agent`); `--at` is optional there and is not part of the key. `--signal` is hashed HERE, after one normalisation that
# both callers can rely on: `\r` removed; on every line the leading `>` quote markers and all leading and trailing blanks go;
# runs of blanks become one space; empty lines go; and for `for-agent` one leading `#` goes. So `#for-agent/review` and
# `for-agent/review` are one key, and a callout passed with or without its `> ` markers is one key. The consequence to know:
# the same callout text on the same note, or the same tag removed and added back later, is ONE signal and alerts once.
#
# THE STATE FILE is `${XDG_STATE_HOME:-~/.local/state}/notify-session/sent.jsonl`, one JSON object per line, append-only.
# XDG STATE, not data: it is a history of acts this script took, and losing it costs a repeated notice, never lost content —
# which is the spec's own example of state. `NOTIFY_STATE_DIR` moves it, for the battery.
#
# A REPEAT exits 0, prints "already notified", and does NOTHING else: no notice, no wake, no log line, and it does not even read
# the session listing. The check runs twice: once at the start without the lock (the cheap road for the common repeat), and
# again under the lock before the notice is written.
#
# THE ORDER IS: take the lock; check the key; write the notice; append the key ONLY IF the notice was written; release the lock;
# then wake and log. So a send that failed is NOT recorded and the next call tries again, and a racing call that waited on the
# lock finds the key and stops. macOS has no `flock`, so the lock is a `mkdir` of `sent.lock` holding the holder's pid; a lock
# whose pid is dead, or that is older than `NOTIFY_LOCK_STALE` seconds (10), is broken by renaming it aside. The lock is held
# only for the notice and the record, a few milliseconds, never across a wake. If the lock cannot be taken in 15 seconds, the
# notice is sent anyway and the log says it was not deduplicated: a duplicate costs noise, a lost notice costs a ruling unread.
#
# AN OLD CALLER with no `--uid` works as before, for `verified` and `answered` only. It cannot be deduplicated, and its log line
# says so. The two new events refuse a call without `--uid` and `--signal`, because they have no old callers to keep.
#
# WHO IS TOLD (the audience, pick 2). The FILER is the note's FIRST `session:` entry (01.65 rule 13); a list, a flow list and a
# scalar are all read.
#   * A session LABEL (`[<code>] <name>`) is told as before: its notice, and a wake if it is stopped.
#   * An `[L0]` (the one-task rank, Nelson 2026-09-30) whose NEWEST notebook entry is `archived/ended` is NOT woken and gets no
#     notice: the entry's `reports-to`, its dispatcher, is told instead. The entry is found by the listing row's sessionId, or,
#     when the job was removed, by its label; an entry that cannot be read or ordered is not guessed at, and the filer is
#     treated as today. A dispatcher that cannot be addressed goes down the captain road below, with the reason.
#   * A FREE-TEXT `session:` (no bracket label; about 150 old items) is never looked up by its text. It goes to `--captain`,
#     which the CALLER reads from the note's path under the vault's ship policy (the map stays out of this script, Nelson
#     2026-09-27); with no `--captain`, to `[A0] rear admiral`. Never a guess.
#   The log line's heading ends ` · for: <label>`, the audience grammar of the start hook's filter (dotfiles #106), so the
#   filer's chain up sees the ruling. The label is the filer's whenever the filer is a label, even when its dispatcher or the
#   captain was the one told; for a free-text or missing `session:`, it is the session that was told.
#
# Works under /bin/bash 3.2 (macOS). Needs jq, shasum and the claude CLI.

set -u
set -o pipefail

PROG=notify-session
FLEET_LOG="${NOTIFY_FLEET_LOG:-$HOME/obsidian/00-09 System/03 Agents/03.16 Cross-session log/CROSS-SESSION.md}"
NOTICES_DIR="${NOTIFY_NOTICES_DIR:-$HOME/.claude/notices}"
FLOATING_DEFAULT="${NOTIFY_FLOATING_DEFAULT:-[L0-FL] dotfiles}"
REAR_ADMIRAL="[A0] rear admiral"

script_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || script_dir=""
WAKE="${NOTIFY_WAKE_SCRIPT:-$script_dir/wake-session.sh}"
STATE_DIR="${NOTIFY_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/notify-session}"
SENT="$STATE_DIR/sent.jsonl"
LOCK="$STATE_DIR/sent.lock"
LOCK_STALE="${NOTIFY_LOCK_STALE:-10}"
LOCK_TRIES="${NOTIFY_LOCK_TRIES:-300}"   # 300 x 0.05 s = 15 s; the battery shortens it
# The notebook roots, for an ended lieutenant's entry: `<agents>/03.04 Records/Agent notebook` and `<agents>/03.09 Archive/Agent
# notebook`, through `claude/lib/notebook-roots.sh`. `NOTIFY_AGENTS_DIR` moves both, for the battery.
AGENTS_DIR="${NOTIFY_AGENTS_DIR:-$HOME/obsidian/00-09 System/03 Agents}"
# The vault root, for a vault-relative `--note`. `NOTIFY_VAULT_DIR` moves it, for the battery.
VAULT_DIR="${NOTIFY_VAULT_DIR:-$HOME/obsidian}"

# ONE `die`, and a flag that makes it loud. Quiet while the arguments are checked (a caller's misuse is the caller's bug, and
# must not page an admiral on every click); loud from the line that sets `loud=1`, below, once every argument is valid. See
# FROM HERE ON A FAILURE IS LOUD.
loud=0
die() {
  [ "$loud" = 1 ] && tell_failure "$*"
  printf '%s: %s%s\n' "$PROG" "$*" "${tf_told:+; $tf_told}" >&2
  exit 2
}

note="" event="" at="" words="" captain="" dry_run=0 uid="" signal="" signal_given=0
while [ $# -gt 0 ]; do
  case "$1" in
    --note)    [ $# -ge 2 ] || die "--note needs a value";  note="$2"; shift 2 ;;
    --event)   [ $# -ge 2 ] || die "--event needs a value"; event="$2"; shift 2 ;;
    --at)      [ $# -ge 2 ] || die "--at needs a value";    at="$2"; shift 2 ;;
    --words)   [ $# -ge 2 ] || die "--words needs a value"; words="$2"; shift 2 ;;
    # The note's `uid`: the dedupe key starts with it. See THE DEDUPE AND THE AUDIENCE in the header.
    --uid)     [ $# -ge 2 ] || die "--uid needs a value";   uid="$2"; shift 2 ;;
    # The callout's text (revise) or the tag (for-agent); hashed here into the key.
    --signal)  [ $# -ge 2 ] || die "--signal needs a value"; signal="$2"; signal_given=1; shift 2 ;;
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
[ -n "$event" ] || die "--event is required: verified, answered, revise or for-agent"
case "$event" in
  verified|answered|revise|for-agent) ;;
  *) die "--event must be 'verified', 'answered', 'revise' or 'for-agent', got '$event'" ;;
esac
# `--at` is the verb's own stamp, taken at write time. Refused rather than defaulted: see the header. Required for the two
# accept events, whose key it is; optional for the two signals, whose key is the hash.
case "$event" in
  verified|answered) [ -n "$at" ] || die "--at is required and is never invented here; the verb takes the stamp at write time" ;;
esac
if [ -n "$at" ]; then
  case "$at" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]*) ;;
    *) die "--at must be an ISO stamp like 2026-09-27T14:05 (got '$at'); a wrong time on his ruling is worse than no notice" ;;
  esac
  # The stamp goes into the key and the state file verbatim, so it holds nothing but a stamp's characters.
  case "$at" in
    *[!0-9TZ:.+-]*) die "--at may hold only digits, T, Z, ':', '.', '+' and '-' (got '$at')" ;;
  esac
fi
[ -n "$words" ] || words="(no words given)"

# THE UID AND THE SIGNAL. A `uid` holds only the characters a uid has, because it goes into the key verbatim.
if [ -n "$uid" ]; then
  case "$uid" in
    *[!A-Za-z0-9._-]*) die "--uid may hold only letters, digits, '.', '_' and '-' (got '$uid')" ;;
  esac
fi
case "$event" in
  revise|for-agent)
    [ -n "$uid" ] || die "--uid is required for '$event': the dedupe key starts with the note's uid"
    [ "$signal_given" = 1 ] || die "--signal is required for '$event': the callout's text (revise) or the tag (for-agent)" ;;
  *)
    [ "$signal_given" = 0 ] || die "--signal is for 'revise' and 'for-agent' only; the key of '$event' is its --at" ;;
esac

# The one normalisation of a signal, stated in the header: both callers rely on it, so it is changed only with both of them.
normalise_signal() {  # $1 = the raw signal; prints the normal form
  printf '%s\n' "$1" | tr -d '\r' \
    | sed -E 's/^[[:space:]>]*//; s/[[:space:]]+$//; s/[[:space:]]+/ /g' \
    | awk 'NF' \
    | { if [ "$event" = "for-agent" ]; then sed -E '1s/^#//'; else cat; fi; }
}
key=""
signal_norm=""
if [ -n "$uid" ]; then
  case "$event" in
    verified|answered) key="$uid|$event|$at" ;;
    *)
      signal_norm=$(normalise_signal "$signal")
      [ -n "$signal_norm" ] || die "--signal is empty once normalised; there is nothing to key on"
      command -v shasum >/dev/null 2>&1 || die "shasum is required to key a '$event' signal"
      sig_hash=$(printf '%s' "$signal_norm" | shasum -a 256 | cut -c1-64)
      key="$uid|$event|$sig_hash" ;;
  esac
fi

# FROM HERE ON A FAILURE IS LOUD, not a line on stderr, which every caller discards. On 2026-10-01 at 16:17 the Request
# revision verb called this script twice with a vault-relative path, both calls died with "no note at", and the only trace
# was `verb-calls.log`: Nelson asked for a revision and no session heard of it. Every argument is valid by this line, so any
# later refusal (no note, no frontmatter, no listing, a wrong uid, a missing library) means an act of his reached nobody.
# `die` now tells the rear admiral: a notice on its file and a wake if it is stopped. ONCE PER FAILURE, keyed in the same
# state file as the alerts (`$SENT`): the key is a hash of the event, the note as the caller gave it, the uid, the alert key
# and the reason, so two roads reporting one failure (the verb and the listener) give one notice, even after the rear admiral
# has read and cleared the first. If the listing names no rear admiral, or its notice cannot be written, the failure goes to
# the Agent friction log, which needs no listing. A dry run only prints what it would do.
#
# THE WAKE IS `--by "human:nelson"`, as the alert wake is, because only that identity may wake an admiral, and the act that
# failed was his click. So the notice says first that it is NOT a ruling, which the injecting hook's preamble would suggest.
FRICTION_LOG="${NOTIFY_FRICTION_LOG:-$AGENTS_DIR/03.04 Records/Agent friction log.md}"
note_given="$note"
tf_told=""
tell_failure() {  # $1 = the failure; sets tf_told
  loud=0   # once: a failure inside this function must not call it again
  tf_msg="NOT A RULING: a script failure after his click. notify-session could not deliver a \`$event\` alert for \`$note_given\`: $1 (uid ${uid:-none}; his words: $words). Nobody else was told; find the note and tell its filer."
  if [ "$dry_run" = 1 ]; then printf 'DRY RUN would tell %s: %s\n' "$REAR_ADMIRAL" "$tf_msg"; tf_told="a dry run, so nobody was told"; return 0; fi
  tf_key="fail|$(printf '%s\n' "$event" "$note_given" "$uid" "$key" "$1" | shasum -a 256 2>/dev/null | cut -c1-64)"
  if [ -f "$SENT" ] && grep -qF "\"key\":\"$tf_key\"" "$SENT" 2>/dev/null; then
    tf_told="this failure was already reported"; return 0
  fi
  tf_why="the session listing names no usable \`$REAR_ADMIRAL\`"
  tf_row=$(claude agents --json --all 2>/dev/null \
    | jq -r --arg n "$REAR_ADMIRAL" '[.[] | select(.name == $n)] | last // empty | [(.sessionId // ""), (.status // "stopped")] | @tsv' 2>/dev/null) || tf_row=""
  tf_sid=$(printf '%s' "$tf_row" | cut -f1)
  tf_status=$(printf '%s' "$tf_row" | cut -f2)
  tf_done=0
  case "$tf_sid" in
    ????????-????-????-????-????????????)
      if mkdir -p "$NOTICES_DIR" 2>/dev/null && printf -- '- %s\n' "$tf_msg" >> "$NOTICES_DIR/$tf_sid.md" 2>/dev/null; then
        tf_done=1
        case "$tf_status" in
          busy|idle) tf_told="the rear admiral was told" ;;
          *) if [ -x "$WAKE" ] && "$WAKE" --session "$tf_sid" --by "human:nelson" --why "notify-session failed: $1" \
                 --message "$tf_msg" >/dev/null 2>&1; then tf_told="the rear admiral was told and woken"
             else tf_told="the rear admiral was told, but it is stopped and the wake was refused"; fi ;;
        esac
      else
        tf_why="the notice for \`$REAR_ADMIRAL\` could not be written to $NOTICES_DIR"
      fi ;;
  esac
  if [ "$tf_done" = 0 ]; then
    if printf '\n## %s · notify-session\n\n%s Not delivered to the rear admiral: %s.\n' \
         "$(date '+%Y-%m-%dT%H:%M')" "$tf_msg" "$tf_why" >> "$FRICTION_LOG" 2>/dev/null; then
      tf_done=1; tf_told="$tf_why, so the failure is in the Agent friction log"
    else
      tf_told="NOBODY could be told: $tf_why, and the friction log could not be written"
    fi
  fi
  if [ "$tf_done" = 1 ]; then
    mkdir -p "$STATE_DIR" 2>/dev/null && printf '{"key":"%s","event":"%s","failure":true,"sent":"%s"}\n' \
      "$tf_key" "$event" "$(date '+%Y-%m-%dT%H:%M:%S%z')" >> "$SENT" 2>/dev/null || true
  fi
}
loud=1

already_sent() {  # is the key in the state file?
  [ -n "$key" ] && [ -f "$SENT" ] && grep -qF "\"key\":\"$key\"" "$SENT" 2>/dev/null
}
# THE CHEAP ROAD FOR A REPEAT, before anything else is read: see the header. The dry run reports it too, and does nothing else.
if already_sent; then
  printf '%s: already notified (%s); nothing done\n' "$PROG" "$key"
  exit 0
fi

# A VAULT-RELATIVE PATH IS RESOLVED AGAINST THE VAULT ROOT FIRST. The verbs pass the note's path as Obsidian knows it
# (`00-09 System/…`), and this script runs from wherever the caller stands, which is not always the vault; a second tree with
# the same layout (`~/obsidian-mobile`, a backup checkout) must not win just because the caller stood in it. So a relative path
# is tried under the vault root first and from the working directory second. A path with a `..` segment is never joined to
# the vault root, so it cannot climb out of it; a leading `~/` is the home directory, as a shell would read it.
case "$note" in
  "~/"*) note="$HOME/${note#"~/"}" ;;
esac
case "$note" in
  /*|..|../*|*/../*|*/..) ;;
  *) [ -e "$VAULT_DIR/$note" ] && note="$VAULT_DIR/$note" ;;
esac
[ -e "$note" ] || die "no note at '$note' (a relative path is tried under $VAULT_DIR, then from the working directory)"
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

# A `--uid` THAT IS NOT THE NOTE'S OWN is refused: the key would be wrong, and a wrong key either repeats an alert or swallows a
# different note's. A note with no `uid:` takes the caller's.
if [ -n "$uid" ]; then
  note_uid=$(fm_value uid)
  if [ -n "$note_uid" ] && [ "$note_uid" != "$uid" ]; then
    die "--uid '$uid' is not the note's own uid '$note_uid'; refusing rather than keying the wrong note"
  fi
fi

# THE FILER: the FIRST `session:` entry (01.65 rule 13). The queue notes carry it as a YAML LIST (`session:` then `  - "…"`),
# which `fm_value` reads as empty, so before this every list-form note went down the captain road. This reads a block list, a
# flow list (`["a", "b"]`) and a scalar, at column zero, first occurrence.
first_session() {
  printf '%s\n' "$flag_block" | awk '
    # THE SAME NORMALISATION AS `roster_value` in claude/lib/session-roster.sh (review of #110): a QUOTED value ends at its
    # first closing quote, so a trailing ` # comment` after it goes; only an UNQUOTED value loses ` # …` by itself.
    function unq(v,   q, i) {
      sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
      q = substr(v, 1, 1)
      if (q == "\"" || q == "\047") {
        i = index(substr(v, 2), q)
        if (i > 0) return substr(v, 2, i - 1)
      }
      sub(/[ \t]+#.*$/, "", v); sub(/[ \t]+$/, "", v)
      return v
    }
    !found && /^session[ \t]*:/ {
      v = $0; sub(/^session[ \t]*:[ \t]*/, "", v); sub(/[ \t]+$/, "", v)
      if (v == "") { inlist = 1; found = 1; next }
      if (v ~ /^\[[ \t]*["\047]/) {                      # a flow list of quoted items: the first one
        sub(/^\[[ \t]*/, "", v); q = substr(v, 1, 1); v = substr(v, 2)
        i = index(v, q); if (i > 0) v = substr(v, 1, i - 1)
        print v; exit
      }
      print unq(v); exit
    }
    inlist {
      if ($0 ~ /^[ \t]*-[ \t]*/) { v = $0; sub(/^[ \t]*-[ \t]*/, "", v); print unq(v); exit }
      if ($0 ~ /^[ \t]*$/) next
      exit
    }'
}
target_name=$(first_session)
# A LABEL is `[<code>] <name>`. Anything else is free text and is never looked up by its text: see the header.
is_label() { printf '%s' "$1" | grep -qE '^\[[^]]+\] +[^ ]'; }

# The rank table and the three notebook readers, found the way the frontmatter reader is found: one level up, and refused
# rather than guessed at if any is missing or does not parse.
for lib in "$script_dir/_fleet-ranks.sh" "$script_dir/../lib/notebook-roots.sh" "$script_dir/../lib/session-roster.sh" "$script_dir/../lib/session-status.sh"; do
  [ -r "$lib" ] || die "a library is missing or unreadable at $lib"
  bash -n "$lib" 2>/dev/null || die "the library at $lib does not parse; refusing rather than guessing who filed the note"
  # shellcheck disable=SC1090
  . "$lib" || die "the library at $lib could not be sourced"
done
for fn in rank_of_name notebook_entry_files_of roster_newest_entry_for_id roster_read roster_value session_status_of; do
  command -v "$fn" >/dev/null 2>&1 || die "the libraries parsed but '$fn' is not defined; refusing"
done
NB_ROOT="$AGENTS_DIR/03.04 Records/Agent notebook"
AR_ROOT="$AGENTS_DIR/03.09 Archive/Agent notebook"

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
  # THE AUDIENCE MARK, in the grammar of the start hook's filter (#106): one ` · for: <label>` segment after the kind.
  audience=""
  [ -z "$for_label" ] || audience=" · for: $for_label"
  cat <<EOF >> "$FLEET_LOG" 2>/dev/null || printf '%s: the log entry could not be written to %s\n' "$PROG" "$FLEET_LOG" >&2

## $stamp · $PROG ($source_words) — ruling$audience

$act_sentence His words: $words

$1$dedupe_note
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
  printf -- '- %s: %s\n' "$notice_about" "$words" >> "$NOTICES_DIR/$1.md" \
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
      --message "$wake_about. His words: $words. Read the note in full, then carry on from it." \
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

# --- the dedupe: lock, check, notice, record --------------------------------------------------------
# The order is the header's: lock, check, notice, record only if the notice was written, unlock; the wake comes after.
lock_held=0
lock_is_stale() {  # $1 = a lock directory: stale if its pid is dead, or it is older than LOCK_STALE seconds
  ls_pid=$(cat "$1/pid" 2>/dev/null || true)
  if [ -n "$ls_pid" ] && ! kill -0 "$ls_pid" 2>/dev/null; then return 0; fi
  ls_m=$(stat -f %m "$1" 2>/dev/null || true)
  [ -n "$ls_m" ] && [ $(( $(date +%s) - ls_m )) -gt "$LOCK_STALE" ]
}
lock_take() {
  mkdir -p "$STATE_DIR" 2>/dev/null || return 1
  lt_tries=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    # EVERY PASS COUNTS AND WAITS, the stale branch included (re-review of #110): a stale lock that cannot be removed (an
    # unwritable state dir, a failed `mv`) spun here forever at full CPU and never reached the send-anyway road.
    lt_tries=$((lt_tries + 1))
    [ "$lt_tries" -lt "$LOCK_TRIES" ] || return 1
    if lock_is_stale "$LOCK"; then
      # BROKEN UNDER A SECOND LOCK, and judged stale AGAIN inside it (review of #110). A check followed by a rename was not
      # atomic: two callers could both judge the dead holder's lock stale, the first break it and take a fresh one, and the
      # second then rename the first's LIVE lock away, so both notified. Inside `sent.lock.break` only one breaker acts, and
      # a lock a winner has just made (fresh mtime, a live pid or none yet) is not stale on the re-check.
      if mkdir "$LOCK.break" 2>/dev/null; then
        if lock_is_stale "$LOCK"; then
          mv "$LOCK" "$LOCK.stale.$$" 2>/dev/null && rm -rf "$LOCK.stale.$$"
        fi
        rmdir "$LOCK.break" 2>/dev/null || true
      elif lock_is_stale "$LOCK.break"; then
        # A breaker that died inside the break lock (a few lines of shell) leaves it behind; the same age rule clears it.
        rmdir "$LOCK.break" 2>/dev/null || true
      fi
      sleep 0.05
      continue
    fi
    sleep 0.05
  done
  printf '%s\n' "$$" > "$LOCK/pid" 2>/dev/null || true
  lock_held=1
  return 0
}
lock_drop() {
  [ "$lock_held" = 1 ] || return 0
  rm -rf "$LOCK" 2>/dev/null || true
  lock_held=0
}
trap lock_drop EXIT

recorded=0      # 1 once this run has appended its key
dedupe_note=""  # the sentence the log adds when this call could not be, or was not, deduplicated
if [ -z "$uid" ]; then
  dedupe_note=" No \`--uid\` was given, so this call could not be deduplicated: a later call for the same act would notify again."
fi
record_key() {  # $1 = the display name told, $2 = its sessionId
  [ -n "$key" ] && [ "$recorded" = 0 ] || return 0
  if [ "$dry_run" = 1 ]; then printf 'DRY RUN would record the key %s in %s\n' "$key" "$SENT"; recorded=1; return 0; fi
  line=$(jq -cn --arg key "$key" --arg uid "$uid" --arg event "$event" --arg at "$at" --arg note "$note" \
    --arg to "$1" --arg sid "$2" --arg stamp "$(date '+%Y-%m-%dT%H:%M:%S%z')" \
    '{key: $key, uid: $uid, event: $event, at: $at, note: $note, to: $to, sessionId: $sid, sent: $stamp}' 2>/dev/null) || line=""
  if [ -n "$line" ] && printf '%s\n' "$line" >> "$SENT" 2>/dev/null; then
    recorded=1
  else
    dedupe_note="$dedupe_note The dedupe record could not be written to \`$SENT\`, so a repeat of this call would notify again."
  fi
}

deliver() {  # $1 = display name, $2 = sessionId, $3 = status; leaves the clause in `delivery`
  if [ -n "$key" ] && [ "$recorded" = 0 ] && [ "$dry_run" = 0 ]; then
    if lock_take; then
      # THE SECOND CHECK, under the lock: a racing call that got here first has recorded the key, and this one stops.
      if already_sent; then
        lock_drop
        printf '%s: already notified (%s); nothing done\n' "$PROG" "$key"
        exit 0
      fi
    else
      dedupe_note=" The dedupe lock at \`$LOCK\` could not be taken, so this notice was sent without the check: a repeat is possible."
    fi
  fi
  write_notice "$2" "$1" || true
  [ "$notice_ok" = 1 ] && record_key "$1" "$2"
  lock_drop
  wake_if_stopped "$2" "$3" "$1" || true
  delivery=$(outcome_clause "$1" "$2" "$3")
}

# --- the words, per event --------------------------------------------------------------------------
at_clause=""
[ -z "$at" ] || at_clause=" at $at"
# The signal as the notice and the log SHOW it: one line, because a notice is one bullet. The key keeps the lines.
signal_show=$(printf '%s' "$signal_norm" | tr '\n' ' ' | sed -E 's/ +$//')
case "$event" in
  verified|answered)
    source_words="the $event verb, on Nelson's click"
    act_sentence="Nelson $event \`$note\`$at_clause."
    what="was $event$at_clause" ;;
  revise)
    source_words="a revise callout"
    act_sentence="Nelson asked for a revision of \`$note\`$at_clause: \`$signal_show\`."
    what="has a revision asked for$at_clause: \`$signal_show\`" ;;
  for-agent)
    source_words="a for-agent tag"
    act_sentence="Nelson tagged \`$note\` with \`$signal_show\`$at_clause."
    what="was tagged \`$signal_show\`$at_clause" ;;
esac
notice_about="your item \`$note\` $what"
wake_about="Your queue item \`$note\` $what"
for_label=""

# --- 1. the session the note names -----------------------------------------------------------------
target_problem=""
if [ -n "$target_name" ] && ! is_label "$target_name"; then
  # FREE TEXT is never looked up: a row that happens to carry the same words is not the filer. See the header.
  target_problem="the note's \`session:\` is \`$target_name\`, which is free text and not a session label, so it was not looked up"
  target_name=""
fi
if [ -n "$target_name" ]; then
  for_label="$target_name"
  find_row "$target_name"

  # AN ENDED LIEUTENANT IS NOT WOKEN (Nelson, 2026-09-30: `[L0]` is the one-task rank). Its newest entry is found by the row's
  # sessionId when there is a row, and by its label when the job was removed; anything this cannot read or order is not
  # guessed at, and the filer is treated as today.
  if [ "$(rank_of_name "$target_name")" = 3 ]; then
    l0_entry=""
    if [ -n "$row_line" ] && valid_sid "$row_sid"; then
      roster_newest_entry_for_id "$row_sid" "$NB_ROOT" 1 "$AR_ROOT" 1
      if [ -n "$roster_entry" ] && [ "${roster_entry_ambiguous:-0}" = 0 ] && [ "${roster_entry_unreadable:-0}" = 0 ]; then
        l0_entry="$roster_entry"
      fi
    elif [ -z "$row_line" ]; then
      # BY LABEL: the newest entry whose `session:` is this label, by the stamp in its filename. A tie or an unstamped
      # candidate leaves it unknown. `grep -lF` narrows the files first, so ~500 entries cost one pass, not 500 parses.
      best=""; best_stamp=""; tie=0; unstamped=0
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        roster_read "$f"
        [ "$roster_session" = "$target_name" ] || continue
        st=$(printf '%s' "${f##*/}" | sed -n -E 's/.*([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{4}).*/\1/p')
        # AN UNSTAMPED CANDIDATE IS STICKY (review of #110): it cannot be ordered, so no later stamp can make the answer known.
        if [ -z "$st" ]; then unstamped=1; continue; fi
        if [ -z "$best" ] || [ "$st" \> "$best_stamp" ]; then best="$f"; best_stamp="$st"; tie=0
        elif [ "$st" = "$best_stamp" ]; then tie=1; fi
      done <<EOF
$(notebook_entry_files_of "$NB_ROOT" 1 "$AR_ROOT" 1 | tr '\n' '\0' | xargs -0 grep -lF -- "$target_name" 2>/dev/null)
EOF
      [ "$tie" = 1 ] || [ "$unstamped" = 1 ] || l0_entry="$best"
    fi
    if [ -n "$l0_entry" ]; then
      session_status_of "$l0_entry"
      if [ "$sess_state" = "ended" ]; then
        roster_read "$l0_entry"
        dispatcher=$(roster_value "$roster_block" "reports-to")
        ended_why="the filer \`$target_name\` is a lieutenant whose newest entry \`${l0_entry##*/}\` is archived/ended, so it was NOT woken and got no notice"
        notice_about="the item \`$note\`, filed by \`$target_name\` (a lieutenant you dispatched, now ended), $what"
        wake_about="The queue item \`$note\`, filed by \`$target_name\` (a lieutenant you dispatched, now ended), $what"
        if [ -n "$dispatcher" ] && is_label "$dispatcher"; then
          find_row "$dispatcher"
          if [ -n "$row_line" ] && valid_sid "$row_sid"; then
            ambiguity=$(ambiguity_note "$dispatcher")
            deliver "$dispatcher" "$row_sid" "$row_status"
            log_line "$ended_why; its dispatcher (the entry's \`reports-to\`) was told instead: $delivery.$ambiguity"
            exit 0
          fi
          target_problem="$ended_why, and its dispatcher \`$dispatcher\` (the entry's \`reports-to\`) could not be addressed"
        else
          target_problem="$ended_why, and the entry names no usable \`reports-to\` ('$dispatcher')"
        fi
        row_line=""   # the captain road below, never the ended lieutenant
      fi
    fi
  fi

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
# A FREE-TEXT OR MISSING `session:` names no label, so the audience is the session this road tells.
[ -n "$for_label" ] || for_label="$captain"
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
