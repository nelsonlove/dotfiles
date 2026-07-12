#!/bin/zsh
# Tickle job: daily contacts refresh (was launchd com.nelson.refresh-contacts).
# Preserves the original env, --quiet flag, and the ~/Library/Logs log path so
# anything that reads that log keeps working. Tickle also keeps its own per-run
# journal (`tickle logs refresh-contacts`).
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
export PYTHONUNBUFFERED=1
LOG="$HOME/Library/Logs/refresh-contacts.log"

"$HOME/.local/bin/refresh-contacts" --quiet 2>&1 | tee -a "$LOG"
exit ${pipestatus[1]}   # zsh: propagate refresh-contacts' exit, not tee's
