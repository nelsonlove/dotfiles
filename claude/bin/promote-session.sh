#!/usr/bin/env bash
# promote-session.sh — promote or demote a running Claude Code fleet session to another rank.
#
# Nelson's rule (2026-09-22): "agents can promote or demote up to the rank below them; a captain
# may promote to commander but never to captain, only i can do that." Rule 19 of 01.65.
#
# What Claude Code 2.1.266 actually does, tested 2026-09-22 on throwaway sessions:
#   * `claude --bg --resume <sessionId> --agent <rank> --name "<name>"` with ANY flag starts a
#     COPY under a NEW id ("keeps its own saved options, so the flags you passed started a copy").
#     The copy carries the whole conversation; the old id stays stopped as the record.
#   * The persona only changes with `--system-prompt-snapshot off`; the default snapshot replays
#     the old system prompt on every resume until the conversation is compacted.
#   * There is no rename command for a running session, so a rank change is a fork under a new
#     name. This script does the sequence in the right order and records the act.
#
# Usage:
#   promote-session.sh --session <id|sessionId> --to <agent> --name "<code-ship> <name>" \
#       --by "<promoter session name>" --why "<reason>" [--ship <code>] [--prompt "<text>"] \
#       [--log <path>] [--pause-note <path>] [--dry-run]
#
#   --to     one of: commander, lieutenant-commander, lieutenant-commander-repository,
#            lieutenant, lieutenant-repository. Never captain or admiral: only Nelson makes those.
#   --name   the new display name, in the coded form: the rank code and the ship code together,
#            e.g. "[C2-CC] dotfiles". The rank code must match --to, and the ship code must be the
#            promoter's own (see --ship and the FL rule below).
#   --by     the promoter's own session name, e.g. "[C0-CC] claude code"; its rank code is the rank
#            the rule is checked against, and its ship code is the ship the new name carries.
#   --ship   the ship code for the new name when --by does not carry one, or FL to make the session
#            float on purpose. The ships are the ones `KNOWN_SHIPS` lists in `_fleet-ranks.sh`,
#            where each one's ruling is recorded; FL is not a ship but the marker
#            of a floating session, shared across captains, and it is accepted here as a code
#            because it is what such a name carries. Never guessed: a wrong code files a session
#            under the wrong captain, and only Nelson can rename it back.
#            (The refusal when --by carries no ship code names every code, in the captain's own
#            wording, corrected by him on 2026-09-26 once HS existed; the codes come from
#            `ships_in_words`, so a new ship reaches the sentence with no edit here.)
#   --log    the cross-session log to append the record to (default: the fleet log).
#   --jobs-dir  where Claude Code's job state lives, which is where the TARGET's rank is read from
#              (`<id>/state.json`, key `template`). For testing only, and REFUSED unless it resolves under
#              /tmp or the system temp directory — see the leash below. It is what lets a battery exercise a
#              captain-ranked target without dispatching a captain or naming a throwaway as one.
#   --pause-note  the Pause note the gate reads. For testing only; an ordinary run reads the fleet's
#            own note, and PAUSE_NOTE is deliberately NOT inherited from the environment.
#   --dry-run  print the plan and stop before touching anything.
#   -h, --help  print this header.
#
# The rear admiral, `[A0]`, added 2026-09-27: the session Nelson placed between himself and the
# captains on 2026-09-26. It is rank -1, above a captain, and the table is numbered rather than shifted
# so that C0..L0 keep their numbers in both scripts (`_fleet-ranks.sh` is where a renumbering belongs).
# What follows from it here: an A0 caller may promote or demote any rank below a captain and a captain
# too, because a captain reports to A0. Since the areas ruling (2026-09-29) there are two A0 sessions, told
# apart by full name, and each reaches only its own ships (`ship_refusal` in the table): the rear admiral
# CC, OB, HS, MA and FL, the areas admiral the area ships; DV no caller at all. Within its own ships an A0
# caller is not held to one ship, since A0 carries no ship code; the new name's ship therefore comes from
# the TARGET unless --ship says otherwise, and a bare-named target must be given --ship rather than
# guessed; a ship-coded `[A0-CC]` is not an admiral and is refused as a name with no rank code at
# all; and `--name` never carries A0, because only Nelson makes an admiral. `--to captain`
# stays refused for everyone, A0 included: only Nelson makes captains.
#
# The ship rules (Nelson, 2026-09-26; names carry the ship code after the rank):
#   * Both forms of the rank code are read, the bare `[C1]` and the coded `[C1-CC]`, because running
#     sessions keep bare names until Nelson renames them in the fleet view.
#   * The new name must be coded, and its ship is the promoter's, unless --ship gives one.
#   * `--by` with no ship code and no --ship is refused: the ship is never guessed.
#   * A --ship naming another captain's ship is refused when --by already carries one; the only
#     other value a promoter may pass for its own ship is FL, which floats the session.
#   * A session on another ship is not reached at all, except a floating `FL` target, which any rank
#     above it may act on, whatever ship that rank is on. A floating PROMOTER reaches floating and
#     uncoded sessions only, and is refused elsewhere. Ruled 2026-09-26: a float should reach any
#     ship when the target is in its own `reports-to` chain, because for a float the chain is the
#     boundary and the ship code is not — but this script has no chain walk (wake-session.sh beside
#     it does), so the refusal stands until the two share one helper, which is the ruled follow-up.
#   * A name may mark a session floating only when it already floats, or when --ship FL says so.
#     A promoter that itself floats does NOT float a session by inheritance: it must pass --ship FL,
#     because the rule says "passes --ship FL on purpose". Also a question in the PR.
#   * A target whose name carries no ship code at all is reachable by any rank above it, whatever its
#     ship, and the change gives the session a code. That is deliberate for the migration, while
#     running sessions still carry bare names, and nothing else protects such a session.
#
# Refuses while the fleet is paused, and fails closed: the flag is read by the same parser the
# tickle jobs use (tickle/scripts/_lib/pause-gate.sh in this repo), so an unreadable or malformed
# Pause note refuses too, and a gate that cannot be found refuses.
#
# Works under /bin/bash 3.2 (macOS). Needs jq and the claude CLI.

set -euo pipefail

FLEET_LOG="$HOME/obsidian/00-09 System/03 Agents/03.16 Cross-session log/CROSS-SESSION.md"
# The repo root, resolved through the ~/.claude/bin symlink, so the tickle gate beside us is found.
script_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || script_dir=""
REPO_ROOT=$(cd "$script_dir/../.." 2>/dev/null && pwd -P) || REPO_ROOT=""
PAUSE_GATE="$REPO_ROOT/tickle/scripts/_lib/pause-gate.sh"
AGENTS_DIR="$HOME/.claude/agents"
JOBS_DIR="$HOME/.claude/jobs"
# The frontmatter key that records a session's superior on its notebook entry. Confirmed by
# [C0] obsidian, 2026-09-26, and carried by the Session lifecycle block of ~/.claude/CLAUDE.md;
# wake-session.sh beside this script walks the same key. One variable, so a rename is one line.
REPORTS_TO_KEY="reports-to"

session="" to="" name="" by="" why="" prompt="" log="$FLEET_LOG" ship="" pause_note="" dry_run=0

die() { printf 'promote-session: %s\n' "$*" >&2; exit 2; }

# After `claude stop` has run, an unexpected failure must say so: the target is stopped and not resumed.
stopped_id=""
on_exit() {
  rc=$?
  if [ "$rc" -ne 0 ] && [ -n "$stopped_id" ]; then
    printf 'promote-session: %s was stopped but not resumed (exit %s); resume it yourself with: claude --bg --resume %s\n' "$stopped_id" "$rc" "$stopped_id" >&2
  fi
}

# THE LEASH ON `--jobs-dir`, put on it by the captain on 2026-09-27 when the flag landed. The flag says where
# a TARGET'S RANK is read from, and rank decides reach, so a flag that moves it must not be usable to dress
# an ordinary session up as something else in a real run. The leash: the path must resolve, with symlinks
# followed, to somewhere under /tmp or the system temp directory — the only places a battery writes.
#
# WHY A LEASH AND NOT A REFUSAL OUTRIGHT. The flag adds no authority it did not already have: `--by` is a
# string the caller supplies, so anyone who can pass `--jobs-dir` can already claim any rank they like, and
# anyone holding a shell can skip both scripts entirely. What the flag buys is a real test of the ONE gate
# nobody could otherwise exercise — the captain gate, which needs a captain-ranked target, which needs a
# session dispatched `--agent captain`, which is a captain in the fleet view and is exactly what the fixture
# rule forbids. So it stays, and it stays pointed at a temp directory.
check_jobs_dir() {  # $1 = the path as given; prints the resolved path, or dies
  jd_real=$(cd "$1" 2>/dev/null && pwd -P) || jd_real=""
  [ -n "$jd_real" ] || die "--jobs-dir must name a directory that exists; got '$1'"
  case "$jd_real" in
    /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) printf '%s' "$jd_real"; return 0 ;;
  esac
  if [ -n "${TMPDIR:-}" ]; then
    jd_tmp=$(cd "$TMPDIR" 2>/dev/null && pwd -P) || jd_tmp=""
    if [ -n "$jd_tmp" ]; then
      case "$jd_real" in
        "$jd_tmp"/*) printf '%s' "$jd_real"; return 0 ;;
      esac
    fi
  fi
  die "refused: --jobs-dir is test-only and must be under /tmp or the system temp directory; '$1' resolves to '$jd_real', which is neither"
}
trap on_exit EXIT

while [ $# -gt 0 ]; do
  case "$1" in
    --session) [ $# -ge 2 ] || die "--session needs a value"; session="$2"; shift 2 ;;
    --to)      [ $# -ge 2 ] || die "--to needs a value"; to="$2"; shift 2 ;;
    --name)    [ $# -ge 2 ] || die "--name needs a value"; name="$2"; shift 2 ;;
    --by)      [ $# -ge 2 ] || die "--by needs a value"; by="$2"; shift 2 ;;
    --why)     [ $# -ge 2 ] || die "--why needs a value"; why="$2"; shift 2 ;;
    --prompt)  [ $# -ge 2 ] || die "--prompt needs a value"; prompt="$2"; shift 2 ;;
    --log)     [ $# -ge 2 ] || die "--log needs a value"; log="$2"; shift 2 ;;
    --jobs-dir) [ $# -ge 2 ] && [ -n "$2" ] || die "--jobs-dir needs a path"; JOBS_DIR=$(check_jobs_dir "$2"); shift 2 ;;
    --ship)    [ $# -ge 2 ] && [ -n "$2" ] || die "--ship needs a value"; ship="$2"; shift 2 ;;
    --pause-note) [ $# -ge 2 ] && [ -n "$2" ] || die "--pause-note needs a path"; pause_note="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) awk 'NR>1 && !/^#/ {exit} NR>1 {sub(/^# ?/, ""); print}' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$session" ] || die "--session is required"
[ -n "$to" ]      || die "--to is required"
[ -n "$name" ]    || die "--name is required"
[ -n "$by" ]      || die "--by is required"
[ -n "$why" ]     || die "--why is required"
command -v jq >/dev/null     || die "jq is required"
command -v claude >/dev/null || die "the claude CLI is required"

# --- ranks and ships, from the one table ------------------------------------------------------
# `_fleet-ranks.sh` beside this script holds the rank line and the ship codes: `rank_of_name`,
# `rank_of_caller`, `rank_of_agent`, `word_of_rank`, `bare_code_of_rank`, `code_of_rank`, `KNOWN_SHIPS`,
# `FLOATING_SHIP`, `ship_of_name`, `ship_is_known`, `ships_in_words`, and the admirals' and guarded ships with `ship_is_guarded` and `ship_refusal`. Both this script and its sibling held byte-identical
# copies of most of those, and copies of `rank_of_name` that differed in the comment only — the rank line
# is the one thing two fleet scripts must never disagree about, so it is one file now. Adding a ship code
# is one line THERE, not here.
#
# Sourced by path beside this script, resolved with `pwd -P`, so it works from the repo and through the
# `~/.claude/bin` symlink the installer makes. A missing or unreadable table is fatal: every rank check in
# this script depends on it, and a script that cannot read the rank line must not act on a rank.
FLEET_RANKS="$script_dir/_fleet-ranks.sh"
[ -r "$FLEET_RANKS" ] || die "the rank table is missing or unreadable at $FLEET_RANKS; this script cannot judge a rank without it"
# PARSED BEFORE IT IS SOURCED, and the `|| die` after the `.` is not enough on its own. Under `set -e` a
# SYNTAX ERROR in a sourced file aborts this script before the `||` is ever reached, the EXIT trap is
# entered with a zero status, and `on_exit` does not re-exit — so the script exited 0, which its own header
# documents as "done", having done nothing. An unresolved merge conflict in the table produces exactly
# that, and this file is where a rank gets added, so it is the realistic shape rather than a contrived one.
# Found by the review of #61; the failure did not exist before the extraction, because nothing was sourced.
bash -n "$FLEET_RANKS" 2>/dev/null || die "the rank table at $FLEET_RANKS does not parse (an unresolved merge conflict, or a truncated file); refusing, because a script that cannot read the rank line must not act on a rank"
# shellcheck source=_fleet-ranks.sh
. "$FLEET_RANKS" || die "the rank table at $FLEET_RANKS could not be sourced"
# AND THAT IT DEFINED WHAT IT PROMISES: a table that parses but defines nothing left the script to fail
# later with 127, not with a refusal. One probe is enough — they all come from the same file.
command -v rank_of_name >/dev/null 2>&1 || die "the rank table at $FLEET_RANKS parsed but defined no rank line; refusing"
# THE bg-id PARSER, the one reader of the new id in `claude --bg` output (shared with wake-session.sh). Guarded as the other libraries are: readable, parses, defines bg_id.
BG_ID_LIB="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)/../lib/bg-id.sh"
[ -r "$BG_ID_LIB" ] || die "the bg-id parser is missing or unreadable at $BG_ID_LIB"
bash -n "$BG_ID_LIB" 2>/dev/null || die "the bg-id parser at $BG_ID_LIB does not parse; refusing"
# shellcheck source=../lib/bg-id.sh
. "$BG_ID_LIB" || die "the bg-id parser at $BG_ID_LIB could not be sourced"
command -v bg_id >/dev/null 2>&1 || die "the bg-id parser at $BG_ID_LIB parsed but defined no bg_id; refusing"
# THE FLEET GATE (Nelson's "a", log 2026-09-30T05:32): no session is stopped, started or resumed while the 5-minute load is 8 or more, or 20 or more sessions are live. claude/lib/fleet-gate.sh asks claude/bin/fleet-gate; a gate that cannot be run holds. A dry run is not gated. Guarded as the other libraries are.
FLEET_GATE_LIB="$script_dir/../lib/fleet-gate.sh"
[ -r "$FLEET_GATE_LIB" ] || die "the fleet-gate library is missing or unreadable at $FLEET_GATE_LIB"
bash -n "$FLEET_GATE_LIB" 2>/dev/null || die "the fleet-gate library at $FLEET_GATE_LIB does not parse; refusing"
# shellcheck source=../lib/fleet-gate.sh
. "$FLEET_GATE_LIB" || die "the fleet-gate library at $FLEET_GATE_LIB could not be sourced"
command -v fleet_gate_check >/dev/null 2>&1 || die "the fleet-gate library at $FLEET_GATE_LIB parsed but defined no fleet_gate_check; refusing"

[ "$to" != "captain" ] || die "refused: only Nelson makes captains"
# `rank_of_agent admiral` is -1 since 2026-09-29, so --to admiral is refused here, outright, the way --to captain
# is, and not by accident further down (review 1 of #80).
[ "$to" != "admiral" ] || die "refused: only Nelson makes an admiral"
[ -f "$AGENTS_DIR/$to.md" ] || die "no agent definition at $AGENTS_DIR/$to.md"
to_rank=$(rank_of_agent "$to");   [ "$to_rank" != 9 ] || die "--to must be a fleet rank, got '$to'"
by_rank=$(rank_of_caller "$by"); [ "$by_rank" != 9 ] || die "--by must start with a rank code, bare or ship-coded ([C0], [C1], [C2], [L0], [C1-CC], [C2-OB] …), or the bare [A0], which carries no ship code; got '$by'"
# THE ACCEPT VERBS' WRITE PATH NOTIFIES; IT DOES NOT PROMOTE. It reaches this script only because
# `rank_of_caller` is one seam shared with wake-session.sh, which package 5 widened for the notifier. Before
# package 5 it was refused here as a caller with no rank code, and it stays refused — but with its own
# sentence, because the ship block below would otherwise refuse it with "pass --ship <every ship>", which
# names the wrong problem and invites a caller to pass one. Nothing was ruled about the verb path promoting
# anybody, and a rank change nobody can attribute to a session is worse than one refused.
[ "$by_rank" -ge -1 ] || die "refused: '$by' is the accept verbs' write path; it notifies a session, it does not promote or demote one"
name_rank=$(rank_of_name "$name"); [ "$name_rank" != -1 ] || die "refused: --name '$name' would make an admiral, and only Nelson makes one; A0 is never a --name"
[ "$name_rank" = "$to_rank" ] || die "--name '$name' must carry the rank code $(bare_code_of_rank "$to_rank") to match --to $to"
[ "$to_rank" -gt "$by_rank" ] || die "refused: $by ($(word_of_rank "$by_rank")) may only promote or demote to a rank below its own; $to is not below it"

# --- the ship ---------------------------------------------------------------------------------
# The new name's ship comes from the promoter's own name, or from --ship when one is given; it is
# never guessed. A promoter with a bare name has no ship to carry over, so it must say which.
by_ship=$(ship_of_name "$by")
# An admiral carries no ship code. Within the ships it reaches, the one-ship rule below does not apply to
# it: it cannot "move a session onto another captain's ship", because no single ship is its own. Which
# ships it reaches is `ship_refusal`'s rule, checked on the new name's ship and on the target's.
# A0 keeps a session where it is unless --ship says otherwise, so the new name's ship comes from the
# TARGET, which is not read until below; the decision is deferred rather than guessed.
ship_from_target=0
if [ "$by_rank" = -1 ]; then
  if [ -n "$ship" ]; then
    ship_is_known "$ship" || die "--ship must be one of: $(unguarded "$KNOWN_SHIPS"); got '$ship'"
    new_ship="$ship"
  else
    new_ship=""
    ship_from_target=1
  fi
elif [ -n "$ship" ]; then
  ship_is_known "$ship" || die "--ship must be one of: $(unguarded "$KNOWN_SHIPS"); got '$ship'"
  if [ -n "$by_ship" ] && [ "$ship" != "$by_ship" ] && [ "$ship" != "$FLOATING_SHIP" ]; then
    die "refused: --ship $ship does not match $by's own ship ($by_ship); a rank does not move a session onto another captain's ship"
  fi
  new_ship="$ship"
else
  # The captain's wording, corrected by him on 2026-09-26 once HS existed. The words around the list are
  # his; the list itself is `ships_in_words`, read from KNOWN_SHIPS, so it grows with the table.
  [ -n "$by_ship" ] || die "--by has no ship code; pass --ship $(ships_in_words) (FL for a floating session)"
  ship_is_known "$by_ship" || die "--by carries the ship code '$by_ship', which is not one of: $(unguarded "$KNOWN_SHIPS"); pass --ship to say which ship"
  new_ship="$by_ship"
fi

name_ship=$(ship_of_name "$name")
# The table reads a ship code in any case (so `[L0-dv]` is DV), but this script WRITES the new name as given, so the code in it must be in capitals (review 2 of #88).
# Compared with its upper-cased form, not a `[a-z]` pattern, which some locales' collation matches to capitals too.
[ "$(printf '%s' "$name" | sed -n -E 's/^\[[A-Za-z][0-9]-([A-Za-z]{1,4})\].*/\1/p')" = "$name_ship" ] || die "--name '$name' must carry its ship code in capitals, like \"$(code_of_rank "$to_rank" "$name_ship") …\""
[ -n "$name_ship" ] || die "--name '$name' must carry the coded form, rank and ship together, like \"$(code_of_rank "$to_rank" "$new_ship") <name>\""
ship_is_known "$name_ship" || die "--name '$name' carries the ship code '$name_ship', which is not one of: $(unguarded "$KNOWN_SHIPS")"
# THE ADMIRALS AND THE GUARDED SHIP (areas ruling, log 2026-09-29T03:35): `ship_refusal` in the table is the
# one rule, checked on every ship the change touches. Here the NEW name's ship, before anything is looked
# up; below, once the target is found, the ship it is on now. Both, because a change touches both ships:
# promoting a DV session onto FL moves it out of DV, and a bare target named onto DV moves it in.
r=$(ship_refusal "$by" "$by_rank" "$name_ship"); [ -z "$r" ] || die "$r"

# --- the target session ----------------------------------------------------------------------
listing=$(claude agents --json --all 2>/dev/null) || die "claude agents --json failed"
row=$(printf '%s' "$listing" | jq -c --arg s "$session" '[.[] | select(.id==$s or .sessionId==$s)] | first // empty') || die "could not parse claude agents --json"
[ -n "$row" ] || die "no background session with id or sessionId '$session' in claude agents --json --all"
old_id=$(printf '%s' "$row" | jq -r .id)
session_id=$(printf '%s' "$row" | jq -r .sessionId)
old_name=$(printf '%s' "$row" | jq -r '.name // ""')
old_cwd=$(printf '%s' "$row" | jq -r '.cwd // ""')
old_pid=$(printf '%s' "$row" | jq -r '.pid // empty')
[ -d "$old_cwd" ] || die "the session's cwd '$old_cwd' does not exist; the resume must run there"

old_agent=$(jq -r '.template // "bg"' "$JOBS_DIR/$old_id/state.json" 2>/dev/null || echo bg)
old_rank=$(rank_of_agent "$old_agent")
# An admiral is matched by its FULL NAME (the table's rule). A session that runs the admiral definition under a
# name that is not an [A0] name was not made by Nelson, so its rank cannot be read (review 1 of #80).
[ "$old_rank" != 9 ] && [ "$old_agent" != bg ] || old_rank=$(rank_of_name "$old_name")
if [ "$old_rank" = -1 ] && ! is_admiral "$old_name"; then
  # After the name fallback, so it covers both roads to -1: the admiral definition, and an [A0] name with no definition. An admiral is one of the two full names (the table's `is_admiral`); anything else that reads as -1 is refused (reviews 1 and 2 of #88).
  die "refused: \`$old_name\` reads as an admiral but is not an admiral's name; only Nelson makes an admiral, so its rank cannot be read"
fi
[ "$old_rank" != 9 ] || die "cannot tell the target's current rank from its agent ('$old_agent') or its name ('$old_name')"
[ "$old_rank" -gt "$by_rank" ] || die "refused: $old_name ($(word_of_rank "$old_rank")) is not below $by; a rank changes only ranks below its own"
[ "$old_rank" -ne "$to_rank" ] || die "$old_name is already a $(word_of_rank "$to_rank")"

if [ "$to_rank" -lt "$old_rank" ]; then verb=promoted; else verb=demoted; fi

# --- the ship, against the target ------------------------------------------------------------
# A session belongs to a captain's ship, and a rank does not reach onto another ship — except for a
# floating session, marked FL, which is shared across captains: any rank above it may act on it.
old_ship=$(ship_of_name "$old_name")
# A target coded with a ship this table does not know is refused whatever --ship says. Before this, only
# the path that takes the ship FROM the target checked it, so `--ship CC` moved a `[L0-DV]` session onto CC
# while DV was held out of the table (review 6 of #72).
[ -z "$old_ship" ] || ship_is_known "$old_ship" || die "refused: \`$old_name\` carries the ship code '$old_ship', which is not one of: $(unguarded "$KNOWN_SHIPS")"
ship_note=""
# The rear admiral's new name takes the target's own ship when no --ship was given: A0 leaves a session
# where it is. A bare-named target has no ship to take, so it must be said rather than guessed.
if [ "$ship_from_target" = 1 ]; then
  [ -n "$old_ship" ] || die "refused: \`$old_name\` carries no ship code and $by has none either, so the new name's ship cannot be read from anywhere; pass --ship $(ships_in_words) (FL for a floating session)"
  # (an unknown code on the target was already refused above, whatever --ship says)
  new_ship="$old_ship"
  ship_note="the ship comes from the target, because an admiral carries none"
fi
r=$(ship_refusal "$by" "$by_rank" "$old_ship"); [ -z "$r" ] || die "$r"
# Reach is judged against the PROMOTER's ship, never against the new name's: a captain making one of
# its own sessions float passes --ship FL, and that must not read as reaching onto another ship.
caller_ship="$by_ship"
[ -n "$caller_ship" ] || caller_ship="$ship"
# Only the FL TARGET is exempt, which is what was ruled. A floating PROMOTER gets no extra reach
# here: that would be a rule nobody has made, so it is refused and left as a question in the PR.
# An admiral is exempt from THIS check as a caller, because it carries no ship of its own; the ships it may
# act on are limited instead by `ship_refusal` (above), which keeps each admiral to its own ships.
if [ "$by_rank" != -1 ] && [ -n "$old_ship" ] && [ "$old_ship" != "$FLOATING_SHIP" ] && [ "$old_ship" != "$caller_ship" ]; then
  die "refused: \`$old_name\` is on ship $old_ship and $by acts on ship $caller_ship; only a rank on its own ship, or Nelson, changes that session's rank (a floating $FLOATING_SHIP session is the exception, and this one is not floating)"
fi
if [ "$name_ship" = "$FLOATING_SHIP" ]; then
  # FL is not inherited by accident: either the session already floats, or the caller says so.
  if [ "$old_ship" != "$FLOATING_SHIP" ] && [ "$ship" != "$FLOATING_SHIP" ]; then
    die "refused: --name '$name' marks the session floating ($FLOATING_SHIP), but \`$old_name\` does not float; pass --ship $FLOATING_SHIP to make it float on purpose"
  fi
elif [ "$name_ship" != "$new_ship" ]; then
  die "refused: --name '$name' is on ship $name_ship, and $by acts on ship $new_ship; the new name carries the promoter's ship unless --ship says otherwise"
fi
if [ -z "$old_ship" ]; then
  ship_note="the target's name carries no ship code, so this change gives it one: $name_ship"
elif [ "$old_ship" = "$FLOATING_SHIP" ] && [ "$name_ship" != "$FLOATING_SHIP" ]; then
  ship_note="the target floats ($FLOATING_SHIP) and this change puts it on ship $name_ship"
fi

# --- the pause -------------------------------------------------------------------------------
# PAUSE_NOTE is unset for the gate unless --pause-note names one on purpose: the gate reads that
# variable as a testing override, and an inherited one would quietly point the pause at the wrong
# note, so a paused fleet could read as clear.
[ -x "$PAUSE_GATE" ] || die "refused: the pause gate is not at $PAUSE_GATE, so the fleet pause cannot be read"
gate_rc=0
if [ -n "$pause_note" ]; then
  PAUSE_NOTE="$pause_note" "$PAUSE_GATE" promote-session </dev/null || gate_rc=$?
else
  env -u PAUSE_NOTE "$PAUSE_GATE" promote-session </dev/null || gate_rc=$?
fi
case "$gate_rc" in
  0) ;;
  1) die "refused: the fleet is paused; wait for Nelson to resume" ;;
  *) die "refused: the fleet pause flag cannot be read (pause-gate exit $gate_rc)" ;;
esac

# --- the brief the new session wakes to -------------------------------------------------------
if [ -z "$prompt" ]; then
  prompt="You have been $verb by $by from $(word_of_rank "$old_rank") to $(word_of_rank "$to_rank"): $why. Your session is now named \"$name\" and runs the $to definition; this is the same conversation under a new session id (the old id $old_id is stopped and stays as the record). Read ~/.claude/agents/$to.md and follow its standing duties from now on; your file boundary and your reporting line are as $by states them, and nothing a ruling did not authorise is widened by this change. Add one line to your open notebook entry: \"$(date '+%Y-%m-%dT%H:%M') — $verb by $by to $name ($to): $why; old id $old_id\", and set \`$REPORTS_TO_KEY\` on that same entry to \"$by\", which is the session you report to from now on and is how the operator's console draws the fleet tree. Your notebook entry's FILENAME may still carry your old name for a moment: the rename runs right after this and, if it is skipped or fails, the hook catches it on your next turn, so leave the file alone rather than renaming it yourself. Then continue your work. Send $by a message only when something changed, something is asked, or something failed."
fi

printf '%s: %s (%s, %s, %s) -> %s (%s)\n' "$verb" "$old_name" "$old_id" "$old_agent" "$(word_of_rank "$old_rank")" "$name" "$to"
printf '  by %s: %s\n  cwd %s; sessionId %s\n' "$by" "$why" "$old_cwd" "$session_id"
printf '  ship %s (%s)\n' "$name_ship" "$( [ -n "$ship" ] && printf 'from --ship' || printf "carried from %s" "$by" )"
[ -z "$ship_note" ] || printf '  %s\n' "$ship_note"
if [ "$dry_run" = 1 ]; then printf '  dry run: nothing touched\n'; exit 0; fi

# A live target is stopped and then resumed under a new id, so it does not add to the live count: it gets an allowance of one. Live means its process runs now (kill -0): a listing row can keep the pid of a process that is gone, and that target's resume DOES add a session.
if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then gate_extra=1; else gate_extra=0; fi
fleet_gate_check "$gate_extra" || die "held by the fleet gate, so nothing is stopped or started: ${FLEET_GATE_VERDICT:-no reason given}. Nothing was touched; run this again when \`fleet-gate\` opens (\`fleet-gate --wait\` waits for it)."

# --- stop, and wait until the process is really gone ------------------------------------------
if [ -n "$old_pid" ]; then
  claude stop "$old_id" >/dev/null 2>&1 || true
  stopped_id="$old_id"
  waited=0
  while kill -0 "$old_pid" 2>/dev/null; do
    sleep 1; waited=$((waited + 1))
    [ "$waited" -lt 90 ] || die "pid $old_pid of $old_id did not exit within 90 s; nothing resumed"
  done
fi

# --- resume as the new rank, under a new id ---------------------------------------------------
out=$(cd "$old_cwd" && claude --bg --resume "$session_id" --agent "$to" --name "$name" --system-prompt-snapshot off "$prompt" 2>&1) || die "claude --bg --resume failed: $out"
# The resume ran (claude --bg exited 0), so the old session is no longer "stopped but not resumed": clear that before the id is read, or a parser refusal would tell the operator to resume it again and start a second copy.
stopped_id=""
new_id=$(printf '%s' "$out" | bg_id) || die "the resume of $old_id RAN, but its new id could not be read (bg-id says why, above). Do NOT resume $old_id again: that would start a second copy. Find the new session named \"$name\" in \`claude agents --json --all\`; nothing was logged."

# --- the record ------------------------------------------------------------------------------
stamp=$(date '+%Y-%m-%dT%H:%M')
cat <<EOF >> "$log"

## $stamp · $by — $verb \`$old_name\` ($old_id) to \`$name\` ($new_id)

$by $verb the session \`$old_name\` (background id $old_id, agent \`$old_agent\`, $(word_of_rank "$old_rank")) to \`$name\` (background id $new_id, agent \`$to\`, $(word_of_rank "$to_rank")). Why: $why. The conversation continues under the new id with the same context; the old id is stopped and stays as the record of the earlier rank. Posted by \`promote-session.sh\` on behalf of $by, who attests its own log position in its own entries. — $by
EOF

# Cosmetic: the new sessionId for the closing line. It must never abort the script; the record is already written.
new_session_id=$( { claude agents --json --all 2>/dev/null || true; } | { jq -r --arg s "$new_id" '.[] | select(.id==$s) | .sessionId' 2>/dev/null || true; } | head -n 1) || new_session_id=""
printf 'done: %s is now %s (%s); new id %s, sessionId %s; old id %s stopped; record appended to %s\n' "$old_name" "$name" "$to" "$new_id" "${new_session_id:-?}" "$old_id" "$log"

# The notebook entry still carries the old name in its filename. The rename script beside this one
# puts it back in step; the old name is passed explicitly because the fork's registry has no
# formerNames for a name that belonged to a session which has already exited. The promotion has
# landed by now either way, so this must never abort the script — but note what that means: if the
# call is skipped because no sessionId came back, or if it fails, the entry keeps the old name until
# the session's next turn, when the UserPromptSubmit hook catches it. Nothing tells the session
# itself; the brief does not mention its filename.
if [ -n "$new_session_id" ] && [ -x "$script_dir/rename-notebook.sh" ]; then
  rn_out=$("$script_dir/rename-notebook.sh" "$new_session_id" --old-name "$old_name" --log "$log" 2>&1) || rn_out="rename-notebook.sh refused or failed: $(printf '%s' "$rn_out" | tail -n 1)"
  printf 'notebook: %s\n' "$(printf '%s' "$rn_out" | tail -n 1)"
fi
