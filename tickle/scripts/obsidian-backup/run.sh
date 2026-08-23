#!/bin/bash
# Tickle job: auto-commit ~/obsidian (the Assent-era vault: live layer, _hold
# generations, _keep fleet surfaces, the Assent design doc) into an external,
# local-only backup repo. Bare repo lives OUTSIDE the vault on purpose (a .git
# inside a vault was tried and reverted twice in prior generations).
#
# Unlike the retired obsidian-new-backup job, a missing target FAILS LOUDLY:
# the 2026-08-08 system review found the old [[ -d ]] || exit 0 guard turned
# "vault deleted" into months of green runs. If the vault moves again, this
# job should scream, not nod.
set -euo pipefail
if [[ ! -d "$HOME/obsidian" ]]; then
  echo "FATAL: ~/obsidian does not exist — vault moved or deleted; fix or retire this job." >&2
  exit 1
fi
# obsidian-governor#337 (Nelson's ruling, 2026-08-23): the Governor standing
# chain — the git store that makes admission claims authoritative — lives
# OUTSIDE the vault at ~/.claude/governor/history, and losing it silently
# reads as "nothing is admitted" rather than erroring. It comes under this
# job's coverage in its own bare repo. The observation replay payloads
# (~/.claude/governor/observations, a SIBLING dir) are deliberately excluded
# by scope — a size call (they can grow toward their cap), not a privacy one.
# The store is a plain gitdir, so its files back up as ordinary content and
# restore is a literal copy-back — restoring authority, never reconstructing
# it. Missing dir fails LOUDLY, same doctrine as the vault guard above: after
# the authority cutover this directory IS standing, and a green run over its
# absence would hide exactly the loss #337 exists to prevent.
# The vault backup runs FIRST, guard second (review finding): a missing
# governor dir must scream, but it must not suppress the vault safety net —
# the job still exits non-zero and the run log carries the FATAL.
"$(dirname "$0")/../_lib/git-autocommit.sh" "$HOME/obsidian-backup.git" "$HOME/obsidian"
if [[ ! -d "$HOME/.claude/governor/history" ]]; then
  echo "FATAL: ~/.claude/governor/history does not exist — the Governor standing chain moved or was deleted (obsidian-governor#337); investigate before trusting this backup." >&2
  exit 1
fi
# Present-but-EMPTY is the same emergency wearing green: the helper would
# find nothing to add and the run would pass — "backed up, 0 files" is the
# failure that reads as success. The store always holds at least its
# vault-slug gitdir (config + HEAD) once created, so zero files means wiped.
if [[ -z "$(find "$HOME/.claude/governor/history" -type f 2>/dev/null | head -1)" ]]; then
  echo "FATAL: ~/.claude/governor/history exists but holds no files — the standing chain store was emptied (obsidian-governor#337); investigate before trusting this backup." >&2
  exit 1
fi
# Restore note: a backup taken before the chain's first commit holds only
# config+HEAD (git does not track empty dirs) — on copy-back, `mkdir -p
# objects refs` inside the store before git will read it.
exec "$(dirname "$0")/../_lib/git-autocommit.sh" "$HOME/governor-history-backup.git" "$HOME/.claude/governor/history"
