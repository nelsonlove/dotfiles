#!/usr/bin/env bash
# pause-guard.sh — PreToolUse hook enforcing the fleet pause.
#
# 01.65 Operator's console (design rule 10 / implementation step 8): the fleet
# pause is one flag note in the vault as the only state. This hook is the
# session-side enforcement: it refuses write-shaped tool calls while the flag
# is set and says who set it, since when, and why. Reads always continue.
# The scheduled-job half is tickle/scripts/_lib/pause-gate.sh in this repo —
# same note, same parser, different exit-code convention.
#
# Modeled on block-edit-shared-files.sh beside it: same stdin-JSON read via
# jq, same exit-2 block / exit-0 allow convention (Claude Code feeds a hook's
# stderr back to the model on exit 2 — see that hook's header for the
# citation).
#
# FAILS CLOSED on the flag. A pause is a human saying stop, so "I could not
# tell" must never mean "carry on". Only two states allow a call through: the
# note is absent, or the note parsed and says not paused. An unreadable note,
# a note with no frontmatter block, a missing or unrecognised `paused` value,
# and any unexpected shell failure all BLOCK with exit 2 — but only for
# write-shaped calls. Reads continue in every case, including a broken flag:
# a guard that blocks reads locks the session out of fixing the note that is
# the problem. Claude Code treats
# every exit code other than 0 and 2 as a non-blocking error — i.e. as allow —
# so the EXIT trap rewrites them all to 2, including the 1 that `set -u`
# returns for an unbound variable.
#
# Register it in claude/settings.json under hooks.PreToolUse for the matchers
# `Edit|Write|NotebookEdit|MultiEdit`, `Bash`, and `mcp__vault-mcp__.*`.
#
# PAUSE_NOTE overrides the note path, for testing only.
#
# The flag parser below is duplicated verbatim in
# tickle/scripts/_lib/pause-gate.sh. The two install through different paths
# (the ~/.claude/hooks symlink here, TICKLE_CONFIG_HOME there) and must never
# disagree about what "paused" means: change both together.
set -u

# Claude Code reads only 0 (allow) and 2 (block); anything else is a
# non-blocking error, which for a pause guard means the write goes through.
# Rewrite every unexpected exit to 2.
on_exit() {
  exit_rc=$?
  [ "$exit_rc" -eq 0 ] && exit 0
  exit 2
}
trap on_exit EXIT

# HOME can be absent from a hook environment. Resolve it rather than tripping
# `set -u` further down.
if [ -z "${HOME:-}" ]; then
  HOME=$(cd ~ 2>/dev/null && pwd) || HOME=""
  [ -n "$HOME" ] || HOME="/Users/nelson"
  export HOME
fi

# NOTE: split into an if-guard rather than PAUSE_NOTE="${PAUSE_NOTE:-...}" on
# one line. bash 3.2 (macOS /bin/bash) mis-parses the literal apostrophe in
# "Operator's" inside a ${VAR:-default} expansion even when double-quoted.
if [ -z "${PAUSE_NOTE:-}" ]; then
    PAUSE_NOTE="$HOME/obsidian/00-09 System/00 System management/00.08 Operator's console/Pause.md"
fi

input=$(cat)

# ---- flag parser (keep identical to tickle/scripts/_lib/pause-gate.sh) ----
# Sets: flag_state = absent | paused | clear | bad, flag_reason, flag_block.
# CR is stripped everywhere: a CRLF note otherwise never matches the `---`
# fence, which used to leave the frontmatter empty and the guard wide open.

sq="'"
flag_state=""
flag_reason=""
flag_block=""

fm_value() {
  printf '%s\n' "$flag_block" \
    | grep -E "^[[:space:]]*$1[[:space:]]*:" \
    | head -n 1 \
    | sed -E "s/^[[:space:]]*$1[[:space:]]*:[[:space:]]*//" \
    | sed -E "s/^\"(.*)\"\$/\1/; s/^${sq}(.*)${sq}\$/\1/" \
    | sed -E "s/[[:space:]]+\$//"
}

read_pause_flag() {
  if [ ! -e "$PAUSE_NOTE" ]; then
    flag_state="absent"
    return 0
  fi
  if [ ! -f "$PAUSE_NOTE" ] || [ ! -r "$PAUSE_NOTE" ]; then
    flag_state="bad"
    flag_reason="the note exists but is not a readable file"
    return 0
  fi

  # The opening fence must be the FIRST line. Matching any `---` anywhere
  # would read a thematic break in the body as the start of frontmatter.
  first_line=$(head -n 1 "$PAUSE_NOTE" 2>/dev/null | tr -d '\r' | sed -E "s/[[:space:]]+\$//")
  if [ "$first_line" != "---" ]; then
    flag_state="bad"
    flag_reason="the note has no frontmatter block (it does not begin with ---)"
    return 0
  fi

  flag_block=$(tr -d '\r' < "$PAUSE_NOTE" | awk 'NR==1{next} /^---[ \t]*$/{closed=1; exit} {print} END{if(!closed) exit 1}')
  if [ $? -ne 0 ]; then
    flag_state="bad"
    flag_reason="the note's frontmatter block is never closed"
    return 0
  fi

  paused_line=$(printf '%s\n' "$flag_block" | grep -E "^[[:space:]]*paused[[:space:]]*:" | head -n 1)
  if [ -z "$paused_line" ]; then
    flag_state="bad"
    flag_reason="the note's frontmatter has no 'paused' key"
    return 0
  fi

  paused_value=$(printf '%s' "$paused_line" \
    | sed -E "s/^[[:space:]]*paused[[:space:]]*:[[:space:]]*//" \
    | sed -E "s/[[:space:]]+#.*\$//" \
    | sed -E "s/^\"(.*)\"\$/\1/; s/^${sq}(.*)${sq}\$/\1/" \
    | sed -E "s/^[[:space:]]+//; s/[[:space:]]+\$//" \
    | tr '[:upper:]' '[:lower:]')

  case "$paused_value" in
    true|yes) flag_state="paused" ;;
    false|no) flag_state="clear" ;;
    *)
      flag_state="bad"
      flag_reason="the note's 'paused' value is not true/false/yes/no (found: '$paused_value')"
      ;;
  esac
  return 0
}
# ---- end flag parser ----

read_pause_flag

# Absent or explicitly not paused -> allow silently. This hook only ever reads
# the note directly (head/awk/grep, no tool call), so it can never block itself.
case "$flag_state" in
    absent|clear) exit 0 ;;
esac

# jq missing -> cannot classify the call. Unchanged from the original: allow,
# and say so loudly. This is the one remaining fail-open path.
command -v jq >/dev/null 2>&1 || {
    echo "[pause-guard] jq not found on PATH — pause guard DISABLED for this call" >&2
    exit 0
}

# ---- Paused, or the flag is unreadable. Either way the call is refused only
# if it is write-shaped: classify FIRST, so a broken flag never blocks a read.
# Blocking reads would wedge the session out of reading or fixing the note
# that is the whole problem. ----

is_readonly_segment() {
    local seg="$1"
    local simple_prefixes=(
        "ls" "cat" "head" "tail" "grep" "rg" "find" "wc" "stat" "echo"
        "pwd" "which" "realpath" "git status" "git log" "git diff"
    )
    local p
    for p in "${simple_prefixes[@]}"; do
        if [ "$seg" = "$p" ] || [[ "$seg" == "$p "* ]]; then
            return 0
        fi
    done

    if [ "$seg" = "sed -n" ] || [[ "$seg" == "sed -n "* ]]; then
        return 0
    fi

    if [ "$seg" = "awk" ] || [[ "$seg" == "awk "* ]]; then
        case "$seg" in
            *"-i"*) return 1 ;;  # awk in-place-ish flag — treat as write
            *) return 0 ;;
        esac
    fi

    if [[ "$seg" == "python3 -c "* ]]; then
        case "$seg" in
            *"open("*)
                # Reject if a write-ish mode literal appears anywhere.
                case "$seg" in
                    *"'w'"*|*'"w"'*|*"'a'"*|*'"a"'*|*"'w+'"*|*'"w+"'*| \
                    *"'x'"*|*'"x"'*|*"'r+'"*|*'"r+"'*)
                        return 1 ;;
                    *) return 0 ;;
                esac
                ;;
            *) return 0 ;;
        esac
    fi

    return 1  # unknown command -> when in doubt, write-shaped
}

# Split a Bash command line into the stages a shell would run it as, on the
# unquoted operators `|`, `||`, `&&` and `;`. It scans character by character
# rather than splitting on the bytes, so a pipe inside a quoted string is a
# literal pipe and not a stage boundary: `grep 'a|b' f` is one read, not two.
#
# Sets SEGMENTS to the stages, in order. Returns 1 — write-shaped, stop here,
# do not look at the stages — when it meets anything that could smuggle a
# write past a read-only-looking stage: an unquoted `>` (any redirection),
# `<(` (process substitution), a lone `&` (backgrounding), a backtick or `$(`
# anywhere a shell would expand them (which includes inside double quotes,
# where single quotes expand nothing), or a line that ends inside a quote.
split_bash_stages() {
    local cmd="$1"
    local n=${#cmd}
    local i=0
    local ch next
    local state="none"   # none | sq (inside '...') | dq (inside "...")
    local cur=""
    SEGMENTS=()

    while [ "$i" -lt "$n" ]; do
        ch="${cmd:$i:1}"
        next="${cmd:$((i + 1)):1}"

        if [ "$state" = "sq" ]; then
            # Single quotes expand nothing at all; only the closing quote ends it.
            [ "$ch" = "'" ] && state="none"
            cur="$cur$ch"; i=$((i + 1)); continue
        fi

        if [ "$state" = "dq" ]; then
            if [ "$ch" = "\\" ]; then
                cur="$cur$ch$next"; i=$((i + 2)); continue
            fi
            # Command substitution still runs inside double quotes.
            [ "$ch" = '`' ] && return 1
            [ "$ch" = '$' ] && [ "$next" = "(" ] && return 1
            [ "$ch" = '"' ] && state="none"
            cur="$cur$ch"; i=$((i + 1)); continue
        fi

        # state = none: this is where the shell's metacharacters mean something.
        case "$ch" in
            "\\")
                cur="$cur$ch$next"; i=$((i + 2)); continue
                ;;
            "'")
                state="sq"; cur="$cur$ch"; i=$((i + 1)); continue
                ;;
            '"')
                state="dq"; cur="$cur$ch"; i=$((i + 1)); continue
                ;;
            '`'|'>')
                return 1
                ;;
            '$')
                [ "$next" = "(" ] && return 1
                cur="$cur$ch"; i=$((i + 1)); continue
                ;;
            '<')
                # `<(` is process substitution; a bare `<` only reads a file,
                # and was allowed before this change too.
                [ "$next" = "(" ] && return 1
                cur="$cur$ch"; i=$((i + 1)); continue
                ;;
            '&')
                # `&&` is a stage boundary. A lone `&` backgrounds the job,
                # which no read-only call needs and which hides its own exit.
                [ "$next" = "&" ] || return 1
                SEGMENTS[${#SEGMENTS[@]}]="$cur"; cur=""; i=$((i + 2)); continue
                ;;
            '|')
                if [ "$next" = "|" ]; then
                    SEGMENTS[${#SEGMENTS[@]}]="$cur"; cur=""; i=$((i + 2)); continue
                fi
                SEGMENTS[${#SEGMENTS[@]}]="$cur"; cur=""; i=$((i + 1)); continue
                ;;
            ';')
                SEGMENTS[${#SEGMENTS[@]}]="$cur"; cur=""; i=$((i + 1)); continue
                ;;
        esac

        cur="$cur$ch"; i=$((i + 1))
    done

    # A line that ends mid-quote is malformed; do not guess what it meant.
    [ "$state" = "none" ] || return 1

    SEGMENTS[${#SEGMENTS[@]}]="$cur"
    return 0
}

# 01.65 rule 10: reads continue during a pause. A pipeline of reads is a read,
# so classify every stage and allow the call only when all of them are
# read-only. `cat a | tee b` is still refused, because `tee` is not on the
# allow-list and an unknown command is write-shaped.
is_readonly_bash() {
    local cmd="$1"
    cmd="$(printf '%s' "$cmd" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -n "$cmd" ] || return 1

    split_bash_stages "$cmd" || return 1

    local seg
    local seen="no"
    for seg in "${SEGMENTS[@]}"; do
        seg="$(printf '%s' "$seg" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        # A trailing `;` leaves an empty stage, which runs nothing.
        [ -n "$seg" ] || continue
        seen="yes"
        is_readonly_segment "$seg" || return 1
    done
    # Operators with no command between them: nothing recognisable ran, so do
    # not call it a read.
    [ "$seen" = "yes" ] || return 1
    return 0
}

tool=$(jq -r '.tool_name // empty' <<<"$input")
shaped="no"

case "$tool" in
    Edit|Write|NotebookEdit|MultiEdit)
        shaped="yes"
        ;;
    Bash)
        cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
        if is_readonly_bash "$cmd"; then
            shaped="no"
        else
            shaped="yes"
        fi
        ;;
    mcp__vault-mcp__obsidian_*)
        suffix="${tool#mcp__vault-mcp__obsidian_}"
        case "$suffix" in
            read_note|read_notes|read_note_parsed|search_notes|search_by_frontmatter|\
            list_notes|list_folders|get_backlinks|get_outlinks|vault_info|note_history|\
            note_diff|check_links|find_by_tag|resolve|resolve_uid|get_active_note|\
            tags_list|list_bookmarks|plugin_info|snippets_list|snippet_read|survey_status|\
            list_scope_claims|conformance_debt|environment_info|list_workspaces|get_command_ids)
                shaped="no"
                ;;
            *)
                shaped="yes"
                ;;
        esac
        ;;
    *)
        shaped="no"
        ;;
esac

# Not write-shaped -> allow, paused or broken flag alike. Reads always continue.
[ "$shaped" = "yes" ] || exit 0

# Write-shaped and the flag could not be read: refuse, because the pause
# cannot be ruled out.
if [ "$flag_state" = "bad" ]; then
    cat >&2 <<EOM
BLOCKED: the fleet pause flag could not be read, so the pause cannot be ruled out.
Note: '$PAUSE_NOTE'
Problem: $flag_reason

Reads continue; only write-shaped tool calls are refused. Fix the note (or set
PAUSE_NOTE) and retry. The guard fails closed on purpose: an unreadable flag
must not silently become "not paused".
EOM
    exit 2
fi

paused_by=$(fm_value "paused-by")
paused_since=$(fm_value "paused-since")
paused_why=$(fm_value "paused-why")

cat >&2 <<EOF
BLOCKED: the fleet is paused — see '$PAUSE_NOTE'.
Paused by: ${paused_by:-unknown}
Paused since: ${paused_since:-unknown}
Reason: ${paused_why:-none given}

Reads continue during a pause; only write-shaped tool calls are refused.
Clear the pause (set paused: false on the note) to resume.
EOF
exit 2
