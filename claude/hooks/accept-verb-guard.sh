#!/usr/bin/env bash
# accept-verb-guard.sh — PreToolUse hook refusing any tool call that INVOKES an Obsidian command or a
# QuickAdd choice. It contains no verb name, and that is the point of this version.
#
# 01.65 Operator's console rule 19, Nelson's words: "No rank invokes an accept verb (verify, reopen,
# request revision, answer) by any means, not through the palette API, a command call or an eval, not
# for testing and not on a test artifact: the verb's first act is a prompt in the admiral's own
# window, so an agent invoking it is an agent at the perimeter."
#
# 01.41 The accept perimeter rule 2: "The accepter's identity is asked for, never passed in." Rule 3
# says where the refusal belongs: "in the code path, before it touches any file. Not by policy text an
# agent is expected to have read. By a check that runs first and returns an error."
#
# WHY THE HOOK EXISTS AT ALL, since the verbs guard themselves. Their guard is a string compare on
# `_invoked-by`, and a call that OMITS the key reads as human. On 2026-09-26 a session attempting a DRY
# RUN of the decision panel's Yes button caused the real path to fire: `executeChoice` ran and two Verify
# prompts opened on Nelson's screen. Nothing was written, because the human-only prompt refused, but a
# dry run reached a live verb. This hook is the check that runs before such a call leaves the session.
#
# WHY THIS IS THE THIRD DESIGN, and the honest history, because two versions of it were wrong in the
# same way. Version one (#53) refused a verb's NAME appearing anywhere near any of several markers, and
# refused four pieces of routine work within the hour — prose about `eval`, a spec note quoting rule 19,
# a notebook section naming the verbs, and a test harness stubbing `executeChoice`. Reverted (#54).
# Version two asked whether a name sat in the VALUE of an invoking key, which was a real improvement and
# survived three soak hours — but a review found the key list itself was wrong: `command=` is not an
# obsidian CLI form at all, so the main CLI road had never been closed while the battery pinned an
# unrunnable form as a positive. Seven of the nine review findings were one failure: hunting a name in
# free text. A deny-list over free text cannot be completed.
#
# SO THE QUESTION IS INVERTED. This version does not ask "does this text contain a verb name". It asks
# "does this call invoke an Obsidian command or a QuickAdd choice AT ALL", answered from structure, and
# refuses if it does. No name is matched, so a rename, a fifth verb or a new spelling changes nothing
# here, and the fleet's whole vocabulary — every note, log line, commit message and grep pattern that
# names a verb — is outside the question.
#
# THE ROADS, and the source of each, so the list is traceable to the grammar rather than to memory:
#   1. A RUN TOOL, by its NAME: `run_command` or `execute_command`, or a looser `execute` only when the
#      name also says obsidian or vault, so widening the matchers later cannot make this vault rule judge
#      another server's `shortcuts_execute`. Refused whatever id it carries.
#   2. THE OBSIDIAN CLI. Its usage text (`obsidian` with no arguments) gives the grammar
#      `obsidian [key=value …] <command-word> [key=value …]`, and the suite's own
#      packages/host/src/mcp/cli-policy.ts already names the command words that execute things:
#      `command`, `eval`, `quickadd`, `quickadd:run`, `quickadd:run-template`. QuickAdd's compiled plugin
#      registers a fourth, `quickadd:run-template-from-folder`, which that list does not carry — so this
#      file matches the plugin's registered names as well, and the discrepancy went to the obsidian ship
#      rather than being smoothed over on one side. Every other CLI word — `append`, `create`, `open`,
#      `rename`, `vault info=`, `aliases` — is not an invocation and is never looked at.
#   3. AN ADVANCED-URI: the `obsidian://` scheme carrying a `commandid`. This is the only road actually
#      present in this repo, which is why it is not an afterthought.
#   4. THE LOCAL REST API: a `/commands` path with a loopback host.
#
# `eval` IS NOT REFUSED FOR EXISTING, and getting this wrong would have been worse than version one.
# CLAUDE.md's own rule is "drive live vaults via the obsidian CLI (`eval`, `append`)", and the vault's
# 00.13 scripts work that way, so a guard refusing every eval would refuse the fleet's normal way of
# working rather than its documentation. What is refused inside `code=` is a call that invokes a command
# or a choice — `executeCommandById`, `executeChoice`, QuickAdd's api run forms. Those are stable API
# names, the JS surface itself, not vault content anyone may rename.
#
# MADE VERSUS WRITTEN is still a question the guard has to answer, and the claim that structure makes
# prose safe "by construction" is only half true: prose that MENTIONS a verb is now outside the question
# entirely, but prose that QUOTES A WHOLE INVOCATION — this file's own header, a PR body, the fleet's
# documentation of this machinery — puts a structurally valid call in the payload. Two things answer it:
#   * QUOTING. A road inside a quoted run is text being carried, unless the run is handed to something
#     that runs it: a shell with `-c`, a shell `eval`, `xargs`, `ssh`, `watch`, `env`, `nohup`, `nice`,
#     `time`, `timeout`, `osascript`, `open`, `open location`, `openLocation(`, `curl`, `wget`. For the
#     URI road only, `python3 -c` and `node -e` count too: code they run cannot reach Obsidian's `app`
#     object, but opening a URL needs no API at all, and exempting interpreters from every road was how
#     the previous version let `webbrowser.open` through.
#   * LINES, and ONE ORDERING that is the whole difference. The comment strip runs BEFORE the heredoc
#     scan: the other way round, a `#` comment containing `<<` opens a heredoc whose delimiter never
#     arrives, and every line after it — including a real call — is read as body. My first attempt had
#     that order wrong and allowed exactly that. The payload is NOT flattened any more. Version two collapsed newlines to defeat separator
#     dodges inside a verb name; with no name to defend, the lines stay — and keeping them lets a heredoc
#     BODY end at its delimiter line and a `#` comment end at its newline. That closes both shapes the
#     previous version had to accept as boundaries: a real call placed after a heredoc write in the same
#     compound command (dotfiles #59) and a comment containing `<<` setting a false wall.
#
# NO ALLOW-LIST, AND NO ID LIST IN THE CODE, because the question was measured rather than guessed. A
# read-only survey found thirteen real call sites and not one is a session's tool call: a scheduled tickle
# job (tickle/scripts/vault-skills-export/export.sh:21), seven Alfred workflow scripts and an AppleScript
# action fired by Nelson at a hotkey, the decision panel's `executeChoice` driven by a meta-bind button he
# clicks, and a self-test command inside Obsidian. Every one is a schedule, a hotkey or Nelson clicking,
# and none passes through any PreToolUse hook, which sees only a session's tool calls. So no session has a
# standing need to invoke anything, and the guard refuses every road.
#
# THREE SURFACES EXIST FOR AGENT INVOCATION AND ARE UNCALLED TODAY. They are named here because they are
# the candidates for the day someone wires one, and because adding any id IS A RULING AND NOT A PATCH:
#   * `00.14 QuickAdd choices/Dispatch agent on current note.md` — a draft choice built to be agent-driven.
#   * `00.13 Scripts/pause-the-fleet.md` and `resume-the-fleet.md` — documented as callable through
#     `executeChoice` with the same dual-mode convention.
#   * `mcp__vault-mcp__obsidian_run_command` — shipped (PR #225) so an agent can route a QuickAdd id
#     through `quickAddApi.executeChoice` headlessly.
#
# FAILS CLOSED, and this is the property that must never be lost. A previous build ALLOWED a real
# invocation when `tool_input` was a string rather than an object: `del(.description)` made jq exit 5,
# `2>/dev/null` hid the message, no `pipefail` hid the status, and an empty-scratch default turned "I read
# nothing" into "there was nothing to read". So: `set -o pipefail`, an explicit type guard on
# `tool_input`, a missing `jq` or `perl` refusing, malformed JSON refusing, an absent tool name refusing,
# and no allow path, override flag or environment variable that lifts any of it.
#
# THE SIZE CAP REFUSES, WHICH IS WHY THERE IS ONE. A previous header rejected a cap in strong terms — "a
# cap is a bypass: put the call after the cut and the guard never sees it" — and that is true only of a
# cap that ALLOWS. A cap that REFUSES is fail-closed, so the objection dissolves. It exists because
# declaring `"timeout": 10` made the harness kill DETERMINISTIC, and a killed hook never reaches its EXIT
# trap and reads as allow: measured, a marker-dense payload crosses 10 s at about 12 MB, so bulk alone was
# a bypass. The order is: the structural fast path first at any size; over the cap with no candidate road,
# pass; over the cap WITH one, refuse unread and say the call must be split.
#
# THE CAP IS DERIVED, NOT CHOSEN, so a later reader can redo the arithmetic when either number changes:
# worst measured rate for the guarded path 0.9 s/MB, plus the fast path's own measured 0.07 s/MB; half the
# declared 10 s timeout is 5 s; 5 / 0.97 = 5.15, rounded down to 5 MB (5 MB costs about 4.9 s). The
# residual, named rather than implied: every rate was measured on an idle machine, so under load an
# under-cap payload can still be killed, and a killed hook reads as allow. The cap narrows that; it does
# not close it, and raising the timeout only moves the size.
#
# WHAT REMAINS A NAMED BOUNDARY: a road assembled at runtime, from a variable, from base64, or arriving
# through a pipe (`echo '<uri>' | xargs open -g`) — the guard reads text, and data flow is not text; and
# `js-engine:*` ids, which run arbitrary vault JS, the same reason cli-policy.ts denies them by default.
#
# A sibling of pause-guard.sh: same stdin-JSON read, same exit-0 allow / exit-2 block convention (Claude
# Code feeds a hook's stderr back to the model on exit 2), same EXIT trap rewriting every unexpected exit
# to 2. Registered on `Bash` and `mcp__vault-mcp__.*` only, never on Edit/Write/NotebookEdit, because
# those tools cannot invoke anything — which is also what leaves a session a clear way to write about one.
#
# Works under /bin/bash 3.2 (macOS). Needs jq and perl.
set -u
set -o pipefail

CAP_BYTES=5242880   # 5 MB — see THE CAP IS DERIVED above

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
  printf 'No rank invokes an Obsidian command or a QuickAdd choice from a tool call. 01.65 Operator'\''s console rule 19: the accept verbs are Nelson'\''s alone, and a verb'\''s first act is a prompt in his own window.\n' >&2
  printf 'This guard names no verb: it refuses the ROAD, so an ordinary command is refused too. Nothing is on an allow-list, and adding one is a ruling, not a patch.\n' >&2
  printf 'What to do instead: ask Nelson to run it, or use a road that is not an invocation — the obsidian CLI'\''s `append`, `create`, `rename`, `open` and `vault info=` verbs, an `eval` that reads rather than invokes, or the vault-mcp read and write tools.\n' >&2
  printf 'If you are WRITING about a call rather than making one, that passes: put it inside a heredoc body, a quoted string, or a `#` comment, or write it with Edit/Write, which this hook does not watch.\n' >&2
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

# The type guard. Anything but an object (or an absent/null field) cannot be read, and a call that cannot
# be read must not run — this is the case that used to be allowed.
t_type=$(printf '%s' "$input" | jq -r 'if has("tool_input") then (.tool_input | type) else "absent" end' 2>/dev/null) \
  || refuse "the tool input could not be examined"
case "$t_type" in
  object|absent|null) ;;
  *) refuse "the tool input is a $t_type rather than an object, so this call cannot be read" ;;
esac

# ROAD 1 — the tool itself exists to run commands. No id matters: there is no allow-list.
case "$tool_l" in
  *run_command*|*runcommand*|*execute_command*|*executecommand*)
    refuse "the tool $tool exists to run an Obsidian command, and no session invokes one" ;;
  *execute*)
    case "$tool_l" in
      *obsidian*|*vault*) refuse "the tool $tool exists to run something in the vault, and no session invokes a command or a choice" ;;
    esac ;;
esac

# The payload as its decoded scalar values, joined by NEWLINES so the line structure survives — that is
# what lets a heredoc body and a comment be bounded. `description` is dropped for the Bash tool only: it
# is the harness's own note about the call, nothing executes it, and dropping it everywhere would delete
# content on tools where that field is content.
scratch=$(mktemp -t accept-verb-guard) || refuse "no scratch file could be made, so this call cannot be read"
if [ "$tool_l" = "bash" ]; then
  printf '%s' "$input" | jq -r '(.tool_input // {}) | del(.description) | [.. | scalars | tostring] | join("\n")' > "$scratch" \
    || refuse "the tool input could not be normalised"
else
  printf '%s' "$input" | jq -r '(.tool_input // {}) | [.. | scalars | tostring] | join("\n")' > "$scratch" \
    || refuse "the tool input could not be normalised"
fi

found=$(perl -e '
# The inversion matcher. Answers ONE question from structure: does this payload INVOKE an Obsidian
# command or a QuickAdd choice? Prints the road it found, or nothing. No verb name appears anywhere.
#
# Contains no single quote character, so it can be embedded in a single-quoted `perl -e` program; a
# literal quote is chr(39).
use strict;
my $SQ = chr(39);
my $DQ = chr(34);

my $file = shift; my $cap = shift; $cap = 0 unless defined $cap;
open my $fh, "<", $file or exit 3; local $/; my $s = <$fh>;
exit 0 unless defined $s && length $s;
$s = lc $s;

# THE FAST PATH. Is there anything in this payload shaped like one of the four roads? Keyed on the
# GRAMMAR — the binary, any key=value prefixes, then a command word — and never on the word "obsidian",
# because this fleet writes `~/obsidian/…` in nearly every payload and a filter keyed on the word would
# filter nothing. Measured at 0.07 s/MB against 0.9 s/MB for the full read. It fails TOWARD the slow path:
# a candidate found inside a heredoc body still costs a full read, which then finds no road and allows.
my $CANDIDATE = qr{
    (?:^|[\s;&|(\x22\x27])obsidian\s+(?:[a-z_-]+=\S*\s+)*   # a quote may open the run that runs it
      (?:command|eval|quickadd(?::run(?:-template(?:-from-folder)?)?)?)\b
  | obsidian://
  | /commands
}x;
exit 0 unless $s =~ $CANDIDATE;

# THE CAP, which REFUSES rather than allows. A payload this size cannot be read inside the timeout, and a
# hook the harness kills reads as allow — so an unreadable-in-time payload that carries a road shape is
# refused unread. A payload over the cap with NO candidate road has already exited above.
if ($cap > 0 && length($s) > $cap) { print "TOOLARGE"; exit 0 }

# ---------------------------------------------------------------------------------------------------
# The quoted runs of one piece of text, and whether each is handed to something that RUNS it.
# ---------------------------------------------------------------------------------------------------
sub regions {
  my $t = shift;
  my $n = length $t;
  my @reg;
  my $i = 0;
  my $nsq = index($t, $SQ, 0);
  my $ndq = index($t, $DQ, 0);
  while ($i < $n) {
    $nsq = index($t, $SQ, $i) if $nsq >= 0 && $nsq < $i;
    $ndq = index($t, $DQ, $i) if $ndq >= 0 && $ndq < $i;
    my $k = ($nsq < 0) ? $ndq : (($ndq < 0) ? $nsq : ($nsq < $ndq ? $nsq : $ndq));
    last if $k < 0;
    if ($k > 0 && substr($t, $k - 1, 1) eq "\\") { $i = $k + 1; next }
    my $q = substr($t, $k, 1);
    my $close;
    if ($q eq $SQ) { $close = index($t, $SQ, $k + 1); $close = $n if $close < 0 }
    else {
      my $j = $k + 1;
      while ($j < $n) { my $d = substr($t, $j, 1); last if $d eq $DQ; $j += ($d eq "\\") ? 2 : 1 }
      $close = ($j > $n) ? $n : $j;
    }
    push @reg, [$k, $close];
    $i = $close + 1;
  }
  return @reg;
}

# A quoted run is a value being USED, not text being carried, when something runs it. `python3 -c` and
# `node -e` are on this list ONLY for the uri road and are marked so: code they run cannot reach
# the Obsidian app object, but opening a URL needs no API at all, which is the distinction the previous
# version got wrong by exempting interpreters from every road.
sub runner_kind {
  my ($t, $open) = @_;
  my $back = $open > 80 ? 80 : $open;
  my $ctx = substr($t, $open - $back, $back);
  return "any" if $ctx =~ /(?:^|[\s;&|(])(?:ba|z|da|k)?sh\s+-[a-z]{0,3}c\s*$/;
  return "any" if $ctx =~ /(?:^|[\s;&|(])eval\s+$/;
  return "any" if $ctx =~ /(?:^|[\s;&|(])xargs\b[^|;&]*$/;
  return "any" if $ctx =~ /(?:^|[\s;&|(])(?:ssh|watch|env|nohup|nice|time|timeout)\b[^|;&]*$/;
  return "any" if $ctx =~ /osascript\b[^|;&]*$/;
  return "any" if $ctx =~ /(?:^|[\s;&|(])(?:curl|wget)\b[^|;&]*$/;
  return "any" if $ctx =~ /(?:^|[\s;&|(])open\b[^|;&]*$/;
  return "any" if $ctx =~ /open\s*location\s*$/ || $ctx =~ /openlocation\s*\(\s*$/;
  return "uri" if $ctx =~ /(?:^|[\s;&|(])(?:python3?|node|ruby|perl)\s+-[a-z]*[ce]\s*$/;
  return "";
}

# ---------------------------------------------------------------------------------------------------
# Strip what a shell would never execute: heredoc BODIES and `#` comments. This is why the payload is
# no longer flattened to one line. The previous version collapsed newlines to defeat separator dodges
# inside a verb name; with no name to defend, the lines can stay, and keeping them is what lets a
# heredoc body end at its delimiter and a comment end at its newline. That closes two things the
# previous version had to accept as boundaries: a real call placed after a heredoc write in the same
# command, and a `#` comment containing `<<` setting a false wall.
# ---------------------------------------------------------------------------------------------------
sub code_only {
  my $t = shift;
  my @lines = split /\n/, $t, -1;
  my @out;
  my $i = 0;
  while ($i <= $#lines) {
    my $line = $lines[$i];
    my @reg = regions($line);
    my $live = sub {
      my $p = shift;
      for my $r (@reg) { next if $p > $r->[1]; return 0 if $p >= $r->[0]; return 1 }
      return 1;
    };
    # a `#` comment runs to the end of the line, if the `#` is live and starts a word. This is done
    # BEFORE the heredoc scan on purpose: a comment containing `<<` would otherwise open a heredoc whose
    # delimiter never arrives, and everything after it — including a real call — would be read as body.
    my $cut = -1;
    {
      my $p = 0;
      while ((my $h = index($line, "#", $p)) >= 0) {
        $p = $h + 1;
        next unless $live->($h);
        next if $h > 0 && substr($line, $h - 1, 1) !~ /[\s;&|(]/;
        $cut = $h; last;
      }
    }
    my $code = ($cut >= 0) ? substr($line, 0, $cut) : $line;

    # heredoc openers in the CODE part, in order, outside quotes. `<<<` is a herestring, not a heredoc.
    my @delims;
    my $pos = 0;
    while ($code =~ /<<(-?)\s*($DQ([^$DQ]*)$DQ|$SQ([^$SQ]*)$SQ|[a-z_][a-z0-9_]*)/g) {
      my $at = pos($code) - length($&);
      next unless $live->($at);
      next if substr($code, $at + 2, 1) eq "<";          # a herestring
      my $dash = $1;
      my $word = defined $3 ? $3 : (defined $4 ? $4 : $2);
      $word =~ s/^[$DQ$SQ]|[$DQ$SQ]$//g;
      push @delims, { word => $word, dash => ($dash eq "-" ? 1 : 0) };
    }
    push @out, $code;
    $i++;
    # skip each heredoc body, to its own terminator line
    for my $d (@delims) {
      while ($i <= $#lines) {
        my $cand = $lines[$i];
        $i++;
        my $test = $cand;
        $test =~ s/^\s+// if $d->{dash};
        $test =~ s/\s+$//;
        last if $test eq $d->{word};
      }
    }
  }
  return join("\n", @out);
}

# ---------------------------------------------------------------------------------------------------
# The roads. Each returns a sentence naming what it found, or nothing.
# ---------------------------------------------------------------------------------------------------
my $code = code_only($s);
my @reg = regions($code);
sub live_in_code {   # 0 = prose, or the runner kind that makes it live
  my $p = shift;
  for my $r (@reg) {
    next if $p > $r->[1];
    return "plain" if $p < $r->[0];
    return runner_kind($code, $r->[0]);
  }
  return "plain";
}

my @OPAQUE = ("command", "eval", "quickadd:run-template-from-folder", "quickadd:run-template", "quickadd:run", "quickadd");

# ROAD 1 — the obsidian CLI. The grammar is `obsidian [key=value ...] <command-word> [key=value ...]`,
# so the command word is the first bare token. Only the opaque set is a road; `append`, `create`, `open`,
# `vault info=` and every other CLI verb are not invocations and are never looked at.
my $pos = 0;
while ((my $k = index($code, "obsidian", $pos)) >= 0) {
  $pos = $k + 1;
  next if $k > 0 && substr($code, $k - 1, 1) !~ /[\s;&|($SQ$DQ]/;   # a quote may open the run that runs it
  my $l = live_in_code($k);
  next if $l eq "" || $l eq "uri";
  my $rest = substr($code, $k + 8);
  next unless $rest =~ /^(\s+(?:[a-z_-]+=\S*\s+)*)([a-z0-9:_-]+)/;
  my $word = $2;
  my $matched = "";
  for my $o (@OPAQUE) { if ($word eq $o) { $matched = $o; last } }
  next unless $matched;
  if ($matched eq "eval") {
    # eval is a SANCTIONED road (CLAUDE.md: drive live vaults via the obsidian CLI, eval and append), so
    # it is not refused for existing. What is refused is code that invokes a command or a choice.
    my $tail = substr($rest, 0, 4000);
    next unless $tail =~ /executecommandbyid|executechoice|quickaddapi\s*\.\s*(?:execute|run)|\.\s*run(?:quickadd|template)/;
    print "an obsidian CLI eval whose code invokes a command or a choice";
    exit 0;
  }
  print "the obsidian CLI road `$matched`, which runs an Obsidian command or a QuickAdd choice";
  exit 0;
}

# ROAD 2 — an advanced-uri carrying a commandid. Interpreters count as runners here, and only here.
$pos = 0;
while ((my $k = index($code, "obsidian://", $pos)) >= 0) {
  $pos = $k + 1;
  my $l = live_in_code($k);
  next if $l eq "";
  my $uri = substr($code, $k, 2000);
  $uri =~ s/[\s$SQ$DQ].*$//s;
  next unless $uri =~ /commandid(?:=|%3d)/;
  print "an obsidian:// uri carrying a commandid, which runs an Obsidian command";
  exit 0;
}

# ROAD 3 — the Local REST API. Only on this machine: a /commands path plus a loopback host.
if ($code =~ m{(?:localhost|127\.0\.0\.1|\[::1\]|:27123|:27124)}) {
  $pos = 0;
  while ((my $k = index($code, "/commands", $pos)) >= 0) {
    $pos = $k + 1;
    my $l = live_in_code($k);
    next if $l eq "" || $l eq "uri";
    print "a Local REST API /commands call, which runs an Obsidian command";
    exit 0;
  }
}

exit 0;
' "$scratch" "$CAP_BYTES") || refuse "the tool input could not be examined"

case "$found" in
  "") exit 0 ;;
  TOOLARGE) refuse "this call is larger than $CAP_BYTES bytes and carries something shaped like an Obsidian command road, so it cannot be checked inside the time the hook is given; split it into smaller calls" ;;
  *) refuse "this call invokes an Obsidian command or a QuickAdd choice: $found" ;;
esac
