#!/usr/bin/env bash
# session-status.sh — is the session that owns this notebook entry alive, from EITHER key.
#
# WHY THIS EXISTS. The notebook's status machine folds into the vault's ordinary one, ruled by Nelson through
# `[A0] rear admiral` on 2026-09-27: `session-status` becomes `status` carrying PATH VALUES —
# `draft/running` while a session runs, `archived/ended` once the process is exiting, and never `stable/*`. A
# resumed session writes a NEW entry pointing at the old one rather than reopening it.
#
# THE READERS IN THIS REPO MUST ACCEPT EITHER KEY UNTIL 2026-10-04, and only `status` after that date. The
# window exists because the vault's 55-entry migration and this repository land on different days, whichever
# way round: a reader that knows only the old key sees a migrated notebook as having no running entries at
# all, and a reader that knows only the new key sees today's notebook the same way. Both failures are SILENT
# — nothing refuses, the machinery just stops finding what it is looking for — which is why the window is
# ruled rather than left to whoever merges first.
#
# THE TWO KEYS ARE NOT OWNED THE SAME WAY, and getting this wrong nearly shipped a dead renamer. `status` is
# the vault's UNIVERSAL note-status key: it has carried `draft`, `stable/verified` and the rest on every class
# of note since long before any of this. `session-status` was ours alone and meant nothing else. So:
#
#   `session-status`  OURS. `running` or `draft/running` is a live claim, `ended` or `archived/ended` a dead
#                     one, and any other NON-EMPTY value is `other` — a malformed session status worth
#                     flagging, because nothing else ever writes that key. An EMPTY value (`session-status:`
#                     with nothing after it) is treated as absent rather than malformed: a key with no value is
#                     a key nobody finished writing, and there is nothing to flag or to act on.
#   `status`          SHARED. Only `draft/running` and `archived/ended` are session claims. Every other value
#                     — `draft`, `stable/verified`, `archived`, anything — IS NOT A SESSION CLAIM AT ALL and
#                     is ignored exactly as if the key were absent.
#
# THE REVIEW OF #65 PROVED WHY, against the live notebook: ten entries carry both keys, and SEVEN of them read
# `session-status: ended|running` beside `status: draft` — the vault's note status, saying nothing about
# liveness. Treating that as a session claim made every one of those seven a `conflict`, and
# `rename-notebook.sh` refuses on the first conflict it meets while scanning, so the rename machinery was dead
# for EVERY session until somebody hand-edited seven unrelated records — which this repo's own rule forbids,
# because records are historical. The census under both rules is at the bottom of this header.
#
# THE STATES, and they are the whole interface:
#   `running`  — a live claim from one key, or from both agreeing.
#   `ended`    — a dead claim, the same way.
#   `other`    — `session-status` carries something this rule does not name. Not treated as either.
#   `conflict` — BOTH keys make a claim and the claims disagree. Never resolved in favour of one: a caller
#                refuses and names both values, exactly as `promote-session.sh` refuses a `--name` whose rank
#                code disagrees with its `--to`. A disagreement is the only thing that tells a human which key
#                is stale, so swallowing it would destroy the evidence and rename or wake the wrong entry.
#   `absent`   — no claim from either key. An entry may legitimately have none — 463 of 518 today — so this is
#                not an error here; what a caller does about it is the caller's own contract.
#
# NO PIPELINE IN HERE MAY ABORT A CALLER. `rename-notebook.sh` runs under `set -euo pipefail`, and the first
# version of this file ended its key reader in a `grep` that exits 1 when a key is absent: under `pipefail`
# that became the assignment's status, and under `set -e` it killed the script mid-loop with exit 1 — outside
# its documented contract, on EVERY entry that carries only one key, which is almost every entry in today's
# notebook. The review of #65 caught it. Every command substitution here therefore ends in `|| true`, and the
# suite runs the library under `bash -euo pipefail` so the class cannot come back unnoticed.
#
# WHAT IS WRITTEN, from now: `status: draft/running` and never the old key. Nothing in this repository writes
# either key into a note today — the only occurrences are READS in `rename-notebook.sh`,
# `notebook-name-sync.sh` and `wake-session.sh`, plus test fixtures — so this rule binds the fixtures and
# anything added later.
#
# WHO USES IT, and who cannot. `rename-notebook.sh` and `notebook-name-sync.sh` read one file at a time and
# source this. `wake-session.sh` indexes the WHOLE notebook in one `awk` pass, so it carries the same rule
# inside that program rather than calling a shell function per file; the rule is stated HERE and the awk says
# so. The suite compares the two on every fixture, malformed ones included, which is the only thing that keeps
# two copies of one rule honest — the review found four inputs where they disagreed, and every one was a shape
# no well-formed fixture had.
#
# AFTER 2026-10-04: delete the `session-status` arms, delete `SESSION_STATUS_DUAL_UNTIL`, and `other` loses its
# only source. That is a deliberate expiry rather than a cleanup somebody might get round to — the date is in
# the code so a reader can see whether it has passed.
#
# THE CENSUS of all 518 entries, measured 2026-09-27 by running THIS FILE over every one of them under
# `bash -euo pipefail`. Under the rule as it now stands: 463 `absent`, 35 `ended`, 20 `running`, 0 `other`, 0
# `conflict`, and the run exits 0 — no entry aborts a caller. Under the rule the review rejected: 444 absent,
# 30 ended, 18 running, 19 `other` and SEVEN conflicts, every conflict being `status: draft` beside a real
# `session-status`. The 19 `other` were the same kind of value and are now correctly not read as claims.
#
# Those numbers were ESTIMATED in the first draft of this header and then measured; the measured ones stand.
# A census in a comment is worth nothing if it was guessed, so if you change the rule, re-run it.
#
# Works under /bin/bash 3.2 (macOS). Needs nothing but the shell and awk.

SESSION_STATUS_DUAL_UNTIL="2026-10-04"

# THE FRONTMATTER BLOCK, and nothing but it. Not a `sed` range: `sed -n '/^---$/,/^---$/p'` RE-ARMS on every
# later `---`, so a horizontal rule in the body opens a second "block" and body text is read as frontmatter —
# the review proved an entry whose body quoted the new key after a rule would have poisoned the whole scan.
# The rule is the one `claude/lib/pause-flag.sh` states: the opening fence must be the FIRST line, and the
# block ends at the first closing fence. This does not source that file, because its reader sets a family of
# `flag_*` globals that a caller may be holding mid-loop, and two libraries writing one another's variables is
# a collision no test would catch.
session_status_block() {  # $1 = file; prints the frontmatter lines, or nothing
  # EVERY `\r` GOES, not only a trailing one. The awk in `wake-session.sh` does `gsub(/\r/, "", s)`, so a value
  # with a carriage return INSIDE it — `draft\r/running` — read as two different things in the two readers
  # until this line matched that behaviour. A CRLF file is the ordinary case for a note edited on another
  # platform, and the pause parser learned the same lesson before it (see `claude/lib/pause-flag.sh`).
  awk 'NR == 1 { if ($0 !~ /^---[ \t\r]*$/) exit 1; next }
       /^---[ \t\r]*$/ { exit }
       { gsub(/\r/, ""); print }' "$1" 2>/dev/null || true
}

# One key's value out of a block, or empty. THE LAST OCCURRENCE WINS, because that is what the `awk` index in
# `wake-session.sh` does — a later assignment overwrites an earlier one — and the two must not disagree about a
# duplicated key. The order of cleaning matters and the review found it wrong: trailing whitespace comes off
# BEFORE the quotes, or `^"(.*)"$` never matches a value with a trailing space and the quotes survive into the
# comparison. A trailing ` # comment` goes too, because YAML allows one and both readers must agree that it is
# not part of the value.
session_status_value() {  # $1 = the block, $2 = key name
  printf '%s\n' "$1" \
    | grep -E "^[[:space:]]*$2[[:space:]]*:" \
    | tail -n 1 \
    | sed -E "s/^[[:space:]]*$2[[:space:]]*:[[:space:]]*//" \
    | sed -E 's/[[:space:]]+#.*$//' \
    | sed -E 's/[[:space:]]+$//' \
    | sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/' \
    | sed -E 's/[[:space:]]+$//' \
    || true
}

# `sess_state` is one of the five words above; `sess_detail` is a sentence for a refusal or a log line, set
# whenever the state is `conflict` or `other`, and empty otherwise.
session_status_of() {  # $1 = the notebook entry's path
  sess_state="absent"
  sess_detail=""
  sess_block=$(session_status_block "$1")
  [ -n "$sess_block" ] || return 0
  old_val=$(session_status_value "$sess_block" "session-status")
  new_val=$(session_status_value "$sess_block" "status")

  # OURS: every value is a claim, right or malformed.
  old_state=""
  case "$old_val" in
    "")                       old_state="" ;;
    running|draft/running)    old_state="running" ;;
    ended|archived/ended)     old_state="ended" ;;
    *)                        old_state="other" ;;
  esac

  # SHARED: only these two are session claims. Everything else is the vault's own note status and not ours to
  # read — `draft` is the commonest value in the notebook and says nothing about a session.
  new_state=""
  case "$new_val" in
    draft/running)            new_state="running" ;;
    archived/ended)           new_state="ended" ;;
    *)                        new_state="" ;;
  esac

  # A MALFORMED VALUE ON OUR KEY IS NOT A CLAIM, so it cannot disagree with one. This file's own table says
  # `other` is "not treated as either" and `conflict` is "BOTH keys make a claim" — and the first version of
  # this code contradicted both by reading `session-status: paused` beside `status: draft/running` as a
  # conflict, which refused the renamer for that session over a value that claims nothing. The review of the
  # fix-forward caught it while it was still latent (no live entry carries `other` today). The real claim wins
  # and the malformed value is NAMED in the detail, which is what a human needs to see to fix it.
  if [ "$old_state" = "other" ] && [ -n "$new_state" ]; then
    sess_state="$new_state"
    sess_detail="status says '$new_val', which this took as the answer, while session-status carries '$old_val', which is not a session status at all; the malformed key wants fixing but it changes nothing here"
    return 0
  fi
  if [ -n "$old_state" ] && [ -n "$new_state" ]; then
    if [ "$old_state" = "$new_state" ]; then
      sess_state="$old_state"
    else
      sess_state="conflict"
      sess_detail="session-status says '$old_val' and status says '$new_val', which disagree; this is not resolved in favour of either, because the disagreement is what tells you which key is stale"
    fi
    return 0
  fi
  if [ -n "$new_state" ]; then
    sess_state="$new_state"
    return 0
  fi
  if [ -n "$old_state" ]; then
    sess_state="$old_state"
    [ "$sess_state" != "other" ] || sess_detail="session-status carries '$old_val', which is not running, ended, draft/running or archived/ended; nothing but a session writes that key, so this is a malformed session status rather than a value of another kind"
    return 0
  fi
  return 0
}

# The question almost every caller actually asks. `conflict`, `other` and `absent` are all NOT running, which
# is the safe side for every caller in this repo today: the two renamers skip an entry they cannot read, and
# skipping one is recoverable while renaming the wrong one is not.
session_is_running() {  # $1 = the notebook entry's path
  session_status_of "$1"
  [ "$sess_state" = "running" ]
}
