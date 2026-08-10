#!/bin/bash
# Rex morning briefing v1 — rebuilt from the gen1 spec (Feature ledger §10 "Rex",
# recovered via the Inbox ideas inventory 2026-08-08). Gathers cheap non-TCC data,
# has headless claude compose the briefing, writes a dated record into the vault,
# and pushes a Pickle message notification.
# v2 candidates (need TCC grants or CLIs absent on this host): calendar + custody
# flag, email highlights, OmniFocus.
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/Users/nelson/.local/bin:$PATH"

VAULT="/Users/nelson/obsidian"
OUT_DIR="$VAULT/00-09 System/03 Agents/03.04 Records for 03 Agents/Rex briefings"
DATE=$(date +%F)
DOW=$(date "+%A")
CTX_FILE=$(mktemp)
trap 'rm -f "$CTX_FILE"' EXIT

{
  echo "## Date"
  echo "$DOW $DATE"
  echo
  echo "## Weather"
  curl -sm 10 'wttr.in/?format=%l:+%c+%t+(feels+%f),+wind+%w,+humidity+%h' || echo "(weather unavailable)"
  echo
  echo
  echo "## Pending approvals (Pickle)"
  pickle inbox 2>/dev/null || echo "(pickle unavailable)"
  echo
  echo "## Open system tasks (00.02)"
  grep -rl --include='*.md' "status: open" \
    "$VAULT/00-09 System/00 System management/00.02 Tasks for 00-09 System" 2>/dev/null \
    | while IFS= read -r f; do echo "- $(basename "$f" .md)"; done
  echo
  echo "## Hacker News top stories"
  for id in $(curl -sm 10 https://hacker-news.firebaseio.com/v0/topstories.json | jq -r '.[0:12][]' 2>/dev/null); do
    curl -sm 5 "https://hacker-news.firebaseio.com/v0/item/$id.json" \
      | jq -r '"- \(.title) (\(.score) pts) \(.url // "")"' 2>/dev/null
  done
} > "$CTX_FILE"

PROMPT_FILE="$(cd "$(dirname "$0")" && pwd)/prompt.md"
BRIEF=$(claude -p "$(cat "$PROMPT_FILE")

---
RAW CONTEXT:
$(cat "$CTX_FILE")")
if [ -z "$BRIEF" ]; then
  echo "rex-briefing: claude produced no output" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
NOTE="$OUT_DIR/$DATE Rex briefing.md"
{
  echo "---"
  echo "name: $DATE Rex briefing"
  echo "created: $(date "+%Y-%m-%dT%H:%M:%S")"
  echo "description: \"Rex morning briefing for $DATE — generated record; corrections are new records.\""
  echo "tags: []"
  echo "author:"
  echo "  - rex (claude headless)"
  echo "---"
  echo
  echo "$BRIEF"
} > "$NOTE"

pickle message --title "Rex briefing — $DOW $DATE" --body "$(printf '%s\n' "$BRIEF" | head -30)" >/dev/null 2>&1 \
  || echo "rex-briefing: pickle notification failed (briefing still written)" >&2

echo "briefing written: $NOTE"
