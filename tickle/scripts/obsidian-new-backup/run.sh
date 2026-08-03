#!/bin/bash
# Tickle job: auto-commit ~/obsidian-new (the ground-up vault rebuild) into an
# external, local-only backup repo. Safety net for migration / Blueprint /
# bulk-apply edits. NEVER pushes; only ever add/commit, and never checks out
# into the vault work-tree. The bare repo lives OUTSIDE the vault on purpose:
# a .git inside obsidian-new was tried and reverted (2026-08-02).
#
# Host-gating is done by the job's on-host.sh trigger (Air only), so this
# script assumes it's on the right machine. It self-inits the bare repo so the
# backup stands itself up with no manual setup.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

GITDIR="$HOME/obsidian-new-backup.git"; WT="$HOME/obsidian-new"
G(){ git --git-dir="$GITDIR" --work-tree="$WT" "$@"; }

[[ -d "$WT" ]] || exit 0                 # vault not present — nothing to back up
[[ -d "$GITDIR" ]] || git init --bare -q "$GITDIR"

G add -A
if ! G diff --cached --quiet; then
  n=$(G diff --cached --name-only | wc -l | tr -d ' ')
  G commit -q -m "auto: $(date '+%Y-%m-%d %H:%M') ($n files)"
fi
