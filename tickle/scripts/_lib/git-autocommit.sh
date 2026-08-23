#!/bin/bash
# _lib/git-autocommit.sh <bare-git-dir> <work-tree>
# Auto-commit a directory into an external, local-only backup repo. Safety net
# for migration / Blueprint / bulk-apply edits. NEVER pushes; only ever
# add/commit, and never checks out into the work-tree. Self-inits the bare
# repo so the backup stands itself up with no manual setup.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

GITDIR="$1"; WT="$2"
G(){ git --git-dir="$GITDIR" --work-tree="$WT" "$@"; }

# DOCTRINE (obsidian-backup's own scar): this silent green exit is exactly
# what turned "vault deleted" into months of green runs once before. It
# survives here ONLY because every current caller FATALs on absence BEFORE
# calling this helper — if you are writing a third caller, add that loud
# guard there; do not let this line be your only absence check.
[[ -d "$WT" ]] || exit 0                 # target not present — nothing to back up
[[ -d "$GITDIR" ]] || git init --bare -q "$GITDIR"

# A run killed mid-add/commit (timeout, sleep, power loss) leaves a stale
# index.lock that would fail every future run forever. Runs are capped at 5m,
# so a lock older than 10m cannot belong to a live git — clear it.
find "$GITDIR" -maxdepth 1 -name index.lock -mmin +10 -delete

# Nested git repos are stored as content-less gitlinks — their files would NOT
# be in the backup. Warn loudly so the run log shows it (such repos are
# usually self-backed by their own history/remote).
nested=$(find "$WT" -maxdepth 6 -name .git 2>/dev/null | head -5)
if [[ -n "$nested" ]]; then
  echo "WARNING: nested git repos present; their contents are NOT captured:"
  echo "$nested"
fi

# -f plus a null excludes file: a safety net must ignore ignore-rules — the
# global ~/.config/git/ignore would silently drop files like
# **/.claude/settings.local.json from every commit. Retry once: `add` can race
# live Obsidian Sync writes; a second failure aborts and the next scheduled
# run catches up.
G -c core.excludesFile=/dev/null add -A -f || { sleep 5; G -c core.excludesFile=/dev/null add -A -f; }

if ! G diff --cached --quiet; then
  n=$(G diff --cached --name-only | wc -l | tr -d ' ')
  G commit -q -m "auto: $(date '+%Y-%m-%d %H:%M') ($n files)"
fi
