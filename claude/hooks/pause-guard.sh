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
# The flag parser lives ONCE, in `claude/lib/pause-flag.sh`, and is sourced below. It used to be
# duplicated verbatim here and in `tickle/scripts/_lib/pause-gate.sh`, with a comment in each telling
# the reader to change both together — and by the time they were unified they had already drifted by
# one word. The two scripts must never disagree about what "paused" means, which is why it is one file.
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

# ---- the flag parser, from the one shared file ----
# `claude/lib/pause-flag.sh` holds it. This block and its twin in `tickle/scripts/_lib/pause-gate.sh` carried BYTE-IDENTICAL copies of
# a 69-line parser, each with a comment telling the reader to keep it identical to the other — and by the
# time they were unified they already differed by one word.
#
# Found by walking UP to the repo root rather than counting levels, because the two callers sit at
# different depths and a copied `../..` resolves to a path that does not exist. `.git` is a directory in
# the main checkout and a file in a worktree, so `-e` covers both, and from a worktree this reads that
# worktree's own copy.
pf_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || pf_dir=""
while [ -n "$pf_dir" ] && [ ! -e "$pf_dir/.git" ]; do [ "$pf_dir" != "/" ] || { pf_dir=""; break; }; pf_dir=$(dirname "$pf_dir"); done
PAUSE_FLAG_LIB="$pf_dir/claude/lib/pause-flag.sh"
# AND THE ROOT MUST BE THIS SCRIPT OWN REPO. The walk finds *a* repo, not necessarily this one: a `.git`
# above a copy of this script could belong to another tree that happens to hold a `claude/lib/pause-flag.sh`,
# and sourcing THAT read a paused note as clear and let a write through. Checking that the root contains
# this script at its expected path turns "a repo" into "my repo". Found by the review of #61.
if [ -n "$pf_dir" ] && [ ! -e "$pf_dir/claude/hooks/pause-guard.sh" ]; then
  msg="the root found at $pf_dir does not contain claude/hooks/pause-guard.sh, so it is not this script own repo; refusing rather than sourcing another tree pause parser"
  printf 'pause-guard: %s\n' "$msg" >&2; exit 2
fi
if [ -z "$pf_dir" ] || [ ! -r "$PAUSE_FLAG_LIB" ]; then
  printf 'pause-guard: the pause parser could not be found from %s (no .git above it, or %s is unreadable); refusing, because a pause that cannot be read must not be assumed absent\n' "$(dirname "$0")" "$PAUSE_FLAG_LIB" >&2
  exit 2
fi
# shellcheck source=../lib/pause-flag.sh
. "$PAUSE_FLAG_LIB" || { printf 'pause-guard: the pause parser at %s could not be sourced; refusing\n' "$PAUSE_FLAG_LIB" >&2; exit 2; }
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
# unquoted operators `|`, `||`, `&&`, `;` and the newline. It scans character by character
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
    local nl=$'\n'
    local cr=$'\r'
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
            "$nl"|"$cr")
                # A newline separates two commands exactly as `;` does. Without
                # this the allow-list sees `cat f<newline>rm -rf x` as one
                # stage, matches its `cat ` prefix and allows the `rm`.
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

    # The stage scan is a character loop, and bash 3.2 indexes a substring by
    # walking to the offset, which makes the loop quadratic: 4 KB costs about
    # 0.7s and 16 KB about 10s. A hook that takes ten seconds is one the
    # harness can give up on, and a guard that does not answer is a guard that
    # does not block — so refuse a long command unscanned rather than sit in
    # the loop. Nothing is lost: a read that wants the pause exemption is
    # short, and anything this size is a heredoc or an inline script, which is
    # write-shaped anyway. Worst case is now about 0.2s.
    if [ "${#cmd}" -gt 2000 ]; then
        return 1
    fi

    split_bash_stages "$cmd" || return 1

    local seg
    local seen="no"
    for seg in "${SEGMENTS[@]}"; do
        seg="$(printf '%s' "$seg" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        # A trailing `;` leaves an empty stage, which runs nothing.
        [ -n "$seg" ] || continue
        seen="yes"

        # The classifier this replaced refused these anywhere in the command,
        # quoted or not. That was blunt, but it was also doing a second job by
        # accident: it backstopped the allow-listed commands that can write
        # through their own quoted arguments, where the stage scan cannot see
        # them — `awk 'BEGIN{print "x" > "f"}'`, `python3 -c 'import os;
        # os.remove(...)'`, `find . -exec rm {} \;`. Splitting on unquoted
        # operators alone would drop that backstop and make all three legal
        # during a pause, so keep it, per stage: a stage carrying one of these
        # is write-shaped even when it is quoted.
        #
        # This is what keeps the change from granting anything new. Every
        # stage of an allowed command is now free of these AND on the
        # allow-list, which is exactly the test the old classifier applied to
        # the whole command — so any stage allowed here would have been
        # allowed on its own before. The only thing that changed is that a
        # command may now be split into stages at all.
        #
        # The pipeline from the issue is unaffected: `sed -n '1,12p' <note>`
        # and `grep -E '^paused'` carry none of these.
        case "$seg" in
            *';'*|*'&&'*|*'||'*|*'`'*|*'$('*|*'>'*|*'<('*)
                return 1
                ;;
        esac

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
