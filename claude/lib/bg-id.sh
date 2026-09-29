#!/usr/bin/env bash
# bg-id.sh — read the new SHORT id out of `claude --bg` output, in one place.
#
# Two parsers disagreed before this file: promote-session.sh took field 3 of the `^backgrounded` line, and wake-session.sh took the first hex token of 6 or more characters on that line. A third copy was on its way into a tickle job. This is the one parser; source it, or run it.
#
#   SOURCED:  . claude/lib/bg-id.sh; new_id=$(printf '%s' "$out" | bg_id) || die "..."
#   RUN:      claude --bg … 2>&1 | bash claude/lib/bg-id.sh
#
# IN   `claude --bg` output (stdout and stderr together) on stdin.
# OUT  the short id and a newline on stdout, exit 0. On failure: nothing on stdout, a message on stderr that names what was seen, exit 1. It never guesses.
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
# The colour codes come even when stdout is a pipe. The name after the second `·` is optional (a copy started without --name has none), and a name can hold a hex word, so only the token straight after `backgrounded ·` is the id. A "started a copy as <id>" note names the new id too; it must agree.
#
# THE RULE: strip CR and colour codes, apply backspaces, strip other control characters; the candidates are the token right after `backgrounded ·` on every `backgrounded` line, and the id after "started a copy as" or "resumed as" in a note. Exactly one distinct candidate, 8 lowercase hex characters, is the answer. None, or two different ones, is a failure. The id the note names as the ORIGINAL ("session 05ab1bf4 is already running") is not a candidate: wake-session.sh reads it to spot a fork, by its own sed.

bg_id() {
  local raw clean cands n
  raw=$(cat)
  # A backspace erases the character before it (a tty echoes ^D and then two backspaces before the first line), so backspaces are applied before the other control characters go.
  clean=$(printf '%s\n' "$raw" | tr -d '\r' | sed -E $'s/\x1b\\[[0-9;?]*[A-Za-z]//g' | LC_ALL=C sed -e $':a\ns/[^\x08]\x08//\nta' | LC_ALL=C tr -d '\000-\010\013\014\016-\037')
  cands=$(printf '%s\n' "$clean" | LC_ALL=C awk '
    /^[[:space:]]*backgrounded[[:space:]]/ {
      line = $0; sub(/^[[:space:]]*backgrounded[[:space:]]*/, "", line)
      if (substr(line, 1, 2) == "\302\267") line = substr(line, 3)   # the middle dot, U+00B7, in UTF-8
      sub(/^[[:space:]]*/, "", line)
      tok = line; sub(/[^0-9A-Za-z].*$/, "", tok)
      if (tok ~ /^[0-9a-f]{8}$/) print tok; else print "BAD:" (tok == "" ? "(nothing)" : tok)
    }
    {
      rest = $0
      while (match(rest, /(started a copy as|resumed as) [0-9a-f]{8}([^0-9A-Za-z]|$)/)) {
        hit = substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH)
        sub(/^(started a copy as|resumed as) /, "", hit); print substr(hit, 1, 8)
      }
    }' | sort -u)
  n=$(printf '%s' "$cands" | grep -c . || true)
  if printf '%s\n' "$cands" | grep -q '^BAD:'; then
    printf 'bg-id: a backgrounded line holds no 8-hex id after "backgrounded ·" (saw %s) in: %s\n' "$(printf '%s\n' "$cands" | sed -n 's/^BAD://p' | head -n 1)" "$clean" >&2
    return 1
  fi
  if [ "$n" = 0 ]; then
    printf 'bg-id: no id in the claude --bg output (no "backgrounded · <id>" line, no "started a copy as <id>"): %s\n' "${clean:-(empty)}" >&2
    return 1
  fi
  if [ "$n" != 1 ]; then
    printf 'bg-id: %s different ids in the claude --bg output (%s), and only one can be the new session: %s\n' "$n" "$(printf '%s' "$cands" | tr '\n' ' ' | sed 's/ $//')" "$clean" >&2
    return 1
  fi
  printf '%s\n' "$cands"
}

# Run as a command: read stdin, print the id.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  bg_id
  exit $?
fi
