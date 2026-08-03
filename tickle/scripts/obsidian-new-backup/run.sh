#!/bin/bash
# Tickle job: auto-commit ~/obsidian-new (the ground-up vault rebuild) into an
# external, local-only backup repo. The bare repo lives OUTSIDE the vault on
# purpose: a .git inside obsidian-new was tried and reverted (2026-08-02).
#
# Host-gating is done by the job's on-host.sh trigger (Air only), so this
# script assumes it's on the right machine. All mechanics live in
# _lib/git-autocommit.sh, shared with the MBP vault-backup job.
set -euo pipefail
exec "$(dirname "$0")/../_lib/git-autocommit.sh" "$HOME/obsidian-new-backup.git" "$HOME/obsidian-new"
