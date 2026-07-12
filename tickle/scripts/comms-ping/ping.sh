#!/bin/zsh
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"
CS="$HOME/repos/agent-stack/plugins/agent-approvals/skills/comms-send/comms-send.sh"
T=$(date +%H:%M)
"$CS" --title "comms ping $T" --from heartbeat --message "5-minute gauge ping at $T — push relay liveness check." >/dev/null
echo pinged $T
