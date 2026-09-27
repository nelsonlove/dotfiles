#!/usr/bin/env bash
# _fleet-ranks.sh — the fleet's rank line and ship codes, in one place.
#
# NOT EXECUTABLE ON ITS OWN. It is sourced, and it defines functions and two constants and does nothing
# else: no `set`, no output, no side effect, so a caller's own `set -euo pipefail` and traps are untouched.
# The leading underscore says the same thing — it is a library beside the scripts, not a command.
#
# WHO SOURCES IT: `claude/bin/wake-session.sh` and `claude/bin/promote-session.sh`. Nothing else reads a
# rank today — `rename-notebook.sh` and all six hooks were read and carry no rank table, so this file has
# exactly two consumers and the survey that established that is in `docs/fleet-machinery/`.
#
# WHY IT EXISTS: the two consumers held byte-identical copies of `rank_of_agent`, `word_of_rank`,
# `ship_of_name`, `ship_is_known` and `KNOWN_SHIPS`, and a copy of `rank_of_name` that differed IN THE
# COMMENT ONLY — the case arms identical, the sentence above them not. That is what a hand-maintained
# duplicate looks like shortly before it stops being identical at all, and the rank line is the one thing
# in the fleet that must never differ between two scripts: it decides who may wake and promote whom.
#
# RULE 19 is what this table serves — 01.65 Operator's console, Nelson's rule that a rank reaches only
# ranks below its own, and that the accept verbs are his alone. The numbers here are the whole of the
# machine-readable part of that rule, which is why they live in one file with one header.
#
# ADDING A SHIP CODE IS ONE LINE HERE: `KNOWN_SHIPS` below. Nothing else needs touching, because both
# consumers ask `ship_is_known` rather than carrying their own list. Adding or renaming a RANK is two
# lines — `rank_of_name` and `word_of_rank` — and it is a ruling, not a patch, because it changes who may
# reach whom.
#
# Works under /bin/bash 3.2 (macOS). Needs nothing but the shell.

# --- the rank line ---------------------------------------------------------------------------------
# Smaller number = higher rank. Repository variants share the rank of their base.
#
# `[A0]`, the rear admiral, is rank -1: the session Nelson placed between himself and the captains on
# 2026-09-26. The table is NUMBERED rather than shifted so that C0..L0 keep the numbers they have always
# had in both scripts and in every battery case. A0 is matched on the BARE code alone, because it carries
# no ship code — it sits above every ship — so `[A0-CC]` is not the rear admiral and is not a rank code at
# all; it reads as unknown and is refused. (That arm once accepted `"[A0-"*` as well, which made
# `[A0-CC] impostor` the real rear admiral to both scripts and contradicted this very paragraph. Found by
# the reviewer of #56.)
rank_of_name() {
  case "$1" in
    "[A0]"*) echo -1 ;;   # the bare code only — see the paragraph above
    "[C0]"*|"[C0-"*) echo 0 ;;
    "[C1]"*|"[C1-"*) echo 1 ;;
    "[C2]"*|"[C2-"*) echo 2 ;;
    "[L0]"*|"[L0-"*|"[L1]"*|"[L1-"*) echo 3 ;;  # [L1] was the lieutenant code until 2026-09-24
    *) echo 9 ;;
  esac
}

# THE CALLER'S rank, which is not always a rank code. This is deliberately a separate function from
# `rank_of_name`, with an empty table of its own today: a caller that is NOT a fleet session — the accept
# verbs' own write path, which acts for Nelson — is a first-class arm here rather than a special case
# bolted onto the rank codes later. The arm package 5 adds looks like this, and nothing else changes:
#
#     human:nelson) echo -2 ;;   # the verb's write path, acting for the admiral himself
#
# Until then the table is empty and every caller falls through to the rank codes, so this function and
# `rank_of_name` return the same answer for every input the fleet has today. Both consumers call THIS one
# for `--by`, so that adding the arm is one line in one file.
rank_of_caller() {
  case "$1" in
    # no non-rank callers yet; see the paragraph above
    *) rank_of_name "$1" ;;
  esac
}

# The rank of an agent DEFINITION name, as `~/.claude/agents/<name>.md` and `claude agents` spell it.
# There is no A0 definition: the rear admiral is a session Nelson placed, not a rank a definition carries.
rank_of_agent() {
  case "$1" in
    captain) echo 0 ;;
    commander) echo 1 ;;
    lieutenant-commander|lieutenant-commander-repository) echo 2 ;;
    lieutenant|lieutenant-repository) echo 3 ;;
    *) echo 9 ;;
  esac
}

# The words, for a sentence a human reads.
word_of_rank() {
  case "$1" in
    -1) echo "rear admiral" ;;
    0) echo captain ;;
    1) echo commander ;;
    2) echo "lieutenant commander" ;;
    3) echo lieutenant ;;
    *) echo unknown ;;
  esac
}

# The bare code for a rank, for a message that names one.
bare_code_of_rank() {
  case "$1" in -1) echo "[A0]" ;; 0) echo "[C0]" ;; 1) echo "[C1]" ;; 2) echo "[C2]" ;; 3) echo "[L0]" ;; *) echo "[??]" ;; esac
}

# The coded form a new name must carry, given a rank and a ship. DERIVED from `bare_code_of_rank` rather
# than carrying its own copy of the codes: the first version of this file hardcoded them a second time,
# which put the rank codes twice inside the one file whose purpose is to hold them once, made the header's
# "adding a rank is two lines" false (it was four), and silently changed `code_of_rank -1` from `[A0-CC]`
# to `[??-CC]`. That input is unreachable today — `--to` only ever yields 1, 2 or 3 — but the construction
# test did not cover it either, so nothing would have caught the day it became reachable. Found by the
# review of #61.
code_of_rank() {  # $1 = rank, $2 = ship code
  # `local`, because this file is SOURCED: an unqualified assignment here is a global, and would clobber a
  # caller variable of the same name.
  local bare
  bare=$(bare_code_of_rank "$1")
  printf '%s-%s]' "${bare%]}" "$2"
}

# --- the ships -------------------------------------------------------------------------------------
# CC is the Claude Code ship, OB the obsidian ship, HS the home server (captain `[C0-HS] orange`), all
# three ruled 2026-09-26. FL is not a ship but the marker of a floating session shared across captains,
# and it is listed beside them because it is what such a name carries.
#
# ADD A SHIP HERE AND NOWHERE ELSE. `FLOATING_SHIP` sits directly below on purpose: `FL` appears both in
# the list and as the floating marker, and the survey in `docs/fleet-machinery/` flags that separating the
# two is how they drift apart.
KNOWN_SHIPS="CC OB HS FL"
FLOATING_SHIP="FL"

# The ship a name declares — `CC` in `[L0-CC] dotfiles` — and empty for a bare `[L0] dotfiles`, which is
# never guessed at: a wrong ship code files a session under the wrong captain, and only Nelson renames it.
ship_of_name() {
  printf '%s' "$1" | sed -n -E 's/^\[[A-Za-z][0-9]-([A-Za-z]{1,4})\].*/\1/p'
}

ship_is_known() {
  case " $KNOWN_SHIPS " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}
