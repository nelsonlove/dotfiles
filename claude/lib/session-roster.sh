#!/usr/bin/env bash
# session-roster.sh — the four keys a notebook entry carries about its session, and what a resume may do with them.
#
# THE ROSTER, ruled 2026-09-29: a session's notebook entry IS the record of that session, so it carries
# `session-id` (the full 36-character sessionId), `session` (the display name), `agent` (the rank definition
# it runs as) and `cwd`. `claude/hooks/notebook-name-sync.sh` writes `agent` and `cwd` beside the id on a
# running session's next turn — never on a resume — and this file is what reads them back.
#
# WHY A SESSION NEEDS ITS OWN RECORD. `claude rm` removes a job: the listing row, the job state and the saved
# options all go, and the transcript stays. After that the only place the session's name, agent and directory
# still exist is its notebook entry. Without them a post-rm resume can bring the conversation back but not the
# session — no rank persona, a derived name — which is worse than leaving it asleep.
#
# THE HAND RULE, in these words because a person running this by hand gets it wrong in the other direction:
# WHILE A STOPPED SESSION'S JOB STILL EXISTS, RESUME IT FLAGLESS. Its saved options (`--agent`, `--name`,
# `--model`) come back under the same id, and ANY flag forks a copy that carries only the flags given — the
# captain's own id `6b6a8cd6` is such a fork, which is why its job records no `--agent`. Only AFTER
# `claude rm` has removed the job do you pass `--agent` and `--name`, taken from the entry, and then the id
# is kept. Flags first is how a session becomes two sessions.
#
# THE TWO ID FORMS, and every script that takes an id must say which it takes: `claude stop` takes the SHORT
# job id, `--resume` needs the FULL sessionId. Take the short form from the listing row when one exists;
# derive it (the first 8 characters) only when there is no row, because that is an observed regularity across
# 14 live sessions and not a documented contract.
#
# A SHORT ID IN `session-id` IS REFUSED ON A RESUME AND SKIPPED ON A SWEEP, and the reason is a measurement:
# **324 historical entries hold a short or junk value** in that key (8-character ids, plus literal
# `vaultbridge` and `.inf`) against about thirty holding a full one, because that is what the key meant before
# this ruling. The 324 reproduces exactly; the TOTAL moves between runs — 351, 354, 357 in three measurements
# an hour apart — because sessions write entries while the count is being taken, which is why the suite prints
# the counts and asserts only the properties. Refusing on the
# resume path protects the one session being woken; refusing on a sweep would refuse 324 records that are
# simply old. So the sweeper reads a short id as "not the four keys" and skips, and NOBODY should tighten
# that skip into a refusal without re-measuring the population first.
#
# AGENT IS READ, NEVER INFERRED. Order: the job state's `template`, then the registry's `agent`; if both are
# absent the caller refuses rather than guessing. The ruled definition (the OB sweep, Nelson "fine,
# reasonable"): the agent is the `--agent` value in the job's `respawnFlags`, or `claude` when none was
# passed. `claude` is the common case — 4 of 14 live sessions tonight — and it is passed back VERBATIM, never
# mapped to a rank. A `[C0-…]` name with `agent: claude` is an ordinary session Nelson opened himself.
#
# WHICH `cwd`, MEASURED. A session records two: the directory its job started in, and the directory it is in
# now. They differ the moment a session enters a worktree. What settles it is where the CONVERSATION lives:
#
#   job state cwd   /Users/nelson/repos/system/dotfiles
#   registry cwd    /Users/nelson/repos/system/dotfiles/.claude/worktrees/feat+session-roster
#   the transcript  ~/.claude/projects/-Users-nelson-repos-system-dotfiles--claude-worktrees-feat-session-roster/509170bb-….jsonl
#
# The transcript sits under the CURRENT directory, not the starting one — Claude Code MOVES it when a session
# changes directory and leaves an empty `…<id>.superseded-<ms>` marker behind in the old project. Both markers
# are on this machine (`509170bb` under the dotfiles root, `52332124` under an obsidian-mcp-suite worktree) and
# they are the evidence. So the registry's cwd is read first and the job state's is the fallback, and the rule
# behind the key is: **"resume where the transcript is"; the `cwd` key is only our best record of that.**
#
# THE PROJECT DIRECTORY NAME IS LOSSY, which decides what the check below may do. A cwd becomes a project
# directory by replacing every character that is not `[A-Za-z0-9-]` with `-` — derived from all six live
# cwd/directory pairs, not assumed; the first guess (`/` and `.` only) was wrong, and `feat+session-roster` →
# `feat-session-roster` is the pair that caught it. The consequence: `…/worktrees/feat+session-roster` and
# `…/worktrees/feat-session-roster` produce the SAME directory name, so a project directory cannot be decoded
# back into a path. A script that found a transcript under some other project directory therefore has no path
# to resume in, and the honest answer is a refusal that names what it found.
#
# Works under /bin/bash 3.2 (macOS). Needs nothing but the shell and awk.

# --- one entry's keys --------------------------------------------------------------------------------
# Sets `roster_session`, `roster_id`, `roster_agent` and `roster_cwd` — those four and nothing else. An
# earlier version of this comment also promised a `roster_status`, which nothing ever set; a caller that wants
# the status calls `session_status_of` itself. Always returns 0: an entry that carries
# nothing is a fact about the entry, not an error here — what a caller does about it is the caller's contract.
roster_read() {  # $1 = the entry's path
  roster_session=""; roster_id=""; roster_agent=""; roster_cwd=""
  [ -n "${1:-}" ] && [ -f "$1" ] || return 0
  roster_block=$(awk 'NR == 1 { if ($0 !~ /^---[ \t\r]*$/) exit 1; next }
                      /^---[ \t\r]*$/ { exit }
                      { gsub(/\r/, ""); print }' "$1" 2>/dev/null || true)
  [ -n "$roster_block" ] || return 0
  roster_session=$(roster_value "$roster_block" "session")
  roster_id=$(roster_value "$roster_block" "session-id")
  roster_agent=$(roster_value "$roster_block" "agent")
  roster_cwd=$(roster_value "$roster_block" "cwd")
  return 0
}

# One key out of a frontmatter block. The LAST occurrence wins, matching `claude/lib/session-status.sh` and the
# awk index in wake-session.sh; quotes come off after trailing whitespace, and a trailing ` # comment` goes,
# for the same reason and in the same order as that library — two readers of one note must not disagree.
# A QUOTED VALUE IS TAKEN WHOLE, and only an UNQUOTED one can carry a trailing comment. The writer quotes
# every value it writes, and the first version of this stripped ` # …` before removing the quotes — so
# `cwd: "/tmp/live #2"` became `"/tmp/live`, an unbalanced quote and a wrong directory. Inside quotes a hash
# is part of the value; outside them it starts a comment. Order decides which, and this is the order.
roster_value() {  # $1 = the block, $2 = the key
  rv_raw=$(printf '%s\n' "$1" \
    | grep -E "^[[:space:]]*$2[[:space:]]*:" \
    | tail -n 1 \
    | sed -E "s/^[[:space:]]*$2[[:space:]]*:[[:space:]]*//" \
    | sed -E 's/[[:space:]]+$//' || true)
  case "$rv_raw" in
    '"'*'"'*)  printf '%s' "$rv_raw" | sed -E 's/^"(.*)".*$/\1/' ;;
    "'"*"'"*)  printf '%s' "$rv_raw" | sed -E "s/^'(.*)'.*\$/\1/" ;;
    *)         printf '%s' "$rv_raw" | sed -E 's/[[:space:]]+#.*$//' | sed -E 's/[[:space:]]+$//' ;;
  esac
  return 0
}

# A full sessionId and nothing else: 36 characters, hex and dashes in the 8-4-4-4-12 shape. `--resume` given
# anything shorter starts a NEW session with the message as its prompt, which is how a junk session named
# after a wake message once appeared.
roster_id_is_full() {  # $1 = a session-id value
  # THE SHAPE IS ENFORCED, not just the length. The first version tested a 36-character glob and a character
  # class that included `-`, so `------------------------------------` and `aaaaaaa--1111-…` were both
  # accepted — the review of #71 proved it. A junk id of that shape would have become a sweeper candidate and
  # a resume target. Each group is hex and only the four separators are dashes.
  case "${1:-}" in
    [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) return 0 ;;
  esac
  return 1
}

# --- the newest entry for one session id, across both roots ------------------------------------------
# `roster_entry` is the path, or empty. The newest by the timestamp in the FILENAME, which is the same rule
# wake-session.sh uses for a name: a session writes a new entry rather than reopening an old one, so the
# newest is the live one. 18 ids in tonight's notebook carry more than one entry, so this is a real case.
roster_newest_entry_for_id() {  # $1 = full session id, $2… = the FOUR root arguments
  roster_entry=""
  roster_entry_count=0
  ros_id="${1:-}"
  shift || true
  [ -n "$ros_id" ] || return 0
  ros_best_stamp=""
  while IFS= read -r ros_f; do
    [ -n "$ros_f" ] || continue
    roster_read "$ros_f"
    [ "$roster_id" = "$ros_id" ] || continue
    roster_entry_count=$((roster_entry_count + 1))
    ros_stamp=$(printf '%s' "${ros_f##*/}" | sed -E 's/.*([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{4}).*/\1/')
    case "$ros_stamp" in
      [0-9][0-9][0-9][0-9]-*) ;;
      *) ros_stamp="" ;;
    esac
    if [ -z "$roster_entry" ] || [ "$ros_stamp" \> "$ros_best_stamp" ]; then
      roster_entry="$ros_f"
      ros_best_stamp="$ros_stamp"
    fi
  done <<EOF
$(notebook_entry_files_of "$@")
EOF
  return 0
}

# --- the ended-entry line ------------------------------------------------------------------------------
# A session resumed under its own id must NOT reopen an entry that was closed while it slept. It happened
# tonight: `[C2-OB] spec steps` had its entry ended while stopped, was resumed under the same id, read
# `archived/ended` as stale and reopened it, which the policy forbids. So every resume path of ours adds one
# line to the wake message when the newest entry for that id is ended — and says NOTHING when it is running,
# when there is no entry, or when the id is short. Silence is the default: a wake must never fail because a
# record is missing or old.
#
# `roster_ended_line` is the line, or empty. The caller appends it to its message and nothing else.
roster_ended_line_for() {  # $1 = full session id, $2… = the FOUR root arguments
  roster_ended_line=""
  ros_eid="${1:-}"
  roster_id_is_full "$ros_eid" || return 0
  roster_newest_entry_for_id "$@"
  [ -n "$roster_entry" ] || return 0
  # A MISSING LIBRARY IS NOT A MISSING RECORD. Silence is right when the entry is running, when there is no
  # entry, or when the id is short — but when the status rule itself cannot be read, a silent "no line" is
  # indistinguishable from "the entry is running", and the line exists to stop a woken session reopening a
  # closed entry. So it still adds no line, and it says why once, where a human can see it.
  ros_state="absent"
  if command -v session_status_of >/dev/null 2>&1; then
    session_status_of "$roster_entry"
    ros_state="${sess_state:-absent}"
  else
    printf 'session-roster: the session-status rule is not sourced, so %s was not read; no ended-entry line was added\n' "$roster_entry" >&2
    return 0
  fi
  case "$ros_state" in
    ended)
      roster_ended_line="your entry $roster_entry was ended while you were stopped; open a new entry that points at it, and do not reopen it" ;;
  esac
  return 0
}

# --- the rank code in the name against the agent --------------------------------------------------------
# A disagreement refuses and prints BOTH values, the same shape as promote-session.sh refusing a `--name`
# whose rank code disagrees with its `--to`: a disagreement is the only thing that tells a human which of the
# two is stale, so resolving it in favour of either destroys the evidence.
#
# `claude` NEVER DISAGREES WITH ANYTHING. It is not a rank, it is what a session Nelson opened himself runs
# as, and it sits under rank-coded names all over the fleet — `[C0-OB] obsidian`, `[A0] rear admiral`,
# `[C1-OB] machinery` and `[C2-FL] vault-mcp-suite` tonight. Mapping it to a rank, or refusing it against one,
# would refuse a wake for four of fourteen live sessions.
# `roster_agree_state` SAYS WHICH FACT the return code stands for, because the first version returned 1 for
# seven different ones — no name, no agent, `claude`, no rank table, an unreadable name, an unreadable agent,
# and genuine agreement — and the first caller would have read "could not tell" as "agreed". One of:
#   `agree` `disagree` `not-a-rank` (the agent is `claude`) `unknown-name` `unknown-agent` `no-table` `no-input`
roster_agent_disagrees() {  # $1 = the display name, $2 = the agent value; sets `roster_disagreement`
  roster_disagreement=""
  roster_agree_state="no-input"
  ros_name="${1:-}"; ros_agent="${2:-}"
  [ -n "$ros_name" ] && [ -n "$ros_agent" ] || return 1
  if [ "$ros_agent" = "claude" ]; then roster_agree_state="not-a-rank"; return 1; fi
  if ! command -v rank_of_name >/dev/null 2>&1 || ! command -v rank_of_agent >/dev/null 2>&1; then
    roster_agree_state="no-table"; return 1
  fi
  ros_name_rank=$(rank_of_name "$ros_name")
  ros_agent_rank=$(rank_of_agent "$ros_agent")
  if [ "$ros_name_rank" = 9 ]; then roster_agree_state="unknown-name"; return 1; fi
  if [ "$ros_agent_rank" = 9 ]; then roster_agree_state="unknown-agent"; return 1; fi
  if [ "$ros_name_rank" = "$ros_agent_rank" ]; then roster_agree_state="agree"; return 1; fi
  roster_agree_state="disagree"
  roster_disagreement="the entry says agent '$ros_agent' (rank $ros_agent_rank) while its session name '$ros_name' carries rank $ros_name_rank; this is not resolved in favour of either, because the disagreement is what tells you which one is stale"
  return 0
}

# --- where the conversation actually is -----------------------------------------------------------------
# Before a post-rm resume, prove the transcript is under the directory we are about to resume in. `roster_
# transcript_state` is one of:
#
#   `here`       the transcript is under the recorded cwd's project directory — resume there.
#   `elsewhere`  it is under exactly one OTHER project directory. A REFUSAL, not a relocation, RULED
#                2026-09-29 after the lossiness was measured: the captain's first rule said "resume there",
#                and a project directory name cannot be decoded back into a path, so there is nothing to
#                resume in. The caller names both that directory and the recorded cwd, and a human resumes
#                from the right one by hand.
#   `none`       no project directory holds it. A refusal: resuming would start a NEW session.
#   `many`       more than one holds it. A refusal: which one is the conversation is not ours to guess.
#
# The projects root is an argument so a suite can point it at a temp directory; nothing here ever reads the
# real `~/.claude/projects` unless its caller passes that path in.
roster_transcript_dir_encode() {  # $1 = a cwd; prints the project directory NAME
  printf '%s' "${1:-}" | sed -E 's/[^A-Za-z0-9-]/-/g'
}

roster_transcript_check() {  # $1 = full session id, $2 = the recorded cwd, $3 = the projects root
  roster_transcript_state="none"
  roster_transcript_found=""
  ros_tid="${1:-}"; ros_tcwd="${2:-}"; ros_proj="${3:-}"
  [ -n "$ros_tid" ] && [ -n "$ros_proj" ] || return 0
  ros_want="$ros_proj/$(roster_transcript_dir_encode "$ros_tcwd")/$ros_tid.jsonl"
  if [ -n "$ros_tcwd" ] && [ -f "$ros_want" ]; then
    roster_transcript_state="here"
    roster_transcript_found="$ros_want"
    return 0
  fi
  ros_hits=""
  ros_n=0
  for ros_c in "$ros_proj"/*/"$ros_tid.jsonl"; do
    [ -f "$ros_c" ] || continue
    ros_n=$((ros_n + 1))
    ros_hits="$ros_hits$ros_c
"
  done
  if [ "$ros_n" = 0 ]; then
    roster_transcript_state="none"
  elif [ "$ros_n" = 1 ]; then
    roster_transcript_state="elsewhere"
    roster_transcript_found=$(printf '%s' "$ros_hits" | sed -n '1p')
  else
    roster_transcript_state="many"
    roster_transcript_found=$(printf '%s' "$ros_hits" | tr '\n' ' ' | sed -E 's/ $//')
  fi
  return 0
}
