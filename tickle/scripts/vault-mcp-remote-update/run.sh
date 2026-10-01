#!/bin/bash
# Tickle job: NOTIFY (do not auto-apply) when the vault-mcp remote proxy's checkout has fallen behind origin/main.
#
# The proxy (the com.nelson.vault-mcp-remote LaunchAgent) runs packages/server/dist/front.js out of a checkout of the obsidian-mcp-suite repo. The plugin ships releases faster than that checkout is hand-updated, so the running server drifts behind, and the real failure is that the drift goes UNNOTICED (it sat 6 commits / 2 releases behind before anyone looked). This job restores the human gate: it only detects and shows a plain notice (_lib/notice.sh), and leaves the pull, rebuild and restart to a deliberate manual step. It never touches the working tree or the service. Host gating is done by the job's gated.sh trigger. Deliberately NOT auto-deploying main HEAD: see PR #17.
#
# THE CHECKOUT is the one the proxy actually runs: the path before `/packages/server/dist/front.js` in the INSTALLED LaunchAgent (~/Library/LaunchAgents/com.nelson.vault-mcp-remote.plist). A hardcoded path went dead when the repo was renamed (obsidian-vault-mcp-plugin → obsidian-mcp-suite), and checking a different checkout from the one that runs would report the wrong drift. VAULT_MCP_REPO overrides it. A checkout that cannot be found is a FAILED run, not a quiet "nothing to check": on the host this job is gated to, the proxy should be there.
#
# THE PUBLIC HOSTNAME of the endpoint is private config, not in the job (Nelson's "A then", 2026-10-01, after the public-repo audit): one line in ~/.config/vault-mcp-remote/public-hostname (example: public-hostname.example beside this script). The notice names it. A missing or empty file FAILS the run loudly, but only after the drift check has run, so a missing name never switches the check off: the run shows a second notice that says which file to create, and exits 1.
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
NOTICE="$(cd "$(dirname "$0")/../_lib" && pwd -P)/notice.sh"
PLIST="${VAULT_MCP_PLIST:-$HOME/Library/LaunchAgents/com.nelson.vault-mcp-remote.plist}"
HOST_FILE="${VAULT_MCP_HOST_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/vault-mcp-remote/public-hostname}"
STATE_DIR="${VAULT_MCP_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/vault-mcp-remote}"
STATE_FILE="$STATE_DIR/drift-notified-rev"   # last remote rev we already gave notice about

stamp() { date '+%Y-%m-%d %H:%M'; }
fail() { echo "$(stamp) FAILED — $*" >&2; exit 1; }

# The public hostname, from private config. Read first; a missing one is reported after the check (see the header).
host=""; host_problem=""
if [[ ! -r "$HOST_FILE" ]]; then host_problem="$HOST_FILE is missing; create it with the endpoint's public hostname on one line (see public-hostname.example)"
else host="$(head -n 1 "$HOST_FILE" | tr -d '[:space:]')"; [[ -n "$host" ]] || host_problem="$HOST_FILE is empty; put the endpoint's public hostname on its first line"; fi
finish() {   # exit for every path after the check: a host problem turns a good run into a loud failure
  if [[ -n "$host_problem" ]]; then
    "$NOTICE" vault-mcp-remote "vault-mcp-remote-update: private config missing" "$host_problem" || true
    fail "$host_problem"
  fi
  exit 0
}

# The checkout the proxy runs.
if [[ -n "${VAULT_MCP_REPO:-}" ]]; then
  REPO="$VAULT_MCP_REPO"
else
  [[ -r "$PLIST" ]] || fail "no installed LaunchAgent at $PLIST to read the proxy's checkout from (set VAULT_MCP_REPO to override)"
  # plutil reads XML and binary plists alike; the ProgramArguments are joined and ~ and $HOME expanded before the path is taken.
  args="$(/usr/bin/plutil -extract ProgramArguments json -o - "$PLIST" 2>/dev/null)" || fail "cannot read ProgramArguments from $PLIST"
  args="$(printf '%s' "$args" | sed -e 's#\\/#/#g' -e "s#\\\$HOME#$HOME#g" -e "s#~/#$HOME/#g")"
  REPO="$(printf '%s' "$args" | grep -oE '/[^"<> ;]+/packages/server/dist/front\.js' | head -n 1 | sed 's|/packages/server/dist/front\.js$||' || true)"
  [[ -n "$REPO" ]] || fail "cannot find the checkout path (…/packages/server/dist/front.js) in $PLIST"
fi
[[ -d "$REPO/.git" || -f "$REPO/.git" ]] || fail "the proxy's checkout $REPO is not a git checkout (the LaunchAgent may point at an old path)"
cd "$REPO"

# Guard the fetch: a transient network or auth hiccup is a job FAILURE (tickle logs it), never swallowed as if there were no drift.
git fetch --quiet origin main || fail "git fetch failed in $REPO — cannot check drift this run"

# Gate on the behind-count, not raw SHA inequality: a locally-ahead or diverged checkout has HEAD != origin/main but `HEAD..origin/main` == 0, and must NOT alert.
n="$(git rev-list --count HEAD..origin/main)"
if [[ "$n" -eq 0 ]]; then
  echo "$(stamp) vault-mcp proxy ($REPO) not behind origin/main — no notice"
  [[ -f "$STATE_FILE" ]] && /usr/bin/trash "$STATE_FILE" 2>/dev/null   # clear so a future drift always gives notice again
  finish
fi

local_rev="$(git rev-parse HEAD)"
remote_rev="$(git rev-parse origin/main)"

# Dedupe: one standing notice per drift target. Notice again only when origin advances to a new rev, not every day for the same remote HEAD.
if [[ -f "$STATE_FILE" && "$(cat "$STATE_FILE")" == "$remote_rev" ]]; then
  echo "$(stamp) already gave notice for $remote_rev ($n behind) — skipping"
  finish
fi

latest="$(git log -1 --format='%s' origin/main)"
echo "$(stamp) vault-mcp proxy $n commit(s) behind (${local_rev:0:7} -> ${remote_rev:0:7})"

MSG="The vault-mcp remote proxy behind ${host:-(the endpoint: hostname not configured)} is $n commit(s) behind origin/main (${local_rev:0:7} -> ${remote_rev:0:7}). Latest: \"$latest\".
To update: cd $REPO && git pull --ff-only && npm install && npm run build --workspace packages/core && npm run build --workspace packages/server && launchctl kickstart -k gui/\$(id -u)/com.nelson.vault-mcp-remote"

# Record the notified rev only after a notice was shown, so a failed one retries next run.
"$NOTICE" vault-mcp-remote "vault-mcp proxy $n behind" "$MSG" || fail "the notice could not be shown — will retry next run"
mkdir -p "$STATE_DIR"
printf '%s\n' "$remote_rev" > "$STATE_FILE"
echo "$(stamp) notice shown and rev $remote_rev recorded"
finish
