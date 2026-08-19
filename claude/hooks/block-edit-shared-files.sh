#!/usr/bin/env bash
# block-edit-shared-files.sh — PreToolUse hook for Edit/Write/MultiEdit.
#
# Blocks Edit/Write/MultiEdit against shared append-only files where
# concurrent writers cause Read→Edit races (see ~/.claude/CLAUDE.md
# § Notebook & Shared File Writes, and 05.50 Agent friction log entry
# 2026-05-11T11:02 documenting the exact race).
#
# Match policy: the file's basename matches one of the shared-write
# patterns below. Matching on basename keeps the rule path-independent
# (works whether the agent supplies an absolute path, a tilde-expanded
# path, or a vault-relative path).
#
# On match: exit 2 with a corrective message on stderr — Claude Code
# surfaces stderr back to the model, so the agent sees the suggested
# atomic-append command and can self-route to Bash.

input=$(cat)

# This guard parses its input with jq. If jq isn't on the hook's PATH the guard
# can't function — surface that on stderr instead of silently failing open (which
# would let the shared-file race through with no signal). Non-blocking (exit 0):
# a missing jq must not wedge every Edit/Write.
command -v jq >/dev/null 2>&1 || {
    echo "[block-edit-shared-files] jq not found on PATH — shared-file write guard DISABLED for this call" >&2
    exit 0
}

# Defensive: only run for file-mutating tools. The matcher in
# settings.json already restricts to these, but guard anyway.
tool=$(jq -r '.tool_name // empty' <<<"$input")
case "$tool" in
    Edit|Write|MultiEdit) ;;
    *) exit 0 ;;
esac

file_path=$(jq -r '.tool_input.file_path // empty' <<<"$input")
[ -n "$file_path" ] || exit 0

basename=$(basename -- "$file_path")

# Record-class surfaces: write-once archives where in-place edits destroy
# byte-verified content (see the Machinery record spine's reading rules;
# 2026-08-19: a mis-quoted shell write-back replaced an 86 KB record file
# with a literal command string — restored from backup). Matched by path
# segment, not basename, so every file in the folder is covered wherever
# the folder itself moves within a vault.
case "/$file_path" in
    */"Machinery record"/*.md)
        cat >&2 <<EOF
BLOCKED: '$file_path' is a record-class file (record: true) — folded content is
byte-verbatim and write-once; Edit/Write here is refused.

To add a correction or new record, APPEND a dated entry instead:

cat <<'EOF_ENTRY' >> '$file_path'

---

## $(date '+%Y-%m-%d') — <title>

<your entry — never modify text between %% fold %% markers>
EOF_ENTRY

Reading rules: the 'Machinery record' spine note in the same folder.
EOF
        exit 2
        ;;
esac

# Shared append-only files. Add new patterns here as the fleet adopts
# more shared coordination surfaces.
case "$basename" in
    "Agent friction log.md")
        # Current home since 2026-08-09:
        # /Users/nelson/obsidian/00-09 System/03 Agents/03.04 Records for 03 Agents/Agent friction log.md
        target="$file_path"
        ;;
    "05.50 Agent friction log.md")
        # Pre-2026-08-02 home; a tombstone keeps this basename at the
        # old path and stale sessions may still target it.
        target="$file_path"
        ;;
    "CROSS-SESSION.md")
        # Fleet cross-session coordination log. Home since 2026-08-18:
        # /Users/nelson/obsidian/00-09 System/03 Agents/03.16 Cross-session log/CROSS-SESSION.md
        # (has moved several times; matching by basename covers future moves).
        target="$file_path"
        ;;
    "Agent note for "????-??-??.md)
        # Legacy daily-rollup notebook (deprecated 2026-05-27 in favor of
        # per-session files). Still blocking in case one is ever revived
        # — the race condition would return with it.
        target="$file_path"
        ;;
    *)
        exit 0
        ;;
esac

cat >&2 <<EOF
BLOCKED: '$target' is a shared append-only file.
Edit/Write on it races with concurrent agent writers (see ~/.claude/CLAUDE.md § Notebook & Shared File Writes).

Use atomic Bash heredoc append instead:

cat <<'EOF_ENTRY' >> '$target'

## $(date '+%Y-%m-%dT%H:%M') · <handle>

<your entry>
EOF_ENTRY

The '>>' redirect is atomic at the OS level — no Read step, no race.
EOF
exit 2
