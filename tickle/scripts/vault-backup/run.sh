#!/bin/bash
# Tickle job: auto-commit the Obsidian vault into an external, local-only
# backup repo. Safety net for Blueprint / bulk-apply edits.
#
# Host-gating is done by the job's on-host.sh trigger (MBP only), so this
# script assumes it's on the right machine. All mechanics live in
# _lib/git-autocommit.sh, shared with the Air obsidian-new-backup job.
set -euo pipefail
exec "$(dirname "$0")/../_lib/git-autocommit.sh" "$HOME/vault-backup.git" "$HOME/obsidian"
