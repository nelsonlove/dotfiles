#!/bin/bash
# Tickle job: NOTIFY (do not auto-apply) when the vault-mcp remote proxy's checkout
# has fallen behind origin/main.
#
# The proxy (com.nelson.vault-mcp-remote LaunchAgent) runs packages/server/dist/front.js
# out of the repo below. The Obsidian plugin ships releases faster than this checkout
# is hand-updated, so the running server drifts behind — and the real failure mode is
# that the drift goes UNNOTICED (it sat 6 commits / 2 releases behind before anyone
# looked). This job restores the human gate: it only detects + pings the comms relay,
# leaving the actual pull/rebuild/restart to a deliberate manual step. It never touches
# the working tree or the service.
#
# Host-gating is done by the job's on-host.sh trigger (MBP only), so this assumes it's
# on the right machine. Deliberately NOT auto-deploying main HEAD — see PR discussion.
set -euo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

REPO="$HOME/repos/obsidian-vault-mcp-plugin"
COMMS_SEND="$HOME/repos/agent-stack/plugins/agent-approvals/skills/comms-send/comms-send.sh"

[[ -d "$REPO/.git" ]] || { echo "repo not present at $REPO — nothing to check"; exit 0; }
cd "$REPO"

git fetch --quiet origin main

local_rev="$(git rev-parse HEAD)"
remote_rev="$(git rev-parse origin/main)"
if [[ "$local_rev" == "$remote_rev" ]]; then
  echo "$(date '+%Y-%m-%d %H:%M') vault-mcp proxy current ($local_rev) — no notice"
  exit 0
fi

n="$(git rev-list --count HEAD..origin/main)"
short_local="$(git rev-parse --short HEAD)"
short_remote="$(git rev-parse --short origin/main)"
latest="$(git log -1 --format='%s' origin/main)"
echo "$(date '+%Y-%m-%d %H:%M') vault-mcp proxy $n commit(s) behind ($short_local -> $short_remote)"

MSG="vault-mcp remote proxy is $n commit(s) behind origin/main ($short_local -> $short_remote). Latest: \"$latest\". To update: cd $REPO && git pull --ff-only && npm install && npm run build --workspace packages/core && npm run build --workspace packages/server && launchctl kickstart -k gui/\$(id -u)/com.nelson.vault-mcp-remote"

if [[ -x "$COMMS_SEND" ]]; then
  "$COMMS_SEND" --title "vault-mcp proxy $n behind" --from vault-mcp-drift --message "$MSG" >/dev/null
  echo "notified via comms-send"
else
  echo "comms-send not found at $COMMS_SEND — notice not delivered" >&2
  exit 1
fi
