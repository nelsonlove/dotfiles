#!/usr/bin/env bash
# accept-verb-guard.sh — PreToolUse hook refusing any tool call that invokes an accept verb.
#
# 01.65 Operator's console rule 19, Nelson's words: "No rank invokes an accept verb (verify, reopen,
# request revision, answer) by any means, not through the palette API, a command call or an eval, not
# for testing and not on a test artifact: the verb's first act is a prompt in the admiral's own
# window, so an agent invoking it is an agent at the perimeter; a verb is tested by the admiral
# clicking, or by a dry-run path that never calls the choice."
#
# 01.41 The accept perimeter rule 2: "The accepter's identity is asked for, never passed in. If it
# could arrive as a parameter, an agent could supply it, and the whole rule would be one variable
# wide." Rule 3 of the same note says the refusal belongs in the code path, "not by policy text an
# agent is expected to have read. By a check that runs first and returns an error." This hook is that
# check for the agent side, and it exists because the verbs' own guard is a string compare on
# `_invoked-by` where an absent key reads as human — so it holds for a human at the palette and not
# against a tool call. Nothing here touches the verbs themselves.
#
# A sibling of pause-guard.sh beside it, not a widening of it: same stdin-JSON read, same exit-0
# allow / exit-2 block convention (Claude Code feeds a hook's stderr back to the model on exit 2),
# same EXIT trap rewriting every unexpected exit to 2. It registers on TWO of that hook's three
# matchers, `Bash` and `mcp__vault-mcp__.*`, and deliberately not on `Edit|Write|NotebookEdit|MultiEdit`,
# because those tools cannot invoke a verb — which is also what leaves a session a way to write about
# one. Two guards, two reasons, one file each.
#
# FAILS CLOSED, and here it parts company with its sibling on purpose: pause-guard.sh fails OPEN with a
# loud warning when its own dependency is missing, under 01.41 rule 7c, because a pause that cannot be
# read must not lock a session out of fixing the note. Rule 19 admits no such allowance — a call whose
# contents cannot be read is a call that must not run — so a missing `jq` blocks here. The asymmetry is
# real and it is the right way round for each.
#
# Malformed input, unreadable input, a missing tool name, a `jq` that is not there, and
# any unexpected shell failure all BLOCK. There is no allow path, no override flag and no environment
# variable that turns this off: an escape hatch in this hook is the hatch the rule exists to close.
#
# WHAT IT MATCHES, and the line it is careful about. The four verbs are named by their choice names
# ("Verify current note", "Reopen current note", "Request revision", "Answer current note"), by the
# basenames of the scripts behind them (verify-current-note, reopen-current-note, request-revision,
# answer-current-note), and by their QuickAdd ids, which carry the choice name inside the path
# (`qan:…/00.14 QuickAdd choices/Verify current note.md#choice`). But a mention is not an invocation:
# this session has written the phrase "Verify current note" into a PR body, a log entry and a policy
# note today, and a guard that blocked those would stop the fleet documenting its own perimeter. So a
# name alone never blocks. A name blocks when it appears together with something that INVOKES:
#   * `executeChoice(` or the QuickAdd API — the documented way to run a choice from code;
#   * `executeCommandById` or a palette command call;
#   * a `qan:` or `quickadd:` choice id, which only ever appears in order to run one;
#   * the obsidian CLI in a command or eval form (`obsidian … command=…`, `… eval`, `code=…`);
#   * a tool whose whole purpose is to run a command (`*run_command*`), including
#     `mcp__vault-mcp__obsidian_run_command`.
# An ordinary QuickAdd choice passes, because its id carries a different name; a read passes; a vault
# write passes even when its content discusses the verbs, which is the case that made this shape
# necessary rather than a blunt substring match.
#
# What it cannot catch, said plainly rather than implied: a name assembled at runtime from pieces
# (string concatenation inside an eval) is invisible to a text matcher. The rule stands above the
# hook; this closes the shapes a session would actually reach for, and the verbs' own `_invoked-by`
# compare remains the reason a belt is wanted as well as braces.
#
# NO SIZE CAP, on purpose, and why that is safe. pause-guard.sh caps the text it inspects at 2000
# characters; this one must not, because a cap is a bypass — put the invocation after the cut and the
# guard never sees it. The cost of reading everything is bounded instead: the payload is searched with
# grep over a scratch file rather than matched against a shell variable, which measured 5.3 s for a
# 10 MB payload against 17 s for the variable form, and 0.7 s for a 1 MB one, with the invocation
# hidden at the very end each time and still refused. That matters because a hook killed by a harness
# timeout never reaches its EXIT trap, and a hook that does not exit 2 is read as allow: the fastest
# safe answer is the one that cannot be interrupted. No `timeout` is set on the hook entry either, so
# it inherits the harness default rather than a shorter budget of our own making.
#
# THE FALSE REFUSAL IT KEEPS, deliberately. Prose that QUOTES an invocation is refused like an
# invocation: a shell heredoc appending `command="…/Verify current note.md#choice"` to the fleet log
# reads, to any text matcher, exactly like the call it describes, and no amount of care separates the
# two. That refusal was measured, not assumed — the log-append shape above is a test case. The cost is
# borne the right way round: a session that wanted to write about a verb rephrases (name the verb
# without pasting a command form) or writes through `Write`/`Edit`, which these matchers do not cover,
# while a session that wanted to RUN one is stopped. A guard for this rule may cost a sentence; it may
# not risk a call.
set -u

# Claude Code reads only 0 (allow) and 2 (block); every other code is a non-blocking error, which for
# this guard would mean the call goes through. Rewrite every unexpected exit to 2.
scratch=""
on_exit() {
  exit_rc=$?
  [ -z "$scratch" ] || rm -f "$scratch" "$scratch.sq"
  [ "$exit_rc" -eq 0 ] && exit 0
  exit 2
}
trap on_exit EXIT

refuse() {
  printf 'REFUSED by accept-verb-guard: %s\n' "$1" >&2
  printf 'The accept verbs — Verify current note, Reopen current note, Request revision, Answer current note — are Nelson'\''s alone.\n' >&2
  printf '01.65 Operator'\''s console rule 19: no rank invokes an accept verb by any means, not through the palette API, a command call or an eval, not for testing and not on a test artifact; the verb'\''s first act is a prompt in the admiral'\''s own window, so an agent invoking it is an agent at the perimeter.\n' >&2
  printf '01.41 The accept perimeter rule 2: the accepter'\''s identity is asked for, never passed in.\n' >&2
  printf 'A verb is tested by Nelson clicking it, or by a dry-run path that never calls the choice. There is no flag that lifts this.\n' >&2
  printf 'If you are quoting rather than calling: describe the verb instead of pasting the call — name it, and leave out the command form, the choice id and the eval — or write through Write/Edit, which this guard does not cover.\n' >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || refuse "jq is not available, so this call cannot be read; a guard that cannot read fails closed"

input=$(cat 2>/dev/null) || refuse "the hook input could not be read"
[ -n "$input" ] || refuse "the hook input was empty"
printf '%s' "$input" | jq -e . >/dev/null 2>&1 || refuse "the hook input is not valid JSON"

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null) || refuse "the tool name could not be read"
[ -n "$tool" ] || refuse "the call carries no tool name"

# --- normalising the payload ----------------------------------------------------------------------
# Two forms are written to disk rather than held in a shell variable, and searched with grep, because
# a `case` match over a multi-megabyte variable took 17 seconds in review — and a guard that misses a
# harness timeout is killed by a signal, which the EXIT trap never sees and the harness reads as allow.
# grep over the same payload is milliseconds.
#
#   .sq  — the "squashed" form: percent-decoded, lowercased, then EVERY character that is not a letter
#          or a digit removed. One pass closes a whole family of dodges at once: a double space, a tab,
#          a carriage return, a non-breaking space, an underscore or any other separator between the
#          words of a verb's name, and `%20` in a choice id, all land on the same string.
#   the plain form — percent-decoded, lowercased, whitespace collapsed. Used for the markers, which
#          need their punctuation (`executechoice(`, `command=`, `qan:`).
# The payload is read as its DECODED scalar values, not with `tostring`: `tostring` re-serialises, so a
# real tab inside a command comes back as the two characters `\t`, and squashing that leaves a stray
# `t` in the middle of the name — "verify\tcurrent\tnote" became "verifytcurrenttnote" and slipped
# through. Walking the scalars hands over the characters the tool would actually receive. Any escape
# that still survives a nested encoding is flattened to a space as well.
scratch=$(mktemp -t accept-verb-guard) || refuse "no scratch file could be made, so this call cannot be read"
printf '%s' "$input" | jq -r '(.tool_input // {}) | [.. | scalars | tostring] | join(" ")' 2>/dev/null \
  | perl -pe 's/\\[nrt]/ /g; s/\\u00a0/ /gi; s/%([0-9a-fA-F]{2})/chr(hex($1))/ge; $_ = lc $_; s/\xc2\xa0/ /g; s/\s+/ /g' > "$scratch" \
  || refuse "the tool input could not be normalised"
[ -s "$scratch" ] || printf '{}' > "$scratch"
perl -pe 's/[^a-z0-9]//g' "$scratch" > "$scratch.sq" || refuse "the tool input could not be normalised"

# The tool name is lowercased too: it was the one thing compared case-sensitively, which let a payload
# through under a differently-cased spelling of the same tool.
tool_l=$(printf '%s' "$tool" | tr '[:upper:]' '[:lower:]')

contains() { grep -q -F -- "$1" "$scratch" 2>/dev/null; }
squashed() { grep -q -F -- "$1" "$scratch.sq" 2>/dev/null; }

# --- is an accept verb named? ---------------------------------------------------------------------
# Matched on the squashed form, so every way of separating the words is one case.
verb=""
for v in verifycurrentnote reopencurrentnote requestrevision answercurrentnote; do
  if squashed "$v"; then verb="$v"; break; fi
done

# --- is this an invocation, rather than a mention? ------------------------------------------------
how=""
case "$tool_l" in
  *run_command*|*runcommand*|*execute*) how="the tool $tool exists to run a command" ;;
esac
if [ -z "$how" ]; then
  if contains "executechoice("; then how="it calls executeChoice(, the QuickAdd API for running a choice"
  elif contains "executecommandbyid"; then how="it calls executeCommandById, the palette API"
  elif contains "quickadd:choice:" || contains "qan:"; then how="it carries a QuickAdd choice id, which exists only to run one"
  elif contains "obsidian" && { contains "command=" || contains "code=" || contains " eval" || contains "eval "; }; then
    how="it drives the obsidian CLI in a command or eval form"
  # Keystroke automation reaches the palette without any API at all, which is how a verb could be run
  # with its name spelled in plain text and none of the markers above present. Nelson's own standing
  # rule keeps GUI automation in his hands, so this is a refusal on two counts.
  elif contains "osascript" || contains "system events" || contains "keystroke" || contains "cliclick" || contains "key code"; then
    how="it drives the GUI by keystroke automation, which reaches the command palette directly"
  elif contains "quickadd"; then how="it reaches the QuickAdd plugin"
  fi
fi

if [ -n "$verb" ] && [ -n "$how" ]; then
  refuse "this call names the accept verb '$verb' and $how"
fi

# --- an invocation this guard cannot read is refused unread ----------------------------------------
# A choice name assembled at runtime, decoded from base64, or fetched through a variable is invisible
# to any text matcher — so when a call plainly invokes something AND hides what it invokes, the answer
# is no. A guard that cannot read what is being run must not allow it, and an ordinary choice named in
# plain text is unaffected, which is what keeps the negative cases passing. 01.41 rule 4 points the
# same way: anything that can run arbitrary vault code is denied to agents by default.
if [ -n "$how" ]; then
  hidden=""
  if contains "base64 -d" || contains "base64 --decode" || contains "| base64" || contains "atob("; then
    hidden="it decodes its payload at runtime"
  elif contains "fromcharcode"; then hidden="it builds a string from character codes"
  elif contains '$('  || contains '${' || contains '`'; then hidden="it substitutes a shell value into the call"
  elif contains '" + ' || contains "' + " || contains '" . ' || contains ".concat("; then hidden="it concatenates the name at runtime"
  fi
  if [ -n "$hidden" ]; then
    refuse "this call invokes a choice or command and $hidden, so which verb it runs cannot be read — an unreadable invocation is refused unread"
  fi
fi

# A command-runner carrying a choice id that names no verb, in plain text, is an ordinary choice: it
# passes here, and the pause guard beside this one still has its own say.
exit 0
