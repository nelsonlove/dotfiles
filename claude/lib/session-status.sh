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
#   `session-status: running`          → alive        `session-status: ended`           → ended
#   `status: draft/running`            → alive        `status: archived/ended`          → ended
#
# THE STATES this file reports, and they are the whole interface:
#   `running`  — one key, or both agreeing, says the session is alive.
#   `ended`    — one key, or both agreeing, says the process is exiting or gone.
#   `other`    — a key is present and carries something this rule does not name. NOT treated as either.
#   `conflict` — BOTH keys are present and they disagree. Never resolved in favour of one: a caller refuses
#                and names both values, exactly as `promote-session.sh` refuses a `--name` whose rank code
#                disagrees with its `--to`. A disagreement is the only thing that tells a human which key is
#                stale, so swallowing it would destroy the evidence and rename or wake the wrong entry.
#   `absent`   — neither key is present. An entry may legitimately have none, so this is not an error here;
#                what a caller does about it is the caller's own contract.
#
# WHAT IS WRITTEN, from now: `status: draft/running` and never the old key. Nothing in this repository writes
# either key into a note today — verified by grep on 2026-09-27, the only occurrences being READS in
# `rename-notebook.sh`, `notebook-name-sync.sh` and `wake-session.sh`, plus test fixtures — so this rule binds
# the fixtures and anything added later. A writer that emits the old key would be building work for the same
# migration twice.
#
# WHO USES IT, and who cannot. `rename-notebook.sh` and `notebook-name-sync.sh` read one file at a time and
# source this. `wake-session.sh` indexes the WHOLE notebook in one `awk` pass, so it carries the same rule
# inside that program rather than calling a shell function per file; the rule is stated HERE and the awk says
# so, because one of them being the authority is what stops the pair drifting the way the pause parser's two
# copies did before #61.
#
# AFTER 2026-10-04: delete the `session-status` arms, delete `SESSION_STATUS_DUAL_UNTIL`, and the state table
# above loses two rows. That is a deliberate expiry rather than a cleanup somebody might get round to — the
# date is in the code so a reader can see whether it has passed.
#
# Works under /bin/bash 3.2 (macOS). Needs nothing but the shell.

SESSION_STATUS_DUAL_UNTIL="2026-10-04"

# The value of one frontmatter key from a note, or empty. Deliberately NOT the reader in
# `claude/lib/pause-flag.sh`: that one wants the whole block and sets a family of globals, while this needs one
# line from one file and is called once per candidate in a loop over the notebook.
session_status_key() {  # $1 = file, $2 = key name
  sed -n '/^---[[:space:]]*$/,/^---[[:space:]]*$/p' "$1" 2>/dev/null \
    | tr -d '\r' \
    | grep -E "^[[:space:]]*$2[[:space:]]*:" \
    | head -n 1 \
    | sed -E "s/^[[:space:]]*$2[[:space:]]*:[[:space:]]*//" \
    | sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/' \
    | sed -E 's/[[:space:]]+$//'
}

# `sess_state` is one of the five words above; `sess_detail` is a sentence for a refusal or a log line, set
# whenever the state is `conflict` or `other`, and empty otherwise.
session_status_of() {  # $1 = the notebook entry's path
  sess_state="absent"
  sess_detail=""
  old_val=$(session_status_key "$1" "session-status")
  new_val=$(session_status_key "$1" "status")

  old_state=""
  case "$old_val" in
    "")        old_state="" ;;
    running)   old_state="running" ;;
    ended)     old_state="ended" ;;
    *)         old_state="other" ;;
  esac

  new_state=""
  case "$new_val" in
    "")                : ;;                        # no new key: `new_state` stays empty
    draft/running)     new_state="running" ;;
    archived/ended)    new_state="ended" ;;
    *)                 new_state="other" ;;
  esac

  if [ -n "$old_state" ] && [ -n "$new_state" ]; then
    if [ "$old_state" = "$new_state" ]; then
      sess_state="$old_state"
      [ "$sess_state" != "other" ] || sess_detail="both keys carry values this rule does not name: session-status '$old_val' and status '$new_val'"
    else
      sess_state="conflict"
      sess_detail="session-status says '$old_val' and status says '$new_val', which disagree; this is not resolved in favour of either, because the disagreement is what tells you which key is stale"
    fi
    return 0
  fi
  if [ -n "$new_state" ]; then
    sess_state="$new_state"
    [ "$sess_state" != "other" ] || sess_detail="status carries '$new_val', which is not draft/running or archived/ended"
    return 0
  fi
  if [ -n "$old_state" ]; then
    sess_state="$old_state"
    [ "$sess_state" != "other" ] || sess_detail="session-status carries '$old_val', which is not running or ended"
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
