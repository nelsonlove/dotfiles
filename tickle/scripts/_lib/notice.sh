#!/bin/bash
# _lib/notice.sh <job-id> <title> <message> — a plain notice for a tickle job, in place of the retired Pickle relay (comms-send).
#
# Nelson's "A then" on the tickle plan (2026-10-01): Pickle is parked, so a job that must tell him something shows a macOS notification and keeps the full text on disk.
#   1. The full message goes to `${XDG_STATE_HOME:-~/.local/state}/<job-id>/latest-notice.md`, with a stamp from `date`, replacing the last one. tickle also keeps the job's stdout.
#   2. A macOS notification shows the title and the first line, with `osascript -e 'display notification …'` (Standard Additions, not System Events). A job under the tickle LaunchAgent runs in the user's GUI session, so it can show one.
# Exit 0 when the file was written and osascript accepted the notification; any failure is exit 1 with the reason on stderr. LIMIT: macOS gives no sign whether the notification was actually SEEN (notifications for Script Editor turned off, Focus on): osascript exits 0 either way. So the file is the record a caller can rely on, and the first run on a new Mac should be watched once by hand (macOS asks to allow notifications then).
#
# NOTICE_CMD replaces the osascript call (tests; it gets the title and the line as $1 and $2). NOTICE_STATE_DIR replaces the state root.
set -u
if [ "$#" -ne 3 ] || [ -z "$1" ] || [ -z "$2" ]; then echo "usage: notice.sh <job-id> <title> <message>" >&2; exit 1; fi
job="$1"; title="$2"; message="$3"
dir="${NOTICE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}}/$job"
mkdir -p "$dir" || { echo "notice: cannot create $dir" >&2; exit 1; }
tmp=$(mktemp "$dir/.latest-notice.XXXXXX") || { echo "notice: cannot write in $dir" >&2; exit 1; }
printf '# %s\n\n%s\n\n%s\n' "$title" "$(date '+%Y-%m-%d %H:%M')" "$message" > "$tmp" && mv "$tmp" "$dir/latest-notice.md" \
  || { /usr/bin/trash "$tmp" 2>/dev/null; echo "notice: cannot write $dir/latest-notice.md" >&2; exit 1; }
# Cut by CHARACTERS: under launchd no locale is set, and a byte cut can split a UTF-8 character, which osascript then rejects.
first=$(printf '%s\n' "$message" | head -n 1 | LC_ALL=en_US.UTF-8 cut -c1-200)
if [ -n "${NOTICE_CMD:-}" ]; then
  "$NOTICE_CMD" "$title" "$first" || { echo "notice: NOTICE_CMD failed" >&2; exit 1; }
else
  # The two strings go in as osascript arguments, never pasted into the script text, so a quote in them cannot break it.
  /usr/bin/osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' "$title" "$first. Full text: $dir/latest-notice.md" >/dev/null \
    || { echo "notice: osascript could not show the notification" >&2; exit 1; }
fi
echo "notice shown; full text in $dir/latest-notice.md"
