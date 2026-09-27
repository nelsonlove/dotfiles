#!/usr/bin/env bash
# pause-flag.sh — the fleet pause note's frontmatter parser, in one place.
#
# NOT EXECUTABLE ON ITS OWN, and it deliberately EXITS NOTHING. It defines two functions and three
# variables and returns; every exit path stays in the caller, because the two callers have incompatible
# exit contracts and sharing them would be a bug rather than a saving:
#   * `claude/hooks/pause-guard.sh` is a PreToolUse hook — exit 0 allows, exit 2 blocks with stderr fed
#     back to the model, and every other code reads as allow.
#   * `tickle/scripts/_lib/pause-gate.sh` is a tickle script trigger — exit 0 runs the job, exit 1 skips
#     it, and anything else is a failed check. A stray 1 there would be an invisible permanent skip.
#
# THE CONTRACT, which is the whole interface:
#   IN   `$PAUSE_NOTE` — the path of the pause note. The caller sets it; this file never guesses it, and
#        never reads it from the environment, because a `PAUSE_NOTE` inherited from an unrelated process
#        once pointed a pause check at the wrong note.
#   OUT  `$flag_state`  — one of `absent`, `paused`, `clear`, `bad`. Nothing else, ever.
#        `$flag_reason` — set only when the state is `bad`, in a sentence a human can act on.
#        `$flag_block`  — the raw frontmatter block, for a caller that wants another key out of it.
#   `read_pause_flag` always RETURNS 0. It reports through `$flag_state`, so a caller cannot mistake a
#   parse failure for a pause or for a clear note; deciding what a `bad` state means belongs to the
#   caller, and both of them treat it as a refusal.
#
# FAILS CLOSED BY DESIGN, and the reason is in the states rather than in this file's code: only `absent`
# and `clear` let anything proceed. An unreadable note, a note that does not begin with `---`, an unclosed
# frontmatter block, a missing `paused` key and an unrecognised value are all `bad`. A pause is a human
# saying stop, so "I could not tell" must never mean "carry on".
#
# CR IS STRIPPED EVERYWHERE, and that is a bug fix rather than a nicety: a CRLF note never matched the
# `---` fence, which left the frontmatter empty and the guard wide open.
#
# HOW A CALLER FINDS THIS FILE — three identical lines, and the way both callers here write them. Walk UP
# from the script's own directory until a `.git` appears, and source `$root/claude/lib/pause-flag.sh`:
#
#     d=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || d=""
#     while [ -n "$d" ] && [ ! -e "$d/.git" ]; do [ "$d" != "/" ] || { d=""; break; }; d=$(dirname "$d"); done
#     [ -n "$d" ] || <the caller refuses, in its own exit contract>
#
# DO NOT COUNT LEVELS. The two callers sit at DIFFERENT DEPTHS — the hook is two levels below the repo
# root (`claude/hooks/`), the gate is three (`tickle/scripts/_lib/`) — so a copied `../..` resolves to a
# path that does not exist. That matters most on the gate: a failed `source` there exits non-zero, the
# EXIT trap rewrites it to 2, tickle records "check failed", and the job SILENTLY DOES NOT RUN. That is
# the same class of silent failure that hid a 29-hour obsidian-backup outage, which is why the gate's own
# header says so and why this file refuses to be found by counting.
#
# `.git` is a DIRECTORY in the main checkout and a FILE in a git worktree, so the test is `-e` rather than
# `-d`, and the walk works verbatim in both. From a worktree it stops at the WORKTREE root and reads that
# worktree's copy of this file, which is the right answer for a parser under development and is stated
# here so nobody discovers it by surprise. If the walk reaches `/` without finding `.git` — a tarball
# export, a vendored copy, a file moved out of the tree — the caller must REFUSE and say which directory
# it searched from. Guessing a depth there is worse than failing, because a wrong guess fails silently.
#
# TWO THINGS A CALLER MUST KNOW BEFORE SOURCING THIS, both found by the review of #61.
#
# `fm_value` IS NOT UNIQUE. `claude/bin/rename-notebook.sh` defines a function of the same name with an
# INCOMPATIBLE signature — there it takes a file and a key, here it takes a key and reads `$flag_block`.
# Nothing collides today because that script sources nothing, but a script that sources both would get
# whichever came last, and the survey in `docs/fleet-machinery/` exists because same-name/different-contract
# functions are exactly the trap. If a third caller ever wants both, one of them has to be renamed first.
#
# THE WALK FINDS *A* REPO, NOT NECESSARILY *THIS* ONE, and this is the one paragraph in this file worth
# reading twice. `.git` above a caller could belong to another tree that happens to contain a
# `claude/lib/pause-flag.sh`, and the caller would source THAT. Measured consequence, not a worry: a PAUSED
# note was read as CLEAR, a write went through, and a job ran. **That is precisely the failure the fleet
# pause rule exists to prevent** — 01.65 design rule 10, one flag note is the whole state — so the
# convenience of finding the library by walking up bought, as a side effect, the one outcome the thing it
# serves forbids. The walk-up was approved by the captain when he ruled out counting levels, and that is
# part of the record rather than a reason to be quiet about the cost: a convenience approved in good faith
# still has to be paid for.
#
# SO EACH CALLER ALSO CHECKS THAT THE ROOT IT FOUND CONTAINS THE CALLER ITSELF at its expected path, and
# that is the REASON the check exists rather than a detail of how it works: it turns "a repo" into "my
# repo", which is the only question that matters. A root that does not hold this script is not this
# script's root, however many `.git` directories are above it. Reaching the bad case needs a
# misconfiguration — a copy of a caller somewhere under an unrelated checkout — and a fail-open is the one
# class of defect worth two lines to close on a maybe.
#
# Works under /bin/bash 3.2 (macOS). Needs grep, sed, awk, tr, head.

sq="'"
flag_state=""
flag_reason=""
flag_block=""

fm_value() {
  printf '%s\n' "$flag_block" \
    | grep -E "^[[:space:]]*$1[[:space:]]*:" \
    | head -n 1 \
    | sed -E "s/^[[:space:]]*$1[[:space:]]*:[[:space:]]*//" \
    | sed -E "s/^\"(.*)\"\$/\1/; s/^${sq}(.*)${sq}\$/\1/" \
    | sed -E "s/[[:space:]]+\$//"
}

# THE FRONTMATTER BLOCK OF ANY NOTE, not only the pause note. `read_pause_flag` below is one caller of
# this; `claude/bin/notify-session.sh` is the other, reading a queue note's `session:` key. It exists so
# that a second script wanting a frontmatter value does not carry a second copy of this block reader —
# which is the whole reason this file exists. Sets `flag_block`, `flag_state` and `flag_reason` exactly as
# the pause reader does, so both callers read one contract.
read_frontmatter() {  # $1 = the note path
  flag_state=""
  flag_reason=""
  flag_block=""
  if [ ! -e "$1" ]; then
    flag_state="absent"
    return 0
  fi
  if [ ! -f "$1" ] || [ ! -r "$1" ]; then
    flag_state="bad"
    flag_reason="the note exists but is not a readable file"
    return 0
  fi

  # The opening fence must be the FIRST line. Matching any `---` anywhere
  # would read a thematic break in the body as the start of frontmatter.
  first_line=$(head -n 1 "$1" 2>/dev/null | tr -d '\r' | sed -E "s/[[:space:]]+\$//")
  if [ "$first_line" != "---" ]; then
    flag_state="bad"
    flag_reason="the note has no frontmatter block (it does not begin with ---)"
    return 0
  fi

  flag_block=$(tr -d '\r' < "$1" | awk 'NR==1{next} /^---[ \t]*$/{closed=1; exit} {print} END{if(!closed) exit 1}')
  if [ $? -ne 0 ]; then
    flag_state="bad"
    flag_reason="the note's frontmatter block is never closed"
    return 0
  fi
  flag_state="read"
  return 0
}

read_pause_flag() {
  read_frontmatter "$PAUSE_NOTE"
  # `absent` and `bad` are already the pause contract's own words for those cases, so they pass straight
  # through; only a successfully READ block continues to the `paused` key.
  [ "$flag_state" = "read" ] || return 0

  paused_line=$(printf '%s\n' "$flag_block" | grep -E "^[[:space:]]*paused[[:space:]]*:" | head -n 1)
  if [ -z "$paused_line" ]; then
    flag_state="bad"
    flag_reason="the note's frontmatter has no 'paused' key"
    return 0
  fi

  paused_value=$(printf '%s' "$paused_line" \
    | sed -E "s/^[[:space:]]*paused[[:space:]]*:[[:space:]]*//" \
    | sed -E "s/[[:space:]]+#.*\$//" \
    | sed -E "s/^\"(.*)\"\$/\1/; s/^${sq}(.*)${sq}\$/\1/" \
    | sed -E "s/^[[:space:]]+//; s/[[:space:]]+\$//" \
    | tr '[:upper:]' '[:lower:]')

  case "$paused_value" in
    true|yes) flag_state="paused" ;;
    false|no) flag_state="clear" ;;
    *)
      flag_state="bad"
      flag_reason="the note's 'paused' value is not true/false/yes/no (found: '$paused_value')"
      ;;
  esac
  return 0
}
