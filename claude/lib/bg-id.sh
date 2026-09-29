#!/usr/bin/env bash
# bg-id.sh — read the new SHORT id out of `claude --bg` output, in one place.
#
# Two parsers disagreed before this file: promote-session.sh took field 3 of the `^backgrounded` line, and wake-session.sh took the first hex token of 6 or more characters on that line, and read the "started a copy as" note with a sed of its own. A third copy was on its way into a tickle job. This is the one parser; source it, or run it.
#
#   SOURCED:  . claude/lib/bg-id.sh
#             new_id=$(printf '%s' "$out" | bg_id) || die "..."        the id, or a loud failure
#             bg_parse <<<"$out"                                       sets BG_NEW, BG_COPY, BG_ORIGINAL, BG_ERR in the caller's shell
#   RUN:      claude --bg … 2>&1 | bash claude/lib/bg-id.sh
#
# IN   `claude --bg` output (stdout and stderr together) on stdin.
# bg_id OUT   the short id and a newline on stdout, exit 0. On failure: nothing on stdout, a message on stderr that names what was seen, exit 1. It never guesses.
# bg_parse    returns 0 or 1 as bg_id does, and sets, whatever the result:
#   BG_NEW       the new id, or empty on failure
#   BG_COPY      the id a note says a COPY was started as ("… started a copy as 61efac93"), or empty. Set even when BG_NEW fails, so a caller can stop a copy before it refuses.
#   BG_ORIGINAL  the id a copy note names as the ORIGINAL ("session 05ab1bf4 is already running", "background session 05ab1bf4 keeps its own saved options"), or empty
#   BG_ERR       the failure message, or empty
#
# THE OUTPUT, measured 2026-09-29 on throwaways (the fixtures in claude/tests/bg-id/fixtures are those raw bytes):
#   a fresh start           backgrounded · ESC[36m2dae6eccESC[39m · [L0-CC] bg-id test
#   a resume of a stopped   note: woke session 2dae6ecc with its saved options (--name, --model, --permission-mode).
#   session                 backgrounded · ESC[36m2dae6eccESC[39m · [L0-CC] bg-id test
#   a resume that forked    note: session 05ab1bf4 is already running in the background, so this started a copy as 61efac93. …
#   (still running, or      note: background session 05ab1bf4 keeps its own saved options, so the flags you passed started a copy as 236a4f0e. …
#   flags passed)           backgrounded · ESC[36m61efac93ESC[39m
#   under a tty             ^D BS BS backgrounded · …  CR at every line end
#   followed by four dim hint lines (`claude attach <id>` and so on), which are not read.
# The colour codes come even when stdout is a pipe. The name after the second `·` is optional (a copy started without --name has none), and a name can hold any words, so only the token straight after `backgrounded ·` is read on that line. No measured output said "resumed as <id>", so that phrase is not read.
#
# THE RULE: strip CR and colour codes, apply backspaces, strip other control characters. The candidates for the new id are the token right after `backgrounded ·` on every `backgrounded` line, and the id after "started a copy as" on a `note:` line. An id is 6 or more lowercase hex characters (8 measured; the width is not pinned, so a longer short id does not break every caller at once). Exactly one distinct candidate is the answer. None, or two different ones, is a failure.

bg_parse() {
  local raw clean cands n
  BG_NEW=""; BG_COPY=""; BG_ORIGINAL=""; BG_ERR=""
  raw=$(cat)
  # A backspace erases the character before it (a tty echoes ^D and then two backspaces before the first line), so backspaces are applied before the other control characters go.
  clean=$(printf '%s\n' "$raw" | tr -d '\r' | sed -E $'s/\x1b\\[[0-9;?]*[A-Za-z]//g' | LC_ALL=C sed -e $':a\ns/[^\x08]\x08//\nta' | LC_ALL=C tr -d '\000-\010\013\014\016-\037')
  BG_COPY=$(printf '%s\n' "$clean" | LC_ALL=C sed -n -E 's/^[[:space:]]*note:.*started a copy as ([0-9a-f]{6,})([^0-9A-Za-z].*)?$/\1/p' | head -n 1)
  BG_ORIGINAL=$(printf '%s\n' "$clean" | LC_ALL=C sed -n -E 's/^[[:space:]]*note:.*session ([0-9a-f]{6,}) (is already running|keeps its own saved options).*$/\1/p' | head -n 1)
  cands=$(printf '%s\n' "$clean" | LC_ALL=C awk '
    /^[[:space:]]*backgrounded[[:space:]]/ {
      line = $0; sub(/^[[:space:]]*backgrounded[[:space:]]*/, "", line)
      if (substr(line, 1, 2) == "\302\267") line = substr(line, 3)   # the middle dot, U+00B7, in UTF-8
      sub(/^[[:space:]]*/, "", line)
      tok = line; sub(/[^0-9A-Za-z].*$/, "", tok)
      if (tok ~ /^[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]+$/) print tok; else print "BAD:" (tok == "" ? "(nothing)" : tok)
    }' | sort -u)
  [ -z "$BG_COPY" ] || cands=$(printf '%s\n%s\n' "$cands" "$BG_COPY" | grep . | sort -u)
  n=$(printf '%s' "$cands" | grep -c . || true)
  if printf '%s\n' "$cands" | grep -q '^BAD:'; then
    BG_ERR="bg-id: a backgrounded line holds no hex id after \"backgrounded ·\" (saw $(printf '%s\n' "$cands" | sed -n 's/^BAD://p' | head -n 1)) in: $clean"
    return 1
  fi
  if [ "$n" = 0 ]; then
    BG_ERR="bg-id: no id in the claude --bg output (no \"backgrounded · <id>\" line, no \"started a copy as <id>\" note): ${clean:-(empty)}"
    return 1
  fi
  if [ "$n" != 1 ]; then
    BG_ERR="bg-id: $n different ids in the claude --bg output ($(printf '%s' "$cands" | tr '\n' ' ' | sed 's/ $//')), and only one can be the new session: $clean"
    return 1
  fi
  BG_NEW=$cands
  return 0
}

bg_id() {
  if bg_parse; then printf '%s\n' "$BG_NEW"; return 0; fi
  printf '%s\n' "$BG_ERR" >&2
  return 1
}

# Run as a command: read stdin, print the id.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  bg_id
  exit $?
fi
