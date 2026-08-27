#!/bin/bash
# Tickle job: NOTIFY (never auto-apply) when a forked Obsidian plugin checkout has
# fallen behind its upstream, or has drifted off the fork conventions.
#
# Background. The vault runs a set of Obsidian plugins that are forks: a clone with
# `origin` = upstream and `fork` = nelsonlove/<repo>, carrying a few local patches on a
# long-lived `nl-main` branch. The failure mode is not that upstream moves — it is that
# the move goes UNNOTICED. On 2026-08-27 an audit found folder-notes 4 commits behind,
# meta-bind 4 behind (including a CodeMirror performance fix), tag-wrangler 1 behind,
# and execute-code sitting on a detached HEAD. None of that was visible anywhere.
#
# This job restores the human gate. It fetches, reports, and pings the comms relay. It
# never pulls, never rebases, never rebuilds, never touches the working tree. Rebasing a
# fork can conflict (it did, in tag-wrangler, on manifest.json and versions.json), so it
# stays a deliberate manual step.
#
# It also guards the two conventions the audit established, because a convention with no
# check decays back to what it replaced:
#   - no fork sits on a detached HEAD (execute-code did; the work was only reachable by SHA)
#   - no fork sits on the retired release/* or brat-* branch naming, which nl-main replaced
#
# Note what the branch check deliberately does NOT flag: a feature branch. forge, importer
# and inscribe are all legitimately parked mid-feature on feat/* and fix/* branches. A rule
# of "must be on nl-main" would nag about normal work in progress every single day, and a
# job that cries wolf daily is a job that gets muted — which costs more than the drift it
# was built to catch. Only the two retired naming patterns are treated as drift.
#
# Discovery is by shape, not by list: any repo under $REPO_ROOT with BOTH an `origin` and
# a `fork` remote is a fork under this convention. A new fork is covered the day it is
# cloned, with no edit here. That is deliberate — a hardcoded list is the thing that goes
# stale and reintroduces the exact blind spot this job exists to close.
#
# Opt-out: a repo containing a `.fork-drift-ignore` file is skipped entirely. Retired forks
# (blueprint-obsidian-plugin, fileclass — both retired 2026-08-14) are still on disk with
# both remotes, so by shape they look live. Without an opt-out they would ping forever about
# an upstream nobody intends to track again.
set -euo pipefail

# ~/.local/bin is load-bearing: comms-send.sh (#!/bin/zsh) execs `pickle`, which lives
# there. Matches comms-ping/ping.sh and vault-mcp-remote-update/run.sh.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

REPO_ROOT="${REPO_ROOT:-$HOME/repos/system}"
VAULT_PLUGINS="${VAULT_PLUGINS:-$HOME/obsidian/.obsidian/plugins}"
STATE_DIR="${STATE_DIR:-$HOME/.local/state/plugin-fork-drift}"
CONVENTION_BRANCH="${CONVENTION_BRANCH:-nl-main}"

# comms-send moved when the repo tree was reorganised into ~/repos/system/. The sibling
# jobs (vault-mcp-remote-update, task-curator) still hardcode the pre-move
# ~/repos/agent-stack path, which does not exist on this machine — they are host-gated to
# the MBP, so whether that path resolves there is unverified from here. Rather than assume
# either layout, try the known candidates in order and fail loudly if none resolve.
resolve_comms_send() {
  if [[ -n "${COMMS_SEND:-}" ]]; then printf '%s\n' "$COMMS_SEND"; return 0; fi
  local c
  for c in \
    "$HOME/repos/system/agent-stack/plugins/agent-approvals/skills/comms-send/comms-send.sh" \
    "$HOME/repos/agent-stack/plugins/agent-approvals/skills/comms-send/comms-send.sh"
  do
    [[ -x "$c" ]] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}

# Host gating is by capability, not by hostname. This job is only meaningful on the
# machine that actually holds both the vault and the checkouts, and that machine changes
# (the vault is Air-only during the rebuild and returns to the MBP after). Testing for the
# thing itself follows the vault automatically; a hardcoded hostname would need an edit
# and would be silently wrong in the window before someone made it.
[[ -d "$VAULT_PLUGINS" ]] || { echo "no vault plugin dir at $VAULT_PLUGINS — not the plugin host, nothing to do"; exit 0; }
[[ -d "$REPO_ROOT" ]]     || { echo "no repo root at $REPO_ROOT — nothing to do"; exit 0; }

# Resolve upstream's default branch. origin/HEAD is the cheap local answer and is what a
# normal clone sets. Fall back to the two common names before giving up, so a clone made
# without --set-head (or one whose origin/HEAD was pruned) is still checked rather than
# silently skipped — a skipped repo looks identical to a clean one in the output.
upstream_ref() {
  local d="$1" ref
  if ref="$(git -C "$d" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"; then
    printf '%s\n' "$ref"; return 0
  fi
  for ref in origin/main origin/master; do
    git -C "$d" rev-parse --verify --quiet "$ref" >/dev/null && { printf '%s\n' "$ref"; return 0; }
  done
  return 1
}

lines=()          # one human-readable finding per line, for the notification body
notify_keys=()    # "<repo>|<state-key>" for the repos represented in `lines`
fetch_failures=0
checked=0

for d in "$REPO_ROOT"/*/; do
  repo="$(basename "$d")"
  [[ -d "$d/.git" ]] || continue

  # The fork shape: upstream on `origin`, ours on `fork`. A repo with only `origin`
  # (obsidian-calca, dotfiles, agent-stack) is our own project, not a fork — it has no
  # upstream to drift from and must not be reported.
  git -C "$d" remote get-url origin >/dev/null 2>&1 || continue
  git -C "$d" remote get-url fork   >/dev/null 2>&1 || continue

  # Retired forks keep both remotes and so still match the shape above. Skip before the
  # fetch, not after — there is no point paying a network round trip for a repo whose
  # answer is discarded.
  [[ -f "$d/.fork-drift-ignore" ]] && { echo "$repo: .fork-drift-ignore present — skipping"; continue; }
  checked=$((checked + 1))

  # A fetch failure must surface as a job failure. Swallowing it would report "no drift"
  # for a repo we never actually checked, which is worse than no check at all.
  if ! git -C "$d" fetch --quiet --prune origin 2>/dev/null; then
    echo "WARN: git fetch failed for $repo" >&2
    fetch_failures=$((fetch_failures + 1))
    continue
  fi

  # --show-current is empty on a detached HEAD, which is exactly the condition worth
  # reporting: the checked-out work is reachable only by SHA and one `git checkout` away
  # from looking lost.
  branch="$(git -C "$d" branch --show-current)"

  if ! up="$(upstream_ref "$d")"; then
    echo "WARN: no upstream ref resolvable for $repo" >&2
    fetch_failures=$((fetch_failures + 1))
    continue
  fi

  behind="$(git -C "$d" rev-list --count "HEAD..$up")"
  ahead="$(git -C "$d" rev-list --count "$up..HEAD")"
  remote_rev="$(git -C "$d" rev-parse "$up")"

  findings=()
  # Gate on the behind-count, never on HEAD != upstream: a fork is ahead by design, so a
  # SHA comparison would alert on every repo, every day, and the job would be muted.
  if [[ "$behind" -gt 0 ]]; then
    latest="$(git -C "$d" log -1 --format='%s' "$up")"
    findings+=("$behind behind $up — latest: \"$latest\"")
  fi
  if [[ -z "$branch" ]]; then
    findings+=("DETACHED HEAD at $(git -C "$d" rev-parse --short HEAD) — no branch holds this work")
  elif [[ "$branch" == release/* || "$branch" == brat-* ]]; then
    # Retired naming only. A feature branch is normal in-progress work and is left alone —
    # see the header note on why a blanket "must be nl-main" rule would get this job muted.
    findings+=("on retired branch naming '$branch' — long-lived line should be '$CONVENTION_BRANCH', releases should be tags")
  fi

  [[ ${#findings[@]} -eq 0 ]] && continue

  # Dedupe key covers both things reported. Keyed on upstream's rev so drift re-pings only
  # when upstream actually advances (not daily for the same unchanged HEAD), and on the
  # branch so a convention break pings once and then again if it changes to something new.
  state_key="${remote_rev}|${branch:-DETACHED}"
  state_file="$STATE_DIR/$repo.rev"
  if [[ -f "$state_file" && "$(cat "$state_file")" == "$state_key" ]]; then
    echo "$repo: already notified for $state_key — skipping"
    continue
  fi

  lines+=("$repo (ahead $ahead): $(IFS='; '; echo "${findings[*]}")")
  notify_keys+=("$repo|$state_key")
done

echo "$(date '+%Y-%m-%d %H:%M') checked $checked fork repo(s), ${#lines[@]} needing notice, $fetch_failures fetch/ref failure(s)"

if [[ ${#lines[@]} -eq 0 ]]; then
  # Clear stale state for repos that are now clean, so a future drift always re-notifies
  # rather than being suppressed by a key left over from the last time they were dirty.
  for d in "$REPO_ROOT"/*/; do
    repo="$(basename "$d")"
    [[ -d "$d/.git" ]] || continue
    git -C "$d" remote get-url fork >/dev/null 2>&1 || continue
    up="$(upstream_ref "$d" 2>/dev/null)" || continue
    branch="$(git -C "$d" branch --show-current)"
    # Must mirror the reporting rules above exactly. If this test were stricter than the
    # one that raises a finding, a repo could be permanently un-clearable: never reported,
    # but never cleared either, so its stale key would suppress a genuine future drift.
    if [[ "$(git -C "$d" rev-list --count "HEAD..$up")" -eq 0 \
          && -n "$branch" \
          && "$branch" != release/* && "$branch" != brat-* ]]; then
      rm -f "$STATE_DIR/$repo.rev"
    fi
  done
  [[ "$fetch_failures" -gt 0 ]] && exit 1
  exit 0
fi

body="$(printf '%s\n' "${lines[@]}")"
MSG="Forked Obsidian plugins need attention:

$body

Nothing was changed. To update one:
  cd $REPO_ROOT/<repo> && git fetch origin && git rebase origin/HEAD
  # resolve manifest.json / versions.json conflicts by taking upstream, then re-stamp the -nl.N version
  # rebuild, then tag: git tag -a v<version> -m '<version>'
A rebase rewrites nl-main, so pushing to the fork needs --force-with-lease."

if ! COMMS="$(resolve_comms_send)"; then
  echo "comms-send not found in any known location — notice not delivered" >&2
  exit 1
fi

# Record state only on successful delivery, so a failed ping retries next run instead of
# being marked as done and swallowed.
if "$COMMS" --title "plugin forks: ${#lines[@]} need attention" --from plugin-fork-drift --message "$MSG" >/dev/null; then
  mkdir -p "$STATE_DIR"
  for k in "${notify_keys[@]}"; do
    printf '%s\n' "${k#*|}" > "$STATE_DIR/${k%%|*}.rev"
  done
  echo "notified via comms-send ($COMMS) and recorded ${#notify_keys[@]} rev(s)"
else
  echo "comms-send delivery failed — will retry next run" >&2
  exit 1
fi

[[ "$fetch_failures" -gt 0 ]] && exit 1
exit 0
