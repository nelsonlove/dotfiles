#!/bin/bash
# Tickle job: NOTIFY (do not auto-apply) when the vault-mcp remote proxy's checkout
# has fallen behind origin/main.
#
# The proxy (com.nelson.vault-mcp-remote LaunchAgent) runs packages/server/dist/front.js
# out of the repo below. The Obsidian plugin ships releases faster than this checkout
# is hand-updated, so the running server drifts behind — and the real failure mode is
# that the drift goes UNNOTICED (it sat 6 commits / 2 releases behind before anyone
# looked). This job restores the human gate: it only detects + pings the comms/pickle
# relay, leaving the actual pull/rebuild/restart to a deliberate manual step. It never
# touches the working tree or the service.
#
# Host-gating is done by the job's on-host.sh trigger (MBP only), so this assumes it's
# on the right machine. Deliberately NOT auto-deploying main HEAD — see PR #17.
set -euo pipefail

# ~/.local/bin is load-bearing: comms-send.sh (#!/bin/zsh) execs `pickle`, which lives
# there. This matches comms-ping/ping.sh, NOT vault-backup (which never calls comms-send).
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

REPO="$HOME/repos/obsidian-vault-mcp-plugin"
# Env-overridable, matching the task-curator sibling — one idiom for the shared path.
COMMS_SEND="${COMMS_SEND:-$HOME/repos/agent-stack/plugins/agent-approvals/skills/comms-send/comms-send.sh}"
STATE_DIR="$HOME/.local/state/vault-mcp-remote"
STATE_FILE="$STATE_DIR/drift-notified-rev"   # last remote rev we already pinged about

[[ -d "$REPO/.git" ]] || { echo "repo not present at $REPO — nothing to check"; exit 0; }
cd "$REPO"

# Guard the fetch: a transient network/auth hiccup must be signalled as a job FAILURE
# (Tickle logs it), never silently swallowed by set -e as if there were no drift.
if ! git fetch --quiet origin main; then
  echo "$(date '+%Y-%m-%d %H:%M') git fetch failed — cannot check drift this run" >&2
  exit 1
fi

# Gate on the actual behind-count, not raw SHA inequality: a locally-ahead or diverged
# checkout has HEAD != origin/main but `HEAD..origin/main` == 0, and must NOT alert.
n="$(git rev-list --count HEAD..origin/main)"
if [[ "$n" -eq 0 ]]; then
  echo "$(date '+%Y-%m-%d %H:%M') vault-mcp proxy not behind origin/main — no notice"
  rm -f "$STATE_FILE"   # clear so a future drift always re-notifies
  exit 0
fi

local_rev="$(git rev-parse HEAD)"
remote_rev="$(git rev-parse origin/main)"

# Dedupe: one standing notice per drift target. Re-ping only when origin advances to a
# new rev (drift grew), not every single day for the same unchanged remote HEAD.
if [[ -f "$STATE_FILE" && "$(cat "$STATE_FILE")" == "$remote_rev" ]]; then
  echo "$(date '+%Y-%m-%d %H:%M') already notified for $remote_rev ($n behind) — skipping"
  exit 0
fi

latest="$(git log -1 --format='%s' origin/main)"
echo "$(date '+%Y-%m-%d %H:%M') vault-mcp proxy $n commit(s) behind (${local_rev:0:7} -> ${remote_rev:0:7})"

MSG="vault-mcp remote proxy is $n commit(s) behind origin/main (${local_rev:0:7} -> ${remote_rev:0:7}). Latest: \"$latest\". To update: cd $REPO && git pull --ff-only && npm install && npm run build --workspace packages/core && npm run build --workspace packages/server && launchctl kickstart -k gui/\$(id -u)/com.nelson.vault-mcp-remote"

if [[ ! -x "$COMMS_SEND" ]]; then
  echo "comms-send not found/executable at $COMMS_SEND — notice not delivered" >&2
  exit 1
fi

# Only record the notified rev if delivery actually succeeded, so a failed ping retries
# next run instead of being marked done.
if "$COMMS_SEND" --title "vault-mcp proxy $n behind" --from vault-mcp-drift --message "$MSG" >/dev/null; then
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$remote_rev" > "$STATE_FILE"
  echo "notified via comms-send and recorded rev $remote_rev"
else
  echo "comms-send delivery failed — will retry next run" >&2
  exit 1
fi
