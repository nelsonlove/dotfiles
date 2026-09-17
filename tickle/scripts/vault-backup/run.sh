#!/bin/bash
# Tickle job: auto-commit the Obsidian vault into an external, local-only backup
# repo. Safety net for Blueprint / bulk-apply edits. NEVER pushes; only ever
# add/commit, and never checks out into the vault work-tree.
#
# Host-gating is done by the job's on-host.sh trigger (MBP only), so this script
# assumes it's on the right machine. It self-inits the bare repo so the backup
# stands itself up on a fresh MBP with no manual setup.
#
# Unlike the earlier version of this script, a missing target FAILS LOUDLY: the
# obsidian-backup job scar (2026-08-08 system review) found a bare [[ -d ]] ||
# exit 0 guard turned "vault deleted" into months of green runs. If the vault
# moves again, this job should scream, not nod.
set -euo pipefail
if [[ ! -d "$HOME/obsidian" ]]; then
  echo "FATAL: ~/obsidian does not exist — vault moved or deleted; fix or retire this job." >&2
  exit 1
fi
exec "$(dirname "$0")/../_lib/git-autocommit.sh" "$HOME/vault-backup.git" "$HOME/obsidian"
