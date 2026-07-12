#!/usr/bin/env bash
# protect-new-repo.sh — PostToolUse hook for `gh repo create`.
#
# When Claude Code runs a `gh repo create` Bash command and it succeeds,
# this hook auto-applies the "Protect main" branch-protection ruleset to
# the new repo (block delete, block force-push, require PR; admin bypass).
#
# Silently no-ops if:
#   - The Bash command wasn't `gh repo create` (the `if` filter in
#     settings.json should already prevent this hook from being invoked,
#     but defense in depth)
#   - The command failed (no GitHub URL in stdout)
#   - The repo is private on a free-tier account (GitHub returns 422
#     "Upgrade to GitHub Pro"; not actionable from here)

input=$(cat)

# Confirm this is a Bash tool event (defensive — the hook config matcher
# already restricts to Bash, but a misconfigured settings.json could
# invoke this on other tools).
[ "$(jq -r '.tool_name // empty' <<<"$input")" = "Bash" ] || exit 0

# `gh repo create` prints the new repo URL on stdout: `https://github.com/owner/repo`
url=$(jq -r '.tool_response.stdout // empty' <<<"$input" \
        | grep -oE 'https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+' \
        | head -1)
[ -n "$url" ] || exit 0  # creation failed or no URL emitted

# Strip protocol/host → owner/repo
repo="${url#https://github.com/}"
repo="${repo%/}"

# Apply ruleset. Capture both stdout (success body) and stderr (error)
# so we can decide whether to surface the success notice.
result=$(gh api -X POST "repos/${repo}/rulesets" --input - 2>&1 <<EOF
{
  "name": "Protect main",
  "target": "branch",
  "enforcement": "active",
  "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
  "rules": [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {"type": "pull_request", "parameters": {"required_approving_review_count": 0, "dismiss_stale_reviews_on_push": false, "require_code_owner_review": false, "require_last_push_approval": false, "required_review_thread_resolution": false}}
  ],
  "bypass_actors": [{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}]
}
EOF
)

# Success body contains an `"id"` field. On anything else, surface a warning on
# stderr (Claude Code shows it) rather than swallowing it — an invalid/expired gh
# token or a network error would otherwise leave the new repo unprotected with no
# signal. Still exit 0: a PostToolUse hook must not fail the Bash tool call.
if printf '%s' "$result" | grep -q '"id"'; then
  printf '[hook] applied "Protect main" ruleset to %s\n' "$repo" >&2
elif printf '%s' "$result" | grep -q 'Upgrade to\|upgrade your plan'; then
  : # private repo on a free-tier account — branch protection needs Pro; not actionable, stay quiet
else
  printf '[hook] WARNING: could not apply "Protect main" ruleset to %s — branch left UNPROTECTED. gh response:\n%s\n' "$repo" "$result" >&2
fi
exit 0
