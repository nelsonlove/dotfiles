#!/usr/bin/env bash
# accept-verb-guard.sh — PreToolUse hook refusing a tool call that INVOKES an Obsidian command or a
# QuickAdd choice, where that can be told from structure. It contains no verb name, and it does not
# pretend to close every road.
#
# 01.65 Operator's console rule 19, Nelson's words: "No rank invokes an accept verb (verify, reopen,
# request revision, answer) by any means, not through the palette API, a command call or an eval, not
# for testing and not on a test artifact: the verb's first act is a prompt in the admiral's own
# window, so an agent invoking it is an agent at the perimeter." 01.41 The accept perimeter rule 3 says
# where the refusal belongs: "in the code path, before it touches any file … by a check that runs first".
#
# WHY IT EXISTS, since the verbs guard themselves: their guard is a string compare on `_invoked-by`, and a
# call that OMITS the key reads as human. On 2026-09-26 a session attempting a DRY RUN of the decision
# panel's Yes button caused the real path to fire — `executeChoice` ran and two Verify prompts opened on
# Nelson's screen. Nothing was written, because the human-only prompt refused. A dry run reached a live verb.
#
# THE HONEST CLAIM, first rather than last, because three designs were needed to learn it: A SHELL REACHES
# OBSIDIAN BY TOO MANY ROADS TO ENUMERATE. Any binary by any path, any interpreter shelling out, a
# multiplexer typing into a pane, a remote shell, a name assembled at runtime, a payload from base64 — all
# reach the same place, and every attempt to enumerate them bought a false-refusal class instead. The one
# that proved it: `timeout 30 grep -rn "obsidian quickadd:run" ~/obsidian` was refused by the version that
# tried, and that is how a session searches for this very machinery. So this guard closes what is
# ENUMERABLE and names what is not. What protects the accept verbs is that they are the admiral's to click
# and that every act is in the log; this hook stops the shapes a session reaches for by habit, and it is
# not an authentication boundary.
#
# WHAT IT REFUSES — two enumerable surfaces, and nothing else.
#
# 1. THE MCP MATCHERS, enumerable because tool names are a finite list the host publishes.
#    * A RUN TOOL, by name: `run_command`, `execute_command`, or a looser `execute` only when the name also
#      says obsidian or vault, so widening the matchers cannot make this vault rule judge another server's
#      `shortcuts_execute`. Refused whatever id it carries — there is no allow-list.
#    * `obsidian_cli` (packages/host/src/mcp/tools-cli.ts, "Run an official Obsidian CLI command"), matched
#      by EXACT tool name, whose payload IS a command line: its `command` word is read against the opaque
#      set, and within the eval case only `params.code`. No other field is read — `params.content` above
#      all, or the note-body failure below would be rebuilt inside the exception.
#    * `mcp__claude-in-chrome__navigate`, by exact name, whose payload is a URL to open: refused when that
#      URL is an `obsidian://` carrying a `commandid`. A browser tool that opens a URL invokes a command as
#      surely as a shell does.
#    Every other MCP tool's payload is DATA handed to that tool, never a command line. `obsidian_write_note`
#    whose BODY documents `obsidian command id=…` is a note being written; reading it as shell text refused
#    exactly the work this fleet does, documenting this machinery in the vault, which is how the rule was
#    found. The claim a previous header made — that the unregistered tools "cannot invoke anything" — was
#    FALSE, and is corrected: Edit and Write cannot invoke; an MCP tool that opens a URL or runs a command
#    joins the list above BY RULING.
#
# 2. THE BASH MATCHER — ONE shape, and no lists of any kind. An obsidian-family binary in COMMAND POSITION
#    carrying an opaque command word in argument position:
#    * COMMAND POSITION is the start of a stage — the start of the payload, or after an unquoted `;` `&&`
#      `||` `|` `&` newline `(` or backtick — with leading `VAR=value` assignments skipped. Quoted text
#      inside a stage is an ARGUMENT and never a command, which is what lets `grep -rn "obsidian quickadd"`
#      pass with no exemption for grep: that `obsidian` is a pattern. The positive test replaced a list of
#      "runners", and the list is gone.
#    * THE BINARY is decided by BASENAME beginning `obsidian`, so `/usr/local/bin/obsidian`, `./obsidian`,
#      `/Applications/Obsidian.app/Contents/MacOS/obsidian-cli` and the real binary name `obsidian-cli` all
#      match. The previous version keyed on the literal token `obsidian` and missed every one of them.
#    * THE COMMAND WORD is the first bare argument, skipping `key=value` pairs, flags and a bare `--`. The
#      opaque set is `command`, `eval`, `quickadd`, `quickadd:run`, `quickadd:run-template`,
#      `quickadd:run-template-from-folder` — the first five from the suite's own
#      packages/host/src/mcp/cli-policy.ts, the sixth registered by QuickAdd's compiled plugin and absent
#      from that list, a discrepancy reported to the obsidian ship rather than smoothed over here. Every
#      other CLI word — `append`, `create`, `rename`, `open`, `vault info=`, `aliases` — is not an
#      invocation and is never looked at.
#    * `eval` IS NOT REFUSED FOR EXISTING. CLAUDE.md's own rule is "drive live vaults via the obsidian CLI
#      (`eval`, `append`)" and the vault's 00.13 scripts work that way, so refusing every eval would refuse
#      the fleet's normal way of working. What is refused is a CALL — an api name followed by an open
#      parenthesis. Testing the bare name refused code that merely MENTIONED it in a string or a comment,
#      which was version one's failure surviving in the one place free text is still read.
#
# PARSING IS NOT ENUMERATION, and four small things are the guard reading the payload the way the shell
# reads it rather than naming anything: a backslash-newline continuation is joined; a backtick is in the
# stage-separator class beside `(`; a bare `--` is skipped in the argument scan; and a heredoc delimiter may
# be `[A-Za-z0-9_.-]+`, quoted, or backslash-escaped (`<<\EOF`). A rule that named a binary or a runner
# would be enumeration, and stays out.
#
# WHAT A SHELL WOULD NEVER EXECUTE is removed before the road is looked for: heredoc BODIES, each ending at
# its own delimiter line, and `#` comments, each ending at its newline. ONE ORDERING is the whole
# difference: the comment is cut BEFORE the heredoc scan, because a comment containing `<<` would otherwise
# open a heredoc whose delimiter never arrives and swallow every line after it, including a real call. A
# terminator is NOT trimmed at the end, because a shell does not strip trailing whitespace from one — being
# stricter than the shell there refused a body that was written correctly.
#
# NO ALLOW-LIST AND NO ID LIST, because the question was measured rather than guessed. A read-only survey
# found thirteen real call sites and not one is a session's tool call: a scheduled tickle job
# (tickle/scripts/vault-skills-export/export.sh:21), seven Alfred workflow scripts and an AppleScript
# action fired at a hotkey, the decision panel's `executeChoice` driven by a meta-bind button Nelson
# clicks, and a self-test command inside Obsidian. Every one is a schedule, a hotkey or Nelson clicking,
# and none passes through any PreToolUse hook, which sees only a session's tool calls. Three surfaces exist
# FOR agent invocation and are uncalled today — `00.14 QuickAdd choices/Dispatch agent on current note.md`,
# the documented `executeChoice` form of `00.13 Scripts/pause-the-fleet.md` and `resume-the-fleet.md`, and
# `mcp__vault-mcp__obsidian_run_command` — and they are the candidates for the day one is wired. ADDING ANY
# ID IS A RULING AND NOT A PATCH.
#
# WHAT WAS CHECKED IN THE SUITE'S SOURCE, and what was not. All 18 packages/host/src/mcp/tools-*.ts files
# plus external-tools.ts were pattern-checked for `executeCommandById`, `executeChoice`, `quickAddApi` and
# Templater, and every matching site in the five files that matched was read. Only `obsidian_run_command`
# (tools-complementary.ts:292) invokes an ARBITRARY payload-supplied id. `obsidian_periodic_note`
# (tools-nav.ts:359) builds its id from an enum and tools-nav.ts:385 uses a literal, so NEITHER JOINS THE
# LIST — said here so a later reader does not widen it by reflex. The Templater tool
# (tools-integrations.ts:182) takes a template PATH rather than an id and its handler scans that template
# pre-exec, failing closed on an acceptance fence, a `<% %>` tag, a `{{ }}` field or an unreadable
# template: checked and excluded. The limit: the files were pattern-checked and the matches read, not every
# handler end to end. `obsidian_cli` is not exposed to this fleet's sessions, so its cases are synthetic
# stdin payloads and this guard has never seen a live call of it.
#
# FAILS CLOSED, the one property that must never be lost, and which a previous build had lost: `tool_input`
# as a STRING allowed a real invocation, because `del(.description)` made jq exit 5, `2>/dev/null` hid the
# message, no `pipefail` hid the status, and an empty-scratch default turned "I read nothing" into "there
# was nothing to read". So: `set -o pipefail`, an explicit type guard on `tool_input`, and refusals for
# malformed JSON, an absent tool name, and a missing jq or perl. No allow path, no override flag, no
# environment variable lifts any of it.
#
# THE SIZE CAP REFUSES, WHICH IS WHY THERE IS ONE. "A cap is a bypass — put the call after the cut and the
# guard never sees it" is true only of a cap that ALLOWS. Declaring `"timeout": 10` made the harness kill
# deterministic, and a killed hook never reaches its EXIT trap and reads as allow, so bulk alone was a
# bypass. The order is the fast path first at any size, then: over the cap with no candidate road, pass;
# over the cap WITH one, refuse unread and say the call must be split.
#
# THE CAP IS DERIVED, NOT CHOSEN, and the arithmetic is here so it can be redone when either number
# changes: worst measured rate for the guarded path 1.2 s/MB (linear, after the second quadratic was
# hoisted), plus the fast path's own 0.07 s/MB; half the declared 10 s timeout is 5 s; 5 / 1.27 = 3.9;
# round down to 4 MB, which costs about 4.8 s. TWICE this file has been quadratic — the region builder, and
# then a per-hit rescan of the region list — and the second time it was a FAIL-OPEN: 396 KB took 9.74 s
# against a 10 s timeout, and 1 MB took 72 s. Both are now single passes with binary search, 1 MB answering
# in 1.19 s. The battery has a case shaped like that failure specifically.
#
# WHAT THIS GUARD DOES NOT STOP, named rather than implied, and all of it following from the honest claim
# above: a shell by path or with an option before `-c`; an interpreter shelling out to the CLI or posting
# to the Local REST API; `tmux send-keys` typing into a pane; a remote shell; a binary name assembled at
# runtime or held in a variable; `$(which obsidian)`; an `obsidian://` URI opened from a shell — because
# the only thing that ever distinguished `open "<uri>"` from a session writing that URI into a note was a
# list of runners that cannot be completed, and it stays closed where it IS enumerable, on
# `mcp__claude-in-chrome__navigate` — and there, a navigate to an ORDINARY url that REDIRECTS to an
# `obsidian://…commandid=` uri passes, because the guard sees the url it is GIVEN and not where that url
# lands, which is equally true of a shortener; the Local REST API called from a shell, for the same reason; a payload
# decoded from base64; and a road arriving through a pipe. Also `js-engine:*` ids, which run arbitrary
# vault JS — the reason cli-policy.ts denies them by default. And every rate here was measured on an idle
# machine, so under load an under-cap payload can still be killed, and a killed hook reads as allow.
#
# A sibling of pause-guard.sh: same stdin-JSON read, same exit-0 allow / exit-2 block convention (Claude
# Code feeds a hook's stderr back to the model on exit 2), same EXIT trap rewriting every unexpected exit
# to 2. Registered on `Bash`, `mcp__vault-mcp__.*` and `mcp__claude-in-chrome__navigate`.
#
# Works under /bin/bash 3.2 (macOS). Needs jq and perl.
set -u
set -o pipefail

CAP_BYTES=4194304   # 4 MB — see THE CAP IS DERIVED above

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
  printf 'What to do instead: ask Nelson to run it, or use a road that is not an invocation — the obsidian CLI'\''s `append`, `create`, `rename`, `open` and `vault info=` verbs, an `eval` that reads rather than calls, or the vault-mcp read and write tools.\n' >&2
  printf 'If you are WRITING about a call rather than making one, that passes: quote it as an argument, put it in a heredoc body or a `#` comment, or write it with Edit/Write, which this hook does not watch.\n' >&2
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

t_type=$(printf '%s' "$input" | jq -r 'if has("tool_input") then (.tool_input | type) else "absent" end' 2>/dev/null) \
  || refuse "the tool input could not be examined"
case "$t_type" in
  object|absent|null) ;;
  *) refuse "the tool input is a $t_type rather than an object, so this call cannot be read" ;;
esac

# --- surface 1: the MCP matchers, by tool name ------------------------------------------------------
case "$tool_l" in
  *run_command*|*runcommand*|*execute_command*|*executecommand*)
    refuse "the tool $tool exists to run an Obsidian command, and no session invokes one" ;;
  *execute*)
    case "$tool_l" in
      *obsidian*|*vault*) refuse "the tool $tool exists to run something in the vault, and no session invokes a command or a choice" ;;
    esac ;;
esac

if [ "$tool_l" != "bash" ]; then
  tool_leaf=${tool_l##*__}
  case "$tool_leaf" in
    obsidian_cli)
      cli_cmd=$(printf '%s' "$input" | jq -r '(.tool_input // {}) | (.command // "") | tostring' 2>/dev/null) \
        || refuse "the tool input could not be examined"
      cli_cmd=$(printf '%s' "$cli_cmd" | tr '[:upper:]' '[:lower:]')
      case "$cli_cmd" in
        command|quickadd|quickadd:run|quickadd:run-template|quickadd:run-template-from-folder)
          refuse "the tool $tool is given the obsidian CLI command word \`$cli_cmd\`, which runs an Obsidian command or a QuickAdd choice" ;;
        eval)
          cli_code=$(printf '%s' "$input" | jq -r '(.tool_input // {}) | (.params // {}) | (.code // "") | tostring' 2>/dev/null) \
            || refuse "the tool input could not be examined"
          cli_code=$(printf '%s' "$cli_code" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
          case "$cli_code" in
            *executecommandbyid\(*|*executechoice\(*) refuse "the tool $tool is given an obsidian CLI eval whose code CALLS a command or a choice" ;;
          esac ;;
      esac ;;
    navigate)
      # this tool's payload is a URL to open, so every string in it is a target and none is prose
      nav=$(printf '%s' "$input" | jq -r '(.tool_input // {}) | [.. | strings] | join(" ")' 2>/dev/null) \
        || refuse "the tool input could not be examined"
      nav=$(printf '%s' "$nav" | tr '[:upper:]' '[:lower:]')
      # SCHEME POSITION, the same principle as command position on the Bash road: the URL must BE an
      # obsidian:// uri, not merely contain one. Asking whether the string contained it refused two things
      # that invoke nothing — browsing Obsidian own URI documentation with the anchor
      # `https://help.obsidian.md/uri#obsidian://advanced-uri?commandid=x`, and an https page carrying the
      # uri as a `?to=` parameter. Both load an https page. Each string in the payload is tested on its
      # own, so a second field holding the uri is still caught.
      for one in $nav; do
        case "$one" in
          obsidian://*commandid*) refuse "the tool $tool is being asked to open an obsidian:// uri carrying a commandid, which runs an Obsidian command" ;;
        esac
      done ;;
  esac
  exit 0
fi

# --- surface 2: the Bash matcher, one shape --------------------------------------------------------
scratch=$(mktemp -t accept-verb-guard) || refuse "no scratch file could be made, so this call cannot be read"
printf '%s' "$input" | jq -r '(.tool_input // {}) | del(.description) | [.. | scalars | tostring] | join("\n")' > "$scratch" \
  || refuse "the tool input could not be normalised"

found=$(perl -e '
# The narrowed matcher. ONE road on the Bash matcher: an obsidian-family binary in COMMAND POSITION
# carrying an opaque command word in argument position. No runner list, no interpreter carve-out, no
# enumeration of wrappers — the bash road cannot be enumerated, and every enumeration tried bought a
# false-refusal class instead. Prints the road it found, or nothing. No verb name appears anywhere.
#
# Contains no single quote character, so it embeds in a single-quoted perl -e program; a literal quote is
# chr(39).
use strict;
my $SQ = chr(39);
my $DQ = chr(34);

my $file = shift; my $cap = shift; $cap = 0 unless defined $cap;
open my $fh, "<", $file or exit 3; local $/; my $s = <$fh>;
exit 0 unless defined $s && length $s;
$s = lc $s;

# THE FAST PATH: is there anything here shaped like the road at all? Keyed on the grammar — a token whose
# basename begins with `obsidian` followed by an opaque command word — never on the word "obsidian",
# because this fleet writes `~/obsidian/...` in nearly every payload. It fails TOWARD the slow path.
my $OPAQUE_RE = qr{command|eval|quickadd(?::run(?:-template(?:-from-folder)?)?)?};
exit 0 unless $s =~ m{obsidian[a-z0-9_.-]*\s+(?:[^\s;&|]*\s+)*?(?:$OPAQUE_RE)\b};

# THE CAP, which REFUSES rather than allows: a payload this size cannot be read inside the declared
# timeout, and a hook the harness kills reads as allow. Derived, not chosen — see the header.
if ($cap > 0 && length($s) > $cap) { print "TOOLARGE"; exit 0 }

# --- the quoted runs of one line, so a `#` and a heredoc opener can be told from text ----------------
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

# --- what a shell would never execute: heredoc bodies and comments ----------------------------------
# A backslash-newline continuation is joined first, so the payload is what the shell sees rather than what
# the text looks like. Then, per line: the comment is cut BEFORE the heredoc scan, because a comment
# containing `<<` would otherwise open a heredoc whose delimiter never arrives and swallow every line
# after it, including a real call.
sub code_only {
  my $t = shift;
  $t =~ s/\\\n//g;
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

    # heredoc openers, in order, outside quotes. `<<<` is a herestring. The delimiter may be bare, quoted,
    # or BACKSLASH-ESCAPED (`<<\EOF`, the classic quote-the-delimiter idiom, which the previous version did
    # not know and so scanned the body as code), and a bare delimiter may carry digits, dots and hyphens
    # (`<<EOF-1`, which the previous version read as `eof` so the terminator never matched and the rest of
    # the payload was swallowed as body).
    my @delims;
    while ($code =~ /<<(-?)\s*(?:\\([a-z0-9_.-]+)|$DQ([^$DQ]*)$DQ|$SQ([^$SQ]*)$SQ|([a-z0-9_.-]+))/g) {
      my $at = pos($code) - length($&);
      next unless $live->($at);
      next if substr($code, $at + 2, 1) eq "<";
      my $dash = $1;
      my $word = defined $2 ? $2 : defined $3 ? $3 : defined $4 ? $4 : $5;
      push @delims, { word => $word, dash => ($dash eq "-" ? 1 : 0) };
    }
    push @out, $code;
    $i++;
    for my $d (@delims) {
      while ($i <= $#lines) {
        my $cand = $lines[$i];
        $i++;
        my $test = $cand;
        $test =~ s/^\s+// if $d->{dash};
        # NOT trimmed at the end: a shell does not strip trailing whitespace from a terminator, so `EOF `
        # is body and not the end of it. Trimming made the hook stricter than the shell, which refused a
        # body that was written correctly.
        last if $test eq $d->{word};
      }
    }
  }
  return join("\n", @out);
}

# --- the road ---------------------------------------------------------------------------------------
# Command position: the start of a stage. A stage begins at the start of the payload or after an unquoted
# `;` `&&` `||` `|` `&` newline `(` or backtick, and may carry leading VAR=value assignments. Quoted text
# inside a stage is an ARGUMENT and never a command, which is what lets `grep -rn "obsidian quickadd" f`
# pass without any exemption list: that `obsidian` is a pattern, not a command.
my $code = code_only($s);
my @stages;
{
  my @reg = regions($code);
  my $live = sub {
    my $p = shift;
    my ($lo, $hi) = (0, $#reg);
    while ($lo <= $hi) {
      my $mid = int(($lo + $hi) / 2);
      if    ($p < $reg[$mid][0]) { $hi = $mid - 1 }
      elsif ($p > $reg[$mid][1]) { $lo = $mid + 1 }
      else                       { return 0 }
    }
    return 1;
  };
  my $start = 0;
  my $n = length $code;
  for (my $i = 0; $i < $n; $i++) {
    my $c = substr($code, $i, 1);
    next unless $c =~ /[;&|\n(`]/;
    next unless $live->($i);
    push @stages, substr($code, $start, $i - $start);
    $start = $i + 1;
  }
  push @stages, substr($code, $start);
}

for my $stage (@stages) {
  # leading whitespace and VAR=value assignments
  my $t = $stage;
  $t =~ s/^\s+//;
  while ($t =~ s/^[a-z_][a-z0-9_]*=(?:$DQ[^$DQ]*$DQ|$SQ[^$SQ]*$SQ|\S*)\s+//) { }
  # the command token, which may be a path; its BASENAME decides, so /usr/local/bin/obsidian, ./obsidian
  # and the real binary name obsidian-cli all match, and none of them needed a list
  next unless $t =~ s/^(\S+)\s+//;
  my $cmd = $1;
  $cmd =~ s{^.*/}{};
  next unless $cmd =~ /^obsidian/;
  # the first bare argument token, skipping key=value pairs, flags, and a bare --
  my $word = "";
  while (length $t) {
    $t =~ s/^\s+//;
    last unless length $t;
    if ($t =~ s/^--\s+//)                                      { next }
    if ($t =~ s/^-[^\s]*\s*//)                                 { next }
    if ($t =~ s/^[a-z_-]+=(?:$DQ[^$DQ]*$DQ|$SQ[^$SQ]*$SQ|\S*)\s*//) { next }
    if ($t =~ /^([a-z0-9:_-]+)/)                               { $word = $1 }
    last;
  }
  next unless length $word;
  next unless $word =~ /^(?:$OPAQUE_RE)$/;
  if ($word eq "eval") {
    # eval is a SANCTIONED road — CLAUDE.md: drive live vaults via the obsidian CLI, eval and append — so
    # it is not refused for existing. What is refused is a CALL that invokes: the api name followed by an
    # open parenthesis. Testing the bare name refused code that merely MENTIONED it in a string or a
    # comment, which was the first version failure surviving inside the one place free text is still read.
    next unless $stage =~ /(?:executecommandbyid|executechoice)\s*\(/
             || $stage =~ /quickaddapi\s*\.\s*[a-z]+\s*\(/;
    print "an obsidian CLI eval whose code CALLS a command or a choice";
    exit 0;
  }
  print "an obsidian-family binary in command position with the command word `$word`";
  exit 0;
}

exit 0;
' "$scratch" "$CAP_BYTES") || refuse "the tool input could not be examined"

case "$found" in
  "") exit 0 ;;
  TOOLARGE) refuse "this call is larger than $CAP_BYTES bytes and carries something shaped like an Obsidian command road, so it cannot be checked inside the time the hook is given; split it into smaller calls" ;;
  *) refuse "this call invokes an Obsidian command or a QuickAdd choice: $found" ;;
esac
