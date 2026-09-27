#!/bin/bash
# [test artifact — safe to delete] Does ONE shared file resolve to the same place from BOTH install roads?
#
# Package 4 unifies the 69-line pause-flag parser duplicated in claude/hooks/pause-guard.sh and
# tickle/scripts/_lib/pause-gate.sh. The ruling attaches a condition: a single sourced file must be
# PROVEN to resolve from both install roads before anything is unified, because the two halves install
# differently — the hook through the ~/.claude/hooks symlink, the gate through tickle's own config home.
# If it does not resolve from both, the copies stay and the package adds a generated-from marker plus a
# drift test instead. This script is that proof, run rather than reasoned. It sources nothing, runs no
# hook, and changes nothing.
#
# WHAT THE FIRST VERSION OF THIS SCRIPT GOT WRONG, kept because it is the finding. It asked whether the
# two roads compute the same REPO_ROOT from `$script_dir/../..`, and they do not:
#   the hook is at  <repo>/claude/hooks/          so ../..     is <repo>            — correct
#   the gate is at  <repo>/tickle/scripts/_lib/   so ../..     is <repo>/tickle     — NOT the repo root
# The gate sits three levels down, not two. That is not a reason to keep the duplication; it means the
# two callers need DIFFERENT relative depths to name the SAME file. So the question to ask is not "do the
# roads agree on a root" but "does the candidate file resolve to one identical absolute path from each
# road, using each road's own correct depth". That is what this version asks.
set -u

CANDIDATE="${1:-claude/lib/pause-flag.sh}"   # the shared file's path, relative to the REPO ROOT

say() { printf '%s\n' "$*" >&2; }            # log to stderr, so a captured value is only the value
hr()  { printf -- '%s\n' "---------------------------------------------------------------" >&2; }

# The two-step resolution the bin scripts already use, and why it is two steps: the first `pwd -P`
# resolves a symlinked directory BEFORE `..` is applied, so the second `cd` walks up the real path. A
# naive `cd "$(dirname "$0")/../.."` applies `..` logically to the symlinked path and lands elsewhere.
# wake-session.sh:94 states the intent. `$2` is how many levels up the repo root is from the script.
root_from() {  # $1 = the path a script sees as "$0"; $2 = levels up to the repo root. prints the root.
  local zero="$1" up="$2" sd rr rel=""
  sd=$(cd "$(dirname "$zero")" 2>/dev/null && pwd -P) || sd=""
  [ -n "$sd" ] || { say "  script_dir : UNRESOLVED (cd failed)"; return 1; }
  say "  script_dir : $sd"
  local i=0; while [ "$i" -lt "$up" ]; do rel="$rel/.."; i=$((i + 1)); done
  say "  levels up  : $up  (\$script_dir$rel)"
  rr=$(cd "$sd$rel" 2>/dev/null && pwd -P) || rr=""
  [ -n "$rr" ] || { say "  repo root  : UNRESOLVED (cd failed)"; return 1; }
  say "  repo root  : $rr"
  printf '%s' "$rr"
}

report_candidate() {  # $1 = repo root, $2 = label
  local target="$1/$CANDIDATE"
  say "  candidate  : $target"
  if [ -f "$target" ]; then
    say "  state      : PRESENT and readable — $2 can source it today"
  elif [ -d "$(dirname "$target")" ]; then
    say "  state      : not created yet; its directory exists, so $2 would reach it here"
  else
    say "  state      : not created yet, nor its directory (expected before the package lands)"
  fi
}

say "Shared-library path proof for: $CANDIDATE"
say "Run at: $(date '+%Y-%m-%dT%H:%M:%S %Z')"
hr

# --- road 1: the session-side hook, invoked as ~/.claude/hooks/<name>.sh ---------------------------
say "ROAD 1 — the hook, as Claude Code invokes it"
HOOK_ZERO="$HOME/.claude/hooks/pause-guard.sh"
say "  \$0 would be: $HOOK_ZERO"
rr1=""
if [ -e "$HOOK_ZERO" ]; then
  ls -ld "$HOME/.claude/hooks" 2>/dev/null | sed 's/^/  symlink    : /' >&2
  rr1=$(root_from "$HOOK_ZERO" 2) && report_candidate "$rr1" "the hook"
else
  say "  MISSING — no hook at that path, so road 1 cannot be measured here"
fi
hr

# --- road 2: the tickle script trigger, through TICKLE_CONFIG_HOME ---------------------------------
say "ROAD 2 — the tickle script trigger, through TICKLE_CONFIG_HOME"
rr2=""
if [ -n "${TICKLE_CONFIG_HOME:-}" ]; then
  say "  TICKLE_CONFIG_HOME: $TICKLE_CONFIG_HOME"
  GATE_ZERO="$TICKLE_CONFIG_HOME/scripts/_lib/pause-gate.sh"
  say "  a job's @config/scripts/_lib/pause-gate.sh is: $GATE_ZERO"
  if [ -e "$GATE_ZERO" ]; then
    # three levels: _lib -> scripts -> tickle -> repo root
    rr2=$(root_from "$GATE_ZERO" 3) && report_candidate "$rr2" "the gate"
  else
    say "  MISSING — no gate at that path, so road 2 cannot be measured here"
  fi
else
  say "  NOT SET in this environment. It is set in the interactive shell and in tickle's own"
  say "  environment, so a bare run here cannot prove road 2 — re-run with it exported."
fi
hr

say "VERDICT"
if [ -n "$rr1" ] && [ -n "$rr2" ]; then
  say "  hook road resolves the shared file to: $rr1/$CANDIDATE"
  say "  gate road resolves the shared file to: $rr2/$CANDIDATE"
  if [ "$rr1" = "$rr2" ]; then
    say "  PROVEN. Both roads name ONE identical absolute path, so a single shared file at"
    say "  \$REPO_ROOT/$CANDIDATE serves both. Package 4 may unify."
    say "  CARRY THIS FORWARD: the depths differ — the hook is 2 levels up, the gate is 3. Each caller"
    say "  must use its own depth; a copied line will resolve to the wrong place and fail silently at"
    say "  source time, which on the gate means exit 2 and a job that does not run."
    exit 0
  fi
  say "  NOT PROVEN. The two roads name different absolute paths, so one repo-relative file cannot"
  say "  serve both. Keep both copies, add the generated-from marker, and add the drift test."
  exit 1
fi
say "  INCOMPLETE — one or both roads could not be measured here (see above). This is a failure to"
say "  measure, not a finding about the design. Re-run where both roads exist."
exit 2
