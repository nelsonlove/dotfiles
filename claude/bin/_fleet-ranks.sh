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
    # THE ARM THIS FUNCTION WAS BUILT FOR, landed by package 5. `human:nelson` is the accept verbs' own
    # write path: the verb runs inside Obsidian when NELSON CLICKS, so it has no session and no rank, and
    # without this it could not tell a session that its item was verified. Rank -2, above the rear admiral,
    # because the click is the admiral's own hand and a ruling of his must not sit unread behind a rank
    # check. Ruled by [A0] rear admiral on 2026-09-27 inside Nelson's "get it built", in the queue note
    # "Rule the two calls in the verified-item notifier before it is built".
    #
    # DISCIPLINE WITH A RECORD, NOT A LOCK, and the ruling says so in as many words: `--by` is not
    # authenticated — it is a string a caller supplies — so any session could pass this, exactly as any
    # session could already write a stamp or a name it did not earn. What it buys is that the verb's wake is
    # attributed and logged in his name, so a wake nobody can account for is VISIBLE in the log. What it
    # cannot do is stop a session that decides to lie, and the guard against that is the same as for
    # `verified` itself: the act is in the log, and the fleet reads the log.
    human:nelson) echo -2 ;;
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
# three ruled 2026-09-26; MA is the macOS ship (captain `[C0-MA] macos`), ruled 2026-09-29 on Nelson's
# "A, MA". The eight area ships were ruled the same day (log 2026-09-29T03:35), one per life area, under
# `[A0] areas admiral`: PE 10-19 Personal, PP 20-29 People, HH 30-39 Household, FN 40-49 Financial, ED 50-59
# Education & research, WK 60-69 Work, HB 70-79 Hobbies & media, DV 80-89 Divorce (guarded: its captain
# starts only when Nelson starts it). FL is not a ship but the marker of a floating session shared across captains, and it is listed
# beside them because it is what such a name carries.
#
# ADD A SHIP HERE AND NOWHERE ELSE. `FLOATING_SHIP` sits directly below on purpose: `FL` appears both in
# the list and as the floating marker, and the survey in `docs/fleet-machinery/` flags that separating the
# two is how they drift apart. A refusal that names the ships builds the words with `ships_in_words`, so
# no sentence types the list out by hand (it did until 2026-09-29, and adding MA had to edit it).
KNOWN_SHIPS="CC OB HS MA PE PP HH FN ED WK HB DV FL"
FLOATING_SHIP="FL"

# --- the admirals and the guarded ship ------------------------------------------------------------------
# Nelson's areas ruling (log 2026-09-29T03:35) put two sessions at A0, and `rank_of_name` cannot tell them
# apart: both are the bare `[A0]` code. So an admiral is matched here by its FULL NAME, and each one reaches
# only its own ships. Any other `[A0] …` name is refused, because a name that merely starts with the code is
# not a session Nelson placed. The two lists together are KNOWN_SHIPS, each ship in exactly one of them
# (the table test checks both properties); FL is on the rear admiral's side, where every floating session
# has lived so far.
REAR_ADMIRAL="[A0] rear admiral"
AREAS_ADMIRAL="[A0] areas admiral"
REAR_ADMIRAL_SHIPS="CC OB HS MA FL"
AREAS_ADMIRAL_SHIPS="PE PP HH FN ED WK HB DV"
# DV (80-89 Divorce) is guarded: its captain starts only when Nelson starts it. No script wakes or promotes
# a session on DV or into DV, whoever the caller is, because the only way into DV is Nelson. This binds
# honest callers of these scripts only: `--by` is self-declared, a SendMessage to a stopped session wakes it
# with no script, and a bare `claude --bg --name "[C0-DV] …"` starts one with no script. The tripwire hook
# `claude/hooks/dv-tripwire.sh` watches the bare command line; nothing watches SendMessage.
GUARDED_SHIPS="DV"

ship_is_guarded() {
  [ -n "${1:-}" ] || return 1
  case " $GUARDED_SHIPS " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# ship_refusal <by> <by-rank> <ship>: the one sentence both scripts refuse with when <by> may not act on a
# session of <ship> (empty for a bare-named session), and nothing when it may. It is the SHIP rule only:
# the rank rule and the reporting line stay in each script. Called once per ship a change touches, so a
# promotion checks both the target's ship and the new name's.
ship_refusal() {
  local by="$1" rank="$2" ship="$3" list
  if ship_is_guarded "$ship"; then
    printf 'refused: ship %s is guarded; no script wakes or promotes a session on it or into it, whoever asks, because only Nelson starts a session there' "$ship"
    return 0
  fi
  [ "$rank" = -1 ] || return 0
  case "$by" in
    "$REAR_ADMIRAL") list="$REAR_ADMIRAL_SHIPS" ;;
    "$AREAS_ADMIRAL") list="$AREAS_ADMIRAL_SHIPS" ;;
    *) printf "refused: '%s' is not one of the two admirals ('%s', '%s'); an admiral is matched by its full name" "$by" "$REAR_ADMIRAL" "$AREAS_ADMIRAL"; return 0 ;;
  esac
  if [ -z "$ship" ]; then
    # A bare-named session predates the ship codes, and every one of them is on the rear admiral's side.
    [ "$by" = "$REAR_ADMIRAL" ] || printf 'refused: the session carries no ship code, and %s reaches only the area ships (%s)' "$by" "$AREAS_ADMIRAL_SHIPS"
    return 0
  fi
  case " $list " in
    *" $ship "*) ;;
    *) printf '%s' "refused: $by does not reach ship $ship; it reaches $list, and the other admiral's ships are not its own" ;;
  esac
}

# The real ships in words, for a refusal: "CC, OB, … or DV", read from KNOWN_SHIPS. FL is left out, because the sentences that
# use this name it on its own ("FL for a floating session").
ships_in_words() {
  local out="" last="" c
  for c in $KNOWN_SHIPS; do
    [ "$c" = "$FLOATING_SHIP" ] && continue
    if [ -n "$last" ]; then out="${out:+$out, }$last"; fi
    last="$c"
  done
  if [ -n "$out" ]; then printf '%s or %s' "$out" "$last"; else printf '%s' "$last"; fi
}

# The ship a name declares — `CC` in `[L0-CC] dotfiles` — and empty for a bare `[L0] dotfiles`, which is
# never guessed at: a wrong ship code files a session under the wrong captain, and only Nelson renames it.
ship_of_name() {
  printf '%s' "$1" | sed -n -E 's/^\[[A-Za-z][0-9]-([A-Za-z]{1,4})\].*/\1/p'
}

ship_is_known() {
  case " $KNOWN_SHIPS " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}
