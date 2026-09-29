#!/bin/bash
# Tickle job: copy the Paperless export from Orange into iCloud Drive.
#
# Additive on purpose: no --delete. If the export on Orange is wiped or a bad
# export removes files, nothing is removed here, so the iCloud copy keeps
# every document it ever received. The price is that files of documents
# deleted in Paperless stay here too; that is the side a backup should err on.
#
# Fails loudly, never green on a missing source (the obsidian-backup rule): the
# remote export dir and its manifest.json are checked BEFORE rsync runs.
# verify.py then checks the LOCAL copy right after the copy. It does not claim
# the files are uploaded to iCloud: upload can lag and iCloud can evict files.
set -euo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

REMOTE_HOST="nelson@proxmox"
REMOTE_DIR="/var/lib/vz/paperless-export"
DEST="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Backups/paperless/export"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=15)

if [[ ! -d "$HOME/Library/Mobile Documents/com~apple~CloudDocs" ]]; then
  echo "FATAL: iCloud Drive folder is missing on this Mac; is iCloud Drive turned off?" >&2
  exit 1
fi

# Preflight: the remote export must exist, hold a non-empty manifest, and hold
# at least one other file. Any failure here, SSH included, exits non-zero.
if ! ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" \
     "test -d '$REMOTE_DIR' && test -s '$REMOTE_DIR/manifest.json' && test -n \"\$(find '$REMOTE_DIR' -type f ! -name manifest.json -print -quit)\""; then
  echo "FATAL: $REMOTE_HOST:$REMOTE_DIR is missing, has no manifest.json, or holds no files (or SSH failed). Check /etc/cron.d/paperless-export and /var/log/paperless-export.log on Orange." >&2
  exit 1
fi

mkdir -p "$DEST"
rsync -rt --partial -e "ssh ${SSH_OPTS[*]}" "$REMOTE_HOST:$REMOTE_DIR/" "$DEST/"

exec python3 "$(dirname "$0")/verify.py" "$DEST"
