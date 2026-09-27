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
#   --notebook-dir, --log, --pause-note  overrides, for testing only.
#   --dry-run    say what would happen and touch nothing.
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

# --- the pause: doing nothing is the safe state, so a pause and an unreadable flag both skip ------
if [ -x "$PAUSE_GATE" ]; then
  gate_rc=0
  if [ -n "$pause_note" ]; then
    PAUSE_NOTE="$pause_note" "$PAUSE_GATE" rename-notebook </dev/null >/dev/null 2>&1 || gate_rc=$?
  else
    env -u PAUSE_NOTE "$PAUSE_GATE" rename-notebook </dev/null >/dev/null 2>&1 || gate_rc=$?
  fi
  case "$gate_rc" in
    0) ;;
    1) say "the fleet is paused; nothing done"; exit 0 ;;
    *) say "the fleet pause flag cannot be read (pause-gate exit $gate_rc); nothing done"; exit 0 ;;
  esac
else
  say "the pause gate is not at $PAUSE_GATE; nothing done"
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

[ -d "$NOTEBOOK_DIR" ] || die "the notebook directory $NOTEBOOK_DIR does not exist"
entry=""
entry_stamp=""
candidates=$(grep -rl -E "^[[:space:]]*session[[:space:]]*:" "$NOTEBOOK_DIR" 2>/dev/null | sort || true)
if [ -n "$candidates" ]; then
  while IFS= read -r nb; do
    [ -n "$nb" ] || continue
    [ "$(fm_value "$nb" session-status)" = "running" ] || continue
    name_matches "$(fm_value "$nb" session)" || continue
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

if [ "$old_base" = "$new_base" ]; then
  say "$old_base already carries the session's name; nothing to do"
  exit 0
fi

new_path="$(dirname "$entry")/$new_base"
[ ! -e "$new_path" ] || die "refused: $new_path already exists; two entries would collide"

printf 'rename: %s\n    to: %s\n  session %s -> %s (sessionId %s)\n' "$old_base" "$new_base" "$(fm_value "$entry" session)" "$current_name" "$session"

# --- the two rename roads ------------------------------------------------------------------------
obsidian_running=0
if [ "$no_obsidian" = 0 ] && pgrep -x Obsidian >/dev/null 2>&1; then obsidian_running=1; fi

vault_rel() {  # the path as the vault sees it
  printf '%s' "${1#"$VAULT_PATH"/}"
}

repoint_links() {  # $1 = old basename without .md, $2 = new basename without .md; prints the count
  link_files=$(grep -rl -F "[[$1" "$VAULT_PATH" --include='*.md' 2>/dev/null || true)
  link_count=0
  if [ -n "$link_files" ]; then
    while IFS= read -r lf; do
      [ -n "$lf" ] || continue
      hits=$(grep -o -F "[[$1" "$lf" 2>/dev/null | grep -c . || true)
      [ "${hits:-0}" -gt 0 ] || continue
      link_count=$((link_count + hits))
      # Only the link target is rewritten: an alias or a heading after it is left as it stands.
      perl -0777 -pi -e "BEGIN { \$o = quotemeta(\$ARGV[0]); \$n = \$ARGV[1]; shift; shift } s/\\[\\[\$o(?=[\\]|#])/[[\$n/g" "$1" "$2" "$lf" 2>/dev/null \
        || die "could not repoint links in $lf"
    done <<EOF
$link_files
EOF
  fi
  printf '%s' "$link_count"
}

if [ "$dry_run" = 1 ]; then
  if [ "$obsidian_running" = 1 ]; then
    printf '  road: the obsidian CLI (Obsidian is running), which repoints inbound links itself\n'
  else
    printf '  road: mv, plus a repoint pass here (Obsidian is not running%s)\n' "$( [ "$no_obsidian" = 1 ] && printf ', --no-obsidian' )"
    printf '  inbound link occurrences that would be repointed: %s\n' "$(grep -r -o -F "[[${old_base%.md}" "$VAULT_PATH" --include='*.md' 2>/dev/null | grep -c . || echo 0)"
  fi
  printf '  dry run: nothing touched\n'
  exit 0
fi

renamed_by=""
links_repointed=""
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
  mv "$entry" "$new_path" || die "mv failed; nothing else was changed"
  links_repointed=$(repoint_links "${old_base%.md}" "${new_base%.md}")
  renamed_by="mv, with $links_repointed inbound link occurrence(s) repointed by this script"
fi

# --- the keys inside the entry --------------------------------------------------------------------
entry_session=$(fm_value "$new_path" session)
if [ "$entry_session" != "$current_name" ]; then
  perl -0777 -pi -e 'BEGIN { $n = $ARGV[0]; shift } s/^(session[ \t]*:[ \t]*).*$/$1"$n"/m' "$current_name" "$new_path" \
    || die "the file is renamed but its session: key could not be rewritten; fix it by hand"
fi
entry_title=$(fm_value "$new_path" title)
if [ "$entry_title" = "${old_base%.md}" ]; then
  perl -0777 -pi -e 'BEGIN { $n = $ARGV[0]; shift } s/^(title[ \t]*:[ \t]*).*$/$1$n/m' "${new_base%.md}" "$new_path" \
    || die "the file is renamed but its title: key could not be rewritten; fix it by hand"
fi

# --- the record -----------------------------------------------------------------------------------
stamp=$(date '+%Y-%m-%dT%H:%M')
cat <<EOF >> "$log"

## $stamp · $current_name — notebook entry renamed to match the session's name

Renamed \`$old_base\` to \`$new_base\` by \`rename-notebook.sh\` (sessionId $session): $renamed_by. The entry's \`session:\` now reads \`$current_name\`. Nothing else in the entry was changed, and no \`ended\` entry was touched.
EOF

printf 'done: %s is now %s; %s\n' "$old_base" "$new_base" "$renamed_by"
