#!/bin/zsh
# task-curator DRY RUN — read-only. Spawns a plan-mode (harness-enforced read-only)
# worker ON THE SUBSCRIPTION (env -u ANTHROPIC_API_KEY, so claude -p uses the Max
# login, NOT API billing), analyzes a .02 scope, reports the curation plan to comms.
# Makes NO changes to the task store.
set -uo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"
SCOPE="${1:-$HOME/obsidian/00-09 System/03 LLMs & agents/03.02 Tasks for 03 LLMs & agents}"
COMMS_SEND="${COMMS_SEND:-$HOME/repos/agent-stack/plugins/agent-approvals/skills/comms-send/comms-send.sh}"
TODAY=$(date +%Y-%m-%d)
SCOPE_NAME="${SCOPE:t}"

# Prompt via stdin (NOT positional): --add-dir is variadic and would eat a positional prompt.
PROMPT="You are a task-curator DRY RUN — make no changes, report only. Today is $TODAY. Read the TaskNotes #task markdown files in this folder: '$SCOPE'. Each file's frontmatter has status/due/scheduled/priority/tags. Analyze up to ~15 open tasks and report CONCISELY what daily curation WOULD do: (1) OVERDUE (due before today); (2) SURFACE TODAY (should get scheduled=$TODAY); (3) STALE REVIEW (user/review tags that look resolved); (4) one-line counts. Do not edit anything. Plain text, no preamble."

REPORT=$(env -u ANTHROPIC_API_KEY claude -p --permission-mode plan --add-dir "$SCOPE" <<<"$PROMPT" 2>/dev/null)

TMP=$(mktemp)
{
  print -r -- "Task-curator DRY RUN (read-only) — $SCOPE_NAME"
  print -r -- "Ran $TODAY on the Max subscription (env -u ANTHROPIC_API_KEY). No changes made."
  print -r -- ""
  print -r -- "${REPORT:-(worker produced no output)}"
} > "$TMP"

"$COMMS_SEND" --title "task-curator dry run: $SCOPE_NAME" --from task-curator \
  --message "Read-only curation plan for $SCOPE_NAME ($TODAY) — see body." --body-file "$TMP" >/dev/null
rm -f "$TMP"
echo "task-curator dry run reported to comms for $SCOPE_NAME"
