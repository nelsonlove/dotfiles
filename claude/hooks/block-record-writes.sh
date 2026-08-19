#!/usr/bin/env bash
# block-record-writes.sh — PreToolUse hook for Bash and mcp__vault-mcp__* tools.
#
# Companion to block-edit-shared-files.sh (which covers Edit/Write/MultiEdit):
# guards record-class files — the byte-verbatim, write-once fold archives under
# any "Machinery record/" folder (currently 00.16 Vault machinery) — against
# the two write paths that hook cannot see:
#
#   1. Bash-mediated writes. Catches the naive clobber forms: a truncating
#      redirect (`>` not `>>`) whose target mentions the record folder,
#      `tee` without -a, `sed -i`, and destructive `mv`/`rm`/`trash`.
#      Appends (`>>`, `tee -a`) pass — dated record entries are appends.
#   2. vault-mcp mutating tools (write_note, patch_note, manage_frontmatter,
#      delete/trash/move/refile/renumber, append_at_heading, …) whose input
#      references a record path. Only obsidian_append_note passes (end-of-file
#      appends are the sanctioned way to add a dated entry).
#
# HONEST LIMITS (threat model: fallible agents, not adversaries — see the
# accept-guard threat-model memory): a shell command that builds the path in
# a variable, cd's into the folder, or writes from inside an inline python/
# perl script is not caught (static detection of "will this command write
# file X" is undecidable; dotfiles#25 documents the same class of bypass in
# shell-move-safety.sh). The durable enforcement layer is server-side in
# vault-mcp — refusing non-append mutation of `record: true` notes — tracked
# upstream; this hook narrows the window until that ships.
#
# On match: exit 2 with a corrective message on stderr.

input=$(cat)

command -v jq >/dev/null 2>&1 || {
    echo "[block-record-writes] jq not found on PATH — record write guard DISABLED for this call" >&2
    exit 0
}

tool=$(jq -r '.tool_name // empty' <<<"$input")

MARKER="Machinery record"

corrective() {
    cat >&2 <<EOF
BLOCKED: this $1 would mutate a record-class file (under '$MARKER/').
Record folds are byte-verbatim and write-once; the only permitted change is
APPENDING a dated entry at end of file:

cat <<'EOF_ENTRY' >> '<record file path>'

---

## $(date '+%Y-%m-%d') — <title>

<your entry — never modify text between %% fold %% markers>
EOF_ENTRY

(vault-mcp obsidian_append_note is equally fine.) Reading rules: the
'Machinery record' spine note. If you believe this block is wrong, say so to
the human rather than working around it.
EOF
    exit 2
}

case "$tool" in
    Bash)
        cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
        [ -n "$cmd" ] || exit 0
        case "$cmd" in
            *"$MARKER"*) ;;
            *) exit 0 ;;
        esac
        # Truncating redirect whose target (same quoting run) reaches the marker.
        # `[^'\">]*` cannot cross a quote boundary, so a redirect into some other
        # file inside a script that merely *mentions* the marker does not match.
        if grep -Eq "(^|[^>&])>[[:space:]]*['\"]?[^'\">]*$MARKER" <<<"$cmd"; then
            corrective "shell redirect (truncating '>')"
        fi
        if grep -Eq "\btee[[:space:]]+(-[^a[:space:]][[:alnum:]]*[[:space:]]+)*['\"]?[^'\"|]*$MARKER" <<<"$cmd" \
           && ! grep -Eq "\btee[[:space:]]+(-[[:alnum:]]*a[[:alnum:]]*)" <<<"$cmd"; then
            corrective "tee without -a"
        fi
        if grep -Eq "\bsed[[:space:]]+(-[[:alnum:]]+[[:space:]]+)*-i[^[:space:]]*[[:space:]][^|;]*$MARKER" <<<"$cmd"; then
            corrective "in-place sed"
        fi
        if grep -Eq "\b(mv|rm|trash|/usr/bin/trash)\b[^|;&]*$MARKER" <<<"$cmd"; then
            corrective "destructive file operation (mv/rm/trash)"
        fi
        exit 0
        ;;
    mcp__vault-mcp__obsidian_append_note)
        exit 0
        ;;
    mcp__vault-mcp__*)
        case "$tool" in
            *read*|*search*|*list*|*get_*|*find_*|*check_links*|*resolve*|*note_history*|*note_diff*|*jump_to*|*open_*|*doctor*|*info*|*tags_list*|*conformance*|*pending_review*)
                exit 0 ;;
        esac
        args=$(jq -r '.tool_input | tostring' <<<"$input")
        case "$args" in
            *"$MARKER"*) corrective "vault-mcp mutation ($tool)" ;;
            *) exit 0 ;;
        esac
        ;;
    *)
        exit 0
        ;;
esac
