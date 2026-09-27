#!/usr/bin/env bash
# accept-verb-guard.sh — PreToolUse hook refusing any tool call that INVOKES an accept verb.
#
# 01.65 Operator's console rule 19, Nelson's words: "No rank invokes an accept verb (verify, reopen,
# request revision, answer) by any means, not through the palette API, a command call or an eval, not
# for testing and not on a test artifact: the verb's first act is a prompt in the admiral's own
# window, so an agent invoking it is an agent at the perimeter."
#
# 01.41 The accept perimeter rule 2: "The accepter's identity is asked for, never passed in." Rule 3
# says where the refusal belongs: "in the code path, before it touches any file. Not by policy text an
# agent is expected to have read. By a check that runs first and returns an error." This hook is that
# check for the agent side, and it is needed because the verbs' own guard is a string compare on
# `_invoked-by` where an absent key reads as human — it holds for a person at the palette and not
# against a tool call. Nothing here touches the verbs themselves.
#
# WHY THIS IS THE SECOND VERSION. The first (dotfiles #53) matched a verb's name anywhere in a payload
# beside any of several markers, and it refused routine work across the fleet within the hour: a python
# heredoc writing prose about `eval` and `executeChoice`; a heredoc adding the rule-19 sentence to a
# spec note; a heredoc appending a notebook section that named the four verbs; and the write of a test
# harness whose own code quotes `executeChoice('Verify current note')` to stub it. It was reverted (#54).
# The captain's ruling for this version: discriminate by CALL SHAPE, not by vocabulary.
#
# WHAT COUNTS AS AN INVOCATION — the whole list, and nothing else:
#   1. a vault-mcp run tool: `mcp__vault-mcp__obsidian_run_command`, or any tool whose name carries
#      `run_command` or `execute_command`, whose payload names a verb (a looser `execute` in a tool's
#      name counts only when the name also says `obsidian` or `vault`, so that widening the matchers
#      later cannot make this vault rule judge some other server's `shortcuts_execute`);
#   2. the obsidian CLI with `command=` whose argument names a verb;
#   3. the obsidian CLI with `eval` or `code=` whose argument names a verb — this is where an
#      `executeChoice(...)` or `executeCommandById(...)` addressed to Obsidian lives;
#   4. keystroke automation — `osascript`/System Events, `cliclick`, `key code` — typing a verb's name,
#      which reaches the command palette with no API at all and was the gap a review found.
# Anything else is text. In particular `node`, `python3`, `bash <file>` and every other interpreter
# running a file is NOT an invocation shape: such a file cannot reach Obsidian's `app` object, so a
# harness that stubs `executeChoice` and asserts against it invokes nothing, however exactly it quotes
# the verbs it tests.
#
# WHAT COUNTS AS PROSE, and passes: the same words inside a heredoc body, a `printf`, a python or shell
# string, or any text written or appended to a file. The test is positional — a would-be invocation that
# appears AFTER the payload's first write boundary (`<<`, `>`, `>>`, `tee`, `.write(`, `writeFileSync`)
# is text being written, not a call being made. A real call still refuses when it redirects its own
# output, because the call comes before the redirect.
#
# THE ACCEPTED BOUNDARY, named rather than implied, and narrower than expected. A call whose argument
# this guard cannot read is not refused: a payload decoded from base64 at runtime, a choice id fetched
# through a variable, or a file written first and then fed to `obsidian eval` by substitution. A text
# guard cannot see any of those, and the cost of guessing was measured — it was the fleet's routine
# writes.
#
# One more sits in the same column, and it follows from the positional rule rather than from encoding:
# a REAL invocation placed after a write in the SAME compound command — `cat <<EOF > note.md … EOF;
# obsidian command="…/Verify current note.md#choice"` — is not refused, because the normalisation
# collapses newlines and nothing in the flattened text says where the written body ended. Closing it
# needs the wall to know where each heredoc and each redirect stops, and every rule strong enough to do
# that also refuses a note whose own text quotes a command form — which is the failure that reverted
# version one. So it is left open and written down, not guessed at. Rule 19 stands above the hook: it
# closes the shapes a session reaches for by habit, and it is not an authentication boundary.
#
# One shape the ruling put on that list turns out NOT to be on it, and the battery proved it: a name
# split across adjacent string literals inside one eval — `executeChoice("veri" + "fy current note")` —
# IS caught, because squashing the argument to letters and digits joins the pieces back together. What
# escapes is a name assembled through variables (`"ver" + x + "note"`), where the middle is not in the
# payload at all. Worth knowing, because it is a stronger position than the design was given credit for.
#
# The verbs' own `_invoked-by` compare is why a belt is wanted as well as braces.
#
# A sibling of pause-guard.sh: same stdin-JSON read, same exit-0 allow / exit-2 block convention
# (Claude Code feeds a hook's stderr back to the model on exit 2), same EXIT trap rewriting every
# unexpected exit to 2. It registers on two of that hook's three matchers, `Bash` and
# `mcp__vault-mcp__.*`, and deliberately not on `Edit|Write|NotebookEdit|MultiEdit`, because those
# tools cannot invoke a verb — which is also what leaves a session a clear way to write about one.
#
# FAILS CLOSED, parting company with its sibling on purpose: pause-guard.sh fails OPEN with a warning
# when its own dependency is missing, under 01.41 rule 7c, because a pause that cannot be read must not
# lock a session out of fixing the note. A call whose contents cannot be read must not run, so a missing
# `jq` or `perl` blocks here. No allow path, no override flag, no environment variable lifts it.
#
# NO SIZE CAP, on purpose: a cap is a bypass — put the call after the cut and the guard never sees it.
# The cost is bounded instead by searching a scratch file rather than matching a shell variable, which
# measured 5.3 s for a 10 MB payload against 17 s for the variable form. A hook killed by a harness
# timeout never reaches its EXIT trap, and anything but exit 2 reads as allow, so speed here is safety.
#
# Works under /bin/bash 3.2 (macOS). Needs jq and perl.
set -u

scratch=""
on_exit() {
  exit_rc=$?
  [ -z "$scratch" ] || rm -f "$scratch"
  [ "$exit_rc" -eq 0 ] && exit 0
  exit 2
}
trap on_exit EXIT

refuse() {
  printf 'REFUSED by accept-verb-guard: %s\n' "$1" >&2
  printf 'The accept verbs — Verify current note, Reopen current note, Request revision, Answer current note — are Nelson'\''s alone.\n' >&2
  printf '01.65 Operator'\''s console rule 19: no rank invokes an accept verb by any means, not through the palette API, a command call or an eval, not for testing and not on a test artifact.\n' >&2
  printf '01.41 The accept perimeter rule 2: the accepter'\''s identity is asked for, never passed in.\n' >&2
  printf 'A verb is tested by Nelson clicking it, or by a dry-run path that never calls the choice. There is no flag that lifts this.\n' >&2
  printf 'If you are writing ABOUT a verb rather than calling one: text inside a heredoc, a printf, or anything written to a file passes — put the words in the file you are writing, not in a live obsidian command.\n' >&2
  exit 2
}

command -v jq >/dev/null 2>&1   || refuse "jq is not available, so this call cannot be read; a guard that cannot read fails closed"
command -v perl >/dev/null 2>&1 || refuse "perl is not available, so this call cannot be read; a guard that cannot read fails closed"

input=$(cat 2>/dev/null) || refuse "the hook input could not be read"
[ -n "$input" ] || refuse "the hook input was empty"
printf '%s' "$input" | jq -e . >/dev/null 2>&1 || refuse "the hook input is not valid JSON"

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null) || refuse "the tool name could not be read"
[ -n "$tool" ] || refuse "the call carries no tool name"
tool_l=$(printf '%s' "$tool" | tr '[:upper:]' '[:lower:]')

# The payload as its DECODED scalar values, not `tostring`: re-serialising turns a real tab back into
# the two characters `\t`, and a squashed `\t` leaves a stray letter in the middle of a verb's name —
# "verify<TAB>current<TAB>note" became "verifytcurrenttnote" and slipped through review. Percent-escapes
# are decoded, case is dropped, non-breaking spaces and leftover escapes become spaces.
scratch=$(mktemp -t accept-verb-guard) || refuse "no scratch file could be made, so this call cannot be read"
printf '%s' "$input" | jq -r '(.tool_input // {}) | [.. | scalars | tostring] | join(" ")' 2>/dev/null \
  | perl -pe 's/\\[nrt]/ /g; s/\\u00a0/ /gi; s/%([0-9a-fA-F]{2})/chr(hex($1))/ge; $_ = lc $_; s/\xc2\xa0/ /g; s/\s+/ /g' > "$scratch" \
  || refuse "the tool input could not be normalised"
[ -s "$scratch" ] || printf '{}' > "$scratch"

# --- does the payload name a verb at all? ----------------------------------------------------------
# On a squashed copy, so every way of separating the words — double space, tab, CR, non-breaking space,
# underscore, hyphen, %20 — is one case. Naming a verb is not by itself a refusal; it is the question
# the shape test then answers.
verb=$(perl -ne '
  $t = $_; $t =~ s/[^a-z0-9]//g;
  for my $v (qw(verifycurrentnote reopencurrentnote requestrevision answercurrentnote)) {
    if (index($t, $v) >= 0) { print $v; exit }
  }' "$scratch")

if [ -z "$verb" ]; then
  exit 0   # no verb named anywhere: nothing here can be an accept-verb invocation
fi

# --- is a verb named INSIDE an invocation, or only in text? -----------------------------------------
# perl reports the invocation shape it found, or nothing. The positional rule: a match that appears
# after the payload's first write boundary is text being written, not a call being made.
how=$(perl -e '
  my $file = shift; open my $fh, "<", $file or exit 0; local $/; my $s = <$fh>; exit 0 unless defined $s;
  my @verbs = qw(verifycurrentnote reopencurrentnote requestrevision answercurrentnote);
  # where does written text begin? the earliest write boundary, if any
  my $wall = length($s) + 1;
  for my $b ("<<", ">>", ">", "| tee", "tee ", ".write(", "writefilesync(") {
    my $i = index($s, $b);
    $wall = $i if $i >= 0 && $i < $wall;
  }
  sub names_verb {
    my $w = shift; $w =~ s/[^a-z0-9]//g;
    for my $v (@verbs) { return 1 if index($w, $v) >= 0 }
    return 0;
  }
  # each candidate: a marker, and how far after it the argument runs
  my @shapes = (
    ["command=", 400, "the obsidian CLI with command= whose argument names a verb"],
    ["code=",    400, "the obsidian CLI with code= whose argument names a verb"],
    [" eval ",   400, "an obsidian CLI eval whose argument names a verb"],
    ["keystroke", 200, "keystroke automation typing a verb name into the palette"],
    ["key code",  200, "keystroke automation typing a verb name into the palette"],
    ["cliclick",  200, "keystroke automation typing a verb name into the palette"],
  );
  my $cli = (index($s, "obsidian") >= 0) ? 1 : 0;
  for my $sh (@shapes) {
    my ($marker, $span, $why) = @$sh;
    my $needs_cli = ($marker =~ /^(command=|code=| eval )$/) ? 1 : 0;
    next if $needs_cli && !$cli;
    my $pos = 0;
    while ((my $i = index($s, $marker, $pos)) >= 0) {
      $pos = $i + 1;
      next if $i >= $wall;                      # this one sits inside written text: prose
      my $window = substr($s, $i, $span);
      if (names_verb($window)) { print $why; exit 0 }
    }
  }
  exit 0' "$scratch")

# A vault-mcp run tool carries no shell text, so its whole payload is the argument.
if [ -z "$how" ]; then
  case "$tool_l" in
    *run_command*|*runcommand*|*execute_command*|*executecommand*)
      how="the tool $tool exists to run a command, and its payload names a verb" ;;
    *execute*)
      # a looser `execute` counts only on a tool that addresses this vault, so that an unrelated
      # `shortcuts_execute` on some other server is not judged by a vault rule if the matchers widen
      case "$tool_l" in
        *obsidian*|*vault*) how="the tool $tool exists to run something, and its payload names a verb" ;;
      esac ;;
  esac
fi

[ -z "$how" ] || refuse "this call invokes the accept verb '$verb': $how"

# A verb named in text that invokes nothing — a note being written, a harness being generated, a log
# line, a printf — passes. That is the whole point of the second version.
exit 0
