#!/bin/bash
# Tickle job: auto-commit the Obsidian vault into an external, local-only backup
# repo. Safety net for Blueprint / bulk-apply edits. NEVER pushes; only ever
# add/commit, and never checks out into the vault work-tree.
#
# Host-gating is done by the job's on-host.sh trigger (MBP only), so this script
# assumes it's on the right machine. It self-inits the bare repo so the backup
# stands itself up on a fresh MBP with no manual setup.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

GITDIR="$HOME/vault-backup.git"; WT="$HOME/obsidian"
G(){ git --git-dir="$GITDIR" --work-tree="$WT" "$@"; }

[[ -d "$WT" ]] || exit 0                 # vault not present — nothing to back up
[[ -d "$GITDIR" ]] || git init --bare -q "$GITDIR"

G add -A
if ! G diff --cached --quiet; then
  n=$(G diff --cached --name-only | wc -l | tr -d ' ')
  G commit -q -m "auto: $(date '+%Y-%m-%d %H:%M') ($n files)"
fi
