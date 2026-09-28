#!/usr/bin/env bash
# rename-notebook.sh — keep a session's notebook entry filename in step with the session's name.
#
# Nelson's ruling (2026-09-26): "b is better, we just need machinery to rename agent notebooks if the
# session name changes." The entry is named `Agent session YYYY-MM-DDTHHMM <name without the
# bracketed code>.md`, and a name changes three ways: Nelson renames the session in the fleet view,
# `promote-session.sh` forks it under a new name, or a captain places it. Without this the filename
# and the entry's `session:` key drift apart, and the wake script and the console read the key.
#
# The shape is the one settled in the queue note "Rule on the notebook rename machinery and whether
# existing entries are retitled", which Nelson cleared, and every fact below was verified on this
# machine before the script was written.
#
# Usage:
#   rename-notebook.sh <sessionId> [--old-name "<name>"] [--notebook-dir <path>] [--log <path>]
#                      [--pause-note <path>] [--no-obsidian] [--dry-run] [-h]
#
#   <sessionId>  the session's full sessionId (also accepted as --session). The registry file
#                ~/.claude/sessions/<pid>.json is found by this, and it carries `name`, `nameSince`
#                and `formerNames` (objects with a `name` field) while the session lives.
#   --old-name   a name the entry may still carry, for when the registry's formerNames is already
#                gone: `promote-session.sh` passes it after a fork, because the old session has
#                exited by then.
#   --no-obsidian  rename with `mv` and repoint inbound wikilinks here, instead of asking a running
#                Obsidian to do it. Used when Obsidian is not running, and by the tests.
#   --notebook-dir, --log, --pause-note, --vault-path  overrides, for testing only. `--vault-path`
#                also bounds the link-repoint pass, so a test can keep it inside a scratch tree.
#   --dry-run    say what would happen and touch nothing, including while the fleet is paused.
#
# Two deliberate departures from its siblings, said here rather than left to be noticed. A paused or
# unreadable pause flag makes this script do nothing and exit 0, where promote-session.sh and
# wake-session.sh refuse with exit 2: this one is called by a hook on every prompt, and handing that a
# failure for a paused fleet would be noise, while leaving the file alone is already the safe state.
# And its log line is headed with the renamed session's name rather than an acting session's, because
# there is no `--by`: the actor is this machinery, usually fired by a hook, and inventing an actor
# would put a name in the record that did nothing.
#
# What it renames, and what it leaves alone. Only an entry whose filename is already the ruled form
# `Agent session <stamp> <name>.md` and whose `<name>` no longer matches the session's is renamed.
# A bare `Agent session <stamp>.md` is a pre-ruling entry and is NOT touched: Nelson ruled "leave em"
# on the 65 such entries, and the queue note says a running session renames its own file once by
# hand. A titled `Agent session <stamp> — <title>.md` is left alone too: the title there is a human's
# words, not a session name, and nothing authorises overwriting it. Only `running` entries are
# considered at all, because an `ended` entry is a record.
#
# How the rename happens. With Obsidian running, through the `obsidian` CLI with `vault=obsidian`
# pinned and the vault's base path asserted first from a neutral working directory (the CLI follows
# the most recently focused window, so neither is optional), because Obsidian's own rename repoints
# every inbound wikilink. With Obsidian closed, `mv` plus a repoint pass this script does itself,
# which touches other sessions' closed entries — rule 8a of 01.44 allows a mechanical,
# meaning-preserving, declared pass, and the count is logged.
#
# It also rewrites the entry's `session:` key to the new name, and its `title:` when that still holds
# the old basename, because the vault's convention is that a note's title is its filename.
#
# Refuses to do anything while the fleet is paused, read through the same gate the tickle jobs use
# (tickle/scripts/_lib/pause-gate.sh), and does nothing rather than half a rename if the flag cannot
# be read. Doing nothing is the safe state here, so an unreadable flag skips like a pause.
#
# Exit codes: 0 renamed, or nothing to do (including while paused); 2 refused or failed.
#
# Works under /bin/bash 3.2 (macOS). Needs jq; needs the `obsidian` CLI only when Obsidian is running.

set -euo pipefail

FLEET_LOG="$HOME/obsidian/00-09 System/03 Agents/03.16 Cross-session log/CROSS-SESSION.md"
VAULT_PATH="$HOME/obsidian"
VAULT_NAME="obsidian"
NOTEBOOK_DIR="$HOME/obsidian/00-09 System/03 Agents/03.04 Records/Agent notebook"
SESSIONS_DIR="$HOME/.claude/sessions"
# The repo root, resolved through the ~/.claude/bin symlink, so the tickle gate beside us is found.
script_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || script_dir=""
REPO_ROOT=$(cd "$script_dir/../.." 2>/dev/null && pwd -P) || REPO_ROOT=""
PAUSE_GATE="$REPO_ROOT/tickle/scripts/_lib/pause-gate.sh"

session="" old_name="" log="$FLEET_LOG" pause_note="" no_obsidian=0 dry_run=0

die() { printf 'rename-notebook: %s\n' "$*" >&2; exit 2; }
say() { printf 'rename-notebook: %s\n' "$*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --session)      [ $# -ge 2 ] && [ -n "$2" ] || die "--session needs a sessionId"; session="$2"; shift 2 ;;
    --old-name)     [ $# -ge 2 ] && [ -n "$2" ] || die "--old-name needs a name"; old_name="$2"; shift 2 ;;
    --notebook-dir) [ $# -ge 2 ] && [ -n "$2" ] || die "--notebook-dir needs a path"; NOTEBOOK_DIR="$2"; shift 2 ;;
    --log)          [ $# -ge 2 ] && [ -n "$2" ] || die "--log needs a path"; log="$2"; shift 2 ;;
    --pause-note)   [ $# -ge 2 ] && [ -n "$2" ] || die "--pause-note needs a path"; pause_note="$2"; shift 2 ;;
    --vault-path)   [ $# -ge 2 ] && [ -n "$2" ] || die "--vault-path needs a path"; VAULT_PATH="$2"; shift 2 ;;
    --no-obsidian)  no_obsidian=1; shift ;;
    --dry-run)      dry_run=1; shift ;;
    -h|--help)      awk 'NR>1 && !/^#/ {exit} NR>1 {sub(/^# ?/, ""); print}' "$0"; exit 0 ;;
    -*)             die "unknown argument: $1" ;;
    *)              [ -z "$session" ] || die "unexpected argument: $1"; session="$1"; shift ;;
  esac
done

[ -n "$session" ] || die "a sessionId is required (positionally, or as --session)"
command -v jq >/dev/null || die "jq is required"

# --- the pause ------------------------------------------------------------------------------------
# Deliberately unlike the siblings: promote-session.sh and wake-session.sh refuse with exit 2, because
# for them refusing IS the safe state. Here the safe state is to leave the file alone and say so, and
# a caller is usually the hook on every prompt, which must not be handed a failure for a paused fleet.
# A dry run reports the flag instead of stopping on it, as wake-session.sh's dry run does.
pause_state="clear"
if [ -x "$PAUSE_GATE" ]; then
  gate_rc=0
  if [ -n "$pause_note" ]; then
    PAUSE_NOTE="$pause_note" "$PAUSE_GATE" rename-notebook </dev/null >/dev/null 2>&1 || gate_rc=$?
  else
    env -u PAUSE_NOTE "$PAUSE_GATE" rename-notebook </dev/null >/dev/null 2>&1 || gate_rc=$?
  fi
  case "$gate_rc" in
    0) ;;
    1) pause_state="the fleet is paused" ;;
    *) pause_state="the fleet pause flag cannot be read (pause-gate exit $gate_rc)" ;;
  esac
else
  pause_state="the pause gate is not at $PAUSE_GATE"
fi
if [ "$pause_state" != "clear" ] && [ "$dry_run" = 0 ]; then
  say "$pause_state; nothing done"
  exit 0
fi

# --- the registry: the only place the current name lives ------------------------------------------
reg_file=""
for candidate in "$SESSIONS_DIR"/*.json; do
  [ -f "$candidate" ] || continue
  candidate_id=$(jq -r '.sessionId // ""' "$candidate" 2>/dev/null || echo "")
  if [ "$candidate_id" = "$session" ]; then reg_file="$candidate"; break; fi
done
[ -n "$reg_file" ] || die "no session registry file in $SESSIONS_DIR carries sessionId '$session'; a session that has exited leaves none, and without it the current name is unknown"

current_name=$(jq -r '.name // ""' "$reg_file")
[ -n "$current_name" ] || die "the registry file $reg_file carries no name"
former_names=$(jq -r '[.formerNames // [] | .[] | (if type == "object" then .name else . end)] | .[]' "$reg_file" 2>/dev/null || true)

# --- the name the filename should carry -----------------------------------------------------------
# Strip a leading bracketed rank-and-ship code, then the characters Obsidian forbids in a filename
# (* " \ / < > : | ?) become spaces, and runs of spaces collapse.
clean_name() {
  printf '%s' "$1" \
    | sed -E 's/^\[[^]]*\][[:space:]]*//' \
    | tr '*"\\/<>:|?' '         ' \
    | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}
new_clean=$(clean_name "$current_name")
[ -n "$new_clean" ] || die "the session's name '$current_name' leaves nothing after the code is stripped"

# --- the entry: running only, matching the current name or any former name ------------------------
fm_value() {  # $1 = file, $2 = key; frontmatter only, quotes stripped
  awk -v key="$2" '
    NR == 1 { if ($0 !~ /^---[ \t\r]*$/) exit; infm = 1; next }
    infm && $0 ~ /^---[ \t\r]*$/ { exit }
    infm && match($0, "^[ \t]*" key "[ \t]*:[ \t]*") {
      v = substr($0, RLENGTH + 1)
      gsub(/\r/, "", v); sub(/[ \t]+$/, "", v)
      if (v ~ /^".*"$/) v = substr(v, 2, length(v) - 2)
      else if (v ~ /^\047.*\047$/) v = substr(v, 2, length(v) - 2)
      print v; exit
    }
  ' "$1" 2>/dev/null || true
}

stamp_of_name() {  # the YYYY-MM-DDTHHMM inside a basename, or empty
  printf '%s' "$1" | sed -n -E 's/.*([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{4}).*/\1/p'
}

name_matches() {  # $1 = the entry's session: value
  [ "$1" = "$current_name" ] && return 0
  [ -n "$old_name" ] && [ "$1" = "$old_name" ] && return 0
  if [ -n "$former_names" ]; then
    while IFS= read -r fn; do
      [ -n "$fn" ] || continue
      [ "$1" = "$fn" ] && return 0
    done <<EOF
$former_names
EOF
  fi
  return 1
}

# THE STATUS RULE IS SHARED, not copied. `claude/lib/session-status.sh` carries which keys mean a running
# session while the notebook's status machine folds into the vault's, and this script and
# `claude/hooks/notebook-name-sync.sh` both read it — the pair used to hold the same `session-status = running`
# test written twice, which is exactly the shape that drifted in the pause parser before #61.
#
# FOUND BY COUNTING ONE LEVEL, not by walking up to `.git`: this script's depth inside its own checkout is
# fixed (`claude/bin/` beside `claude/lib/`), and one level up cannot land in a stranger's repository the way
# a walk can. Guarded the way #61 ruled — readable, parses, defines what is wanted — because a status reader
# that silently defines nothing would make every entry unreadable and rename nothing, quietly.
SESSION_STATUS_LIB="$script_dir/../lib/session-status.sh"
[ -r "$SESSION_STATUS_LIB" ] || die "the session-status rule is missing or unreadable at $SESSION_STATUS_LIB"
bash -n "$SESSION_STATUS_LIB" 2>/dev/null || die "the session-status rule at $SESSION_STATUS_LIB does not parse; refusing rather than guessing which entry is running"
# shellcheck source=../lib/session-status.sh
. "$SESSION_STATUS_LIB" || die "the session-status rule at $SESSION_STATUS_LIB could not be sourced"
command -v session_status_of >/dev/null 2>&1 || die "the session-status rule at $SESSION_STATUS_LIB parsed but defined no reader; refusing"

[ -d "$NOTEBOOK_DIR" ] || die "the notebook directory $NOTEBOOK_DIR does not exist"
entry=""
entry_stamp=""
candidates=$(grep -rl -E "^[[:space:]]*session[[:space:]]*:" "$NOTEBOOK_DIR" 2>/dev/null | sort || true)
if [ -n "$candidates" ]; then
  while IFS= read -r nb; do
    [ -n "$nb" ] || continue
    # NAME FIRST, THEN STATUS. The order is not a style choice: this loop walks EVERY entry with a `session:`
    # key, so judging the status before the name let one unrelated record decide the fate of every session —
    # the review of #65 proved seven live entries would have refused the renamer for everybody. A record that
    # is not ours is not our business, and `continue` is the only right answer to it.
    name_matches "$(fm_value "$nb" session)" || continue
    # EITHER KEY, until 2026-10-04, and a disagreement refuses rather than picking one. The rule and the five
    # states live in `claude/lib/session-status.sh`; this reads it, it does not restate it. The refusal stands
    # for an entry that IS ours: renaming the wrong file cannot be undone, and which key is stale is a thing
    # only a human can settle.
    session_status_of "$nb"
    case "$sess_state" in
      running) ;;
      conflict) die "refused: $nb disagrees with itself about whether its session is running — $sess_detail; fix the entry, because renaming the wrong one cannot be undone" ;;
      *) continue ;;
    esac
    nb_stamp=$(stamp_of_name "$(basename "$nb")")
    # Newest by the stamp in the filename, because a name recurs across days.
    if [ -z "$entry" ] || [ "$nb_stamp" \> "$entry_stamp" ]; then entry="$nb"; entry_stamp="$nb_stamp"; fi
  done <<EOF
$candidates
EOF
fi

if [ -z "$entry" ]; then
  say "no running notebook entry for '$current_name'${old_name:+ or '$old_name'} under $NOTEBOOK_DIR; nothing to do"
  exit 0
fi

old_base=$(basename "$entry")
[ -n "$entry_stamp" ] || { say "the entry $old_base carries no timestamp in its filename, so the ruled name cannot be built; nothing to do"; exit 0; }
new_base="Agent session $entry_stamp $new_clean.md"

# --- which filename forms this machinery may rewrite ---------------------------------------------
# Ruled form only: "Agent session <stamp> <name>.md". A bare entry is pre-ruling ("leave em"), and a
# titled one carries a human's words.
case "$old_base" in
  "Agent session $entry_stamp.md")
    say "$old_base is a pre-ruling entry with no name in its filename; Nelson ruled those are left alone (nothing to do)"
    exit 0 ;;
  "Agent session $entry_stamp — "*)
    say "$old_base carries a written title, not a session name, so it is left alone (nothing to do)"
    exit 0 ;;
  "Agent session $entry_stamp "*) ;;
  *)
    say "$old_base does not match the notebook's naming pattern; it is left alone (nothing to do)"
    exit 0 ;;
esac

# --- what needs doing: the filename, the keys, or neither ----------------------------------------
# The filename and the keys are checked separately on purpose. A filename that already carries the
# name while `session:` or `title:` still holds the old one is the fingerprint of an earlier run that
# was interrupted between the rename and the key rewrites; a filename-only idempotency check would
# declare that "nothing to do" for ever and the stale keys would never be reachable again.
#
# The `title:` test is deliberately narrow. A machine-written notebook title is the filename, so one
# that no longer matches it is stale and is repaired; a title a person has written instead is theirs
# and is left alone, whatever the filename says. Both the decision to act and the act itself use this
# one predicate, so a title left alone can never make the script think there is work left to do —
# which would have it repeat a no-op repair, and a log line with it, on every prompt for ever.
title_is_stale() {  # $1 = the file to read
  case "$(fm_value "$1" title)" in
    "${new_base%.md}") return 1 ;;                  # already right
    "" | "Agent session "*) return 0 ;;             # missing, or a machine title that has drifted
    *) return 1 ;;                                  # a person's own words
  esac
}

needs_rename=0
[ "$old_base" = "$new_base" ] || needs_rename=1
needs_keys=0
[ "$(fm_value "$entry" session)" = "$current_name" ] || needs_keys=1
if title_is_stale "$entry"; then needs_keys=1; fi

if [ "$needs_rename" = 0 ] && [ "$needs_keys" = 0 ]; then
  say "$old_base already carries the session's name, and its keys agree; nothing to do"
  exit 0
fi

new_path="$(dirname "$entry")/$new_base"
if [ "$needs_rename" = 1 ]; then
  [ ! -e "$new_path" ] || die "refused: $new_path already exists; two entries would collide"
  printf 'rename: %s\n    to: %s\n  session %s -> %s (sessionId %s)\n' "$old_base" "$new_base" "$(fm_value "$entry" session)" "$current_name" "$session"
else
  new_path="$entry"
  printf 'repair: %s keeps its name, but its keys are stale — the mark of an interrupted earlier run\n  session %s -> %s (sessionId %s)\n' "$old_base" "$(fm_value "$entry" session)" "$current_name" "$session"
fi

# --- the two rename roads ------------------------------------------------------------------------
obsidian_running=0
if [ "$no_obsidian" = 0 ] && pgrep -x Obsidian >/dev/null 2>&1; then obsidian_running=1; fi

vault_rel() {  # the path as the vault sees it
  printf '%s' "${1#"$VAULT_PATH"/}"
}

repoint_links() {  # $1 = old basename without .md, $2 = new basename without .md; prints the count
  # The count is what was actually rewritten, not what a plain grep matched: perl reports its own
  # substitution count per file on stderr, because a name that is a strict prefix of another entry's
  # name would match the grep and then be left alone by the gated substitution.
  link_files=$(grep -rl -F "[[$1" "$VAULT_PATH" --include='*.md' 2>/dev/null || true)
  link_count=0
  if [ -n "$link_files" ]; then
    while IFS= read -r lf; do
      [ -n "$lf" ] || continue
      # Only the link target is rewritten: an alias (|) or a heading (#) after it is left as it is.
      hits=$(perl -0777 -pi -e "BEGIN { \$o = quotemeta(\$ARGV[0]); \$n = \$ARGV[1]; shift; shift; \$c = 0 } \$c += s/\\[\\[\$o(?=[\\]|#])/[[\$n/g; END { print STDERR \$c }" "$1" "$2" "$lf" 2>&1 >/dev/null) \
        || die "could not repoint links in $lf"
      case "$hits" in ''|*[!0-9]*) hits=0 ;; esac
      link_count=$((link_count + hits))
    done <<EOF
$link_files
EOF
  fi
  printf '%s' "$link_count"
}

if [ "$dry_run" = 1 ]; then
  if [ "$needs_rename" = 0 ]; then
    printf '  road: none — only the keys would be rewritten, in place\n'
  elif [ "$obsidian_running" = 1 ]; then
    printf '  road: the obsidian CLI (Obsidian is running), which repoints inbound links itself\n'
  else
    printf '  road: mv, plus a repoint pass here (Obsidian is not running%s)\n' "$( [ "$no_obsidian" = 1 ] && printf ', --no-obsidian' )"
    # Counted the same way the real pass counts: the gated pattern, so a name that is a strict prefix
    # of another entry's name is not counted as something that would be rewritten.
    would_files=$(grep -rl -F "[[${old_base%.md}" "$VAULT_PATH" --include='*.md' 2>/dev/null || true)
    would_count=0
    if [ -n "$would_files" ]; then
      while IFS= read -r wf; do
        [ -n "$wf" ] || continue
        wh=$(perl -0777 -ne "BEGIN { \$o = quotemeta(\$ARGV[0]); shift } \$c = () = /\\[\\[\$o(?=[\\]|#])/g; print \$c" "${old_base%.md}" "$wf" 2>/dev/null || printf 0)
        case "$wh" in ''|*[!0-9]*) wh=0 ;; esac
        would_count=$((would_count + wh))
      done <<EOF
$would_files
EOF
    fi
    printf '  inbound link occurrences that would be repointed: %s\n' "$would_count"
  fi
  if [ "$pause_state" = "clear" ]; then
    printf '  the pause is clear, so a real run would go ahead.\n'
  else
    printf '  %s, so a real run would do nothing at all.\n' "$pause_state"
  fi
  printf '  dry run: nothing touched\n'
  exit 0
fi

renamed_by="nothing: the filename was already right, only its keys were stale"
links_repointed=""
repoint_failed=""
if [ "$needs_rename" = 1 ]; then
  if [ "$obsidian_running" = 1 ]; then
    command -v obsidian >/dev/null || die "Obsidian is running but the obsidian CLI is not on PATH"
    # The CLI follows the most recently focused window, so the vault is pinned AND its path asserted,
    # from a neutral working directory.
    seen_path=$(cd / && obsidian "vault=$VAULT_NAME" vault info=path 2>/dev/null | head -n 1 | tr -d '\r') || seen_path=""
    [ "$seen_path" = "$VAULT_PATH" ] || die "refused: the obsidian CLI answers for '$seen_path', not '$VAULT_PATH'; nothing was touched"
    out=$(cd / && obsidian "vault=$VAULT_NAME" rename "path=$(vault_rel "$entry")" "name=${new_base%.md}" 2>&1) || die "the obsidian CLI rename failed: $out"
    [ -f "$new_path" ] || die "the obsidian CLI reported '$out' but $new_base is not on disk; nothing else was changed"
    renamed_by="the obsidian CLI, which repointed inbound links itself"
  else
    # -n, because the existence check above and this move are not one act: another writer could have
    # created the destination in between, and a plain mv would overwrite it without a word. With -n a
    # losing race leaves both files alone, which the check afterwards turns into a refusal.
    mv -n "$entry" "$new_path" || die "mv failed; nothing else was changed"
    if [ -e "$entry" ] || [ ! -f "$new_path" ]; then
      die "refused: $new_base appeared while this was working, so mv -n moved nothing; both files are as they were"
    fi
    # A failure here must NOT abort before the keys are rewritten: the file has already moved, and a
    # half-done entry that no later run can see is worse than unrepointed links, which a person can fix.
    links_repointed=$(repoint_links "${old_base%.md}" "${new_base%.md}") || repoint_failed=1
    if [ -n "$repoint_failed" ]; then
      renamed_by="mv; the inbound-link repoint pass FAILED and those links still name $old_base"
    else
      renamed_by="mv, with $links_repointed inbound link occurrence(s) repointed by this script"
    fi
  fi
fi

# --- the keys inside the entry --------------------------------------------------------------------
# Always, whether or not the filename moved just now: this is the only path that can repair the keys
# of an entry whose earlier rename was interrupted.
entry_session=$(fm_value "$new_path" session)
if [ "$entry_session" != "$current_name" ]; then
  perl -0777 -pi -e 'BEGIN { $n = $ARGV[0]; shift } s/^(session[ \t]*:[ \t]*).*$/$1"$n"/m' "$current_name" "$new_path" \
    || die "the file is at $new_base but its session: key could not be rewritten; fix it by hand"
fi
if title_is_stale "$new_path"; then
  perl -0777 -pi -e 'BEGIN { $n = $ARGV[0]; shift } s/^(title[ \t]*:[ \t]*).*$/$1$n/m' "${new_base%.md}" "$new_path" \
    || die "the file is at $new_base but its title: key could not be rewritten; fix it by hand"
fi

# --- the record -----------------------------------------------------------------------------------
stamp=$(date '+%Y-%m-%dT%H:%M')
if [ "$needs_rename" = 1 ]; then
  headline="notebook entry renamed to match the session's name"
  body="Renamed \`$old_base\` to \`$new_base\` by \`rename-notebook.sh\` (sessionId $session): $renamed_by."
else
  headline="notebook entry's keys repaired after an interrupted rename"
  body="\`$old_base\` already carried the session's name while its keys did not, which is what an interrupted earlier rename leaves behind; \`rename-notebook.sh\` (sessionId $session) rewrote the keys and moved no file."
fi
cat <<EOF >> "$log"

## $stamp · $current_name — $headline

$body The entry's \`session:\` now reads \`$current_name\`. Nothing else in the entry was changed, and no \`ended\` entry was touched.
EOF

if [ -n "$repoint_failed" ]; then
  printf 'done with a failure: %s is now %s and its keys are right, but the inbound-link repoint pass failed and those links still name %s; repoint them by hand\n' "$old_base" "$new_base" "${old_base%.md}" >&2
  exit 2
fi
if [ "$needs_rename" = 1 ]; then
  printf 'done: %s is now %s; %s\n' "$old_base" "$new_base" "$renamed_by"
else
  printf 'done: %s keeps its name; its stale keys are repaired\n' "$old_base"
fi
