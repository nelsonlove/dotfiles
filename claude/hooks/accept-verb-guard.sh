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
#    * `mcp__claude-in-chrome__navigate`, by exact name, whose payload is a URL to open: refused when the URL
#      IS an `obsidian://` one (scheme position, not merely containing one) carrying a `commandid` OR a
#      `commandname` — the advanced-uri plugin runs a command by display NAME too, and a verb is a named
#      thing, so that is the spelling reached for first. A browser tool that opens a URL invokes a command as
#      surely as a shell does. By exact tool name rather than the claude-in-chrome family, because a hook on
#      every browser call is latency for nothing.
#    * `obsidian_call_tool`, a DISPATCHER (tools-code-mode.ts:177) whose payload names another tool and
#      carries its arguments — so its payload is a call, and the same rule is applied ONE LEVEL DOWN to the
#      `name` it gives. One level only: a dispatcher naming a dispatcher is refused rather than followed,
#      and a target that is absent or unreadable is refused, because a call whose target cannot be read must
#      not run. It is not refused wholesale, which would refuse all 65 tools it routes to.
#    Every OTHER MCP tool's payload is DATA handed to that tool, never a command line. `obsidian_write_note`
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
#      "runners" — but it is NOT coverage, and the second review was right to call the old sentence out:
#      it inspects a stage's FIRST token only, so any wrapper word in front of the binary defeats it
#      (`timeout 30 obsidian command id=x`, and `env`, `sudo`, `nohup`, `exec`, `command`, `time`,
#      `xargs -I{}`), as do same-line shell keywords (`{ … }`, `if … then`, `while`, `!`). Multi-line forms
#      ARE caught. That whole class is in the boundary paragraph, because enumerating wrappers is what the
#      cut removed and re-adding one word would re-open the false-refusal class it cost.
#    * THE BINARY is decided by BASENAME beginning `obsidian`, so `/usr/local/bin/obsidian`, `./obsidian`,
#      `/Applications/Obsidian.app/Contents/MacOS/obsidian-cli`, a QUOTED path, one carrying a
#      backslash-escaped space, and the real binary name `obsidian-cli` all match. Two histories worth
#      keeping: the version before this keyed on the literal token `obsidian` and missed every path form;
#      and then the FAST PATH in front of the parser disagreed with it, exiting 0 on a quoted path and on
#      any `;` `&` `|` inside an earlier token, so the worked examples above were true of the parser and
#      false of the hook. The fast path is now TWO INDEPENDENT TESTS with no chain between them — is the
#      word `obsidian` present, and is an opaque word present — which cannot break that way and errs
#      toward running the parser.
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
# THIS FILE HAS BEEN QUADRATIC FOUR TIMES, and that number is in the header on purpose. The quote-region
# builder searched for both quote characters on every iteration. A per-hit rescan of the region list in the
# road scan took 396 KB to 9.74 s and 1 MB to 72 s. The heredoc-opener liveness test walked the region list
# per opener: 200 KB took 9.58 s and 800 KB took 151 s. And the leading-assignment stripper copied the rest
# of the stage per assignment: 1.76 MB took 10.26 s and 4 MB took 52.68 s. Every one was a FAIL-OPEN, because
# a hook the harness kills reads as allow, and every one passed every verdict case while it was broken. All
# four are single passes now — binary search for a position, `\G` matching instead of copying — and the
# worst shape that took 151 s answers in 0.73 s.
#
# SO THE TEST FOR THIS IS A PROPERTY, not a shape. `claude/tests/accept-verb-guard/property-timing.py` runs
# every payload shape at 1x, 2x and 4x size and fails if the time grows more than 6x for a 4x increase
# (linear is 4x, quadratic is 16x), and fails if a verdict CHANGES with size. It earned its place twice
# before it was committed: it caught two of the four quadratics on the build it was written against, and
# then it caught a bug in the fix itself — one `(?:…)+` repetition over 50,000 assignments hit perl's
# repetition limit and silently matched nothing, so the same payload refused at 200 KB and ALLOWED at
# 400 KB. No verdict case would have seen that.
#
# THE CAP IS DERIVED, NOT CHOSEN, and the arithmetic is here so it can be redone when either number changes.
# Worst measured rate after the fixes, taken pessimistically at 1 MB where fixed process start-up inflates
# the per-MB figure: 0.94 s/MB. Half the declared 10 s timeout is 5 s, and 5 / 0.94 = 5.3 MB. The cap STAYS
# AT 4 MB rather than widening to 5: the arithmetic permits 5, nothing is gained by widening the window in
# which a payload goes unread, and a fail-closed bound is not widened without a reason. At 4 MB the worst
# shape costs about 3.8 s.
#
# WHAT THIS GUARD DOES NOT STOP, named rather than implied, and all of it following from the honest claim
# above: A WRAPPER WORD OR A SHELL KEYWORD in front of the binary on the same line — `timeout 30 obsidian
# command id=x`, and `env`, `sudo`, `nohup`, `exec`, `command`, `time`, `xargs -I{}`, `{ … }`, `if … then`,
# `while`, `!` — because the road test reads a stage's first token, and enumerating wrappers is exactly what
# the cut removed (multi-line `if … then` on its own line IS caught); an `eval` whose call is assembled so
# the api name and its parenthesis are not adjacent (`"executeCommandById"'('`), or reached by bracket
# notation, or held in a variable, since the test is a call shape and not a JS parser; a dispatcher naming a
# dispatcher; a shell by path or with an option before `-c`; an interpreter shelling out to the CLI or posting
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
      # trimmed as well as lowercased: `{"command":" command "}` slipped past the case list untrimmed
      cli_cmd=$(printf '%s' "$cli_cmd" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
      case "$cli_cmd" in
        command|quickadd|quickadd:run|quickadd:run-template|quickadd:run-template-from-folder)
          refuse "the tool $tool is given the obsidian CLI command word \`$cli_cmd\`, which runs an Obsidian command or a QuickAdd choice" ;;
        eval)
          # EVERY params value, not only `params.code`. The schema declares no `code` key at all — `params`
          # is a record of arbitrary keys — so a claim resting on that name rested on nothing, and an eval
          # body under any other key passed. When the command word is `eval` the params ARE the command
          # line, which is why reading them all stays inside the rule; for every other command word only
          # the command-naming field is read and `params.content` is never touched.
          cli_code=$(printf '%s' "$input" | jq -r '(.tool_input // {}) | (.params // {}) | [.. | scalars | tostring] | join(" ")' 2>/dev/null) \
            || refuse "the tool input could not be examined"
          cli_code=$(printf '%s' "$cli_code" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
          case "$cli_code" in
            *executecommandbyid\(*|*executechoice\(*) refuse "the tool $tool is given an obsidian CLI eval whose code CALLS a command or a choice" ;;
          esac ;;
      esac ;;
    obsidian_call_tool)
      # A DISPATCHER: its payload names another tool and carries that tool's arguments, so the payload IS a
      # call. It is not put on the refused-by-name list wholesale, because it routes to all 65 tools and
      # that would refuse every one of them the day code mode is on. Instead the same rule is applied ONE
      # LEVEL DOWN: the `name` field is read and judged as a tool name would be. One level only — a
      # dispatcher naming a dispatcher is a named boundary, not a recursion. A name that is absent,
      # unreadable or unresolvable REFUSES, which is this guard doctrine: a call whose target cannot be
      # read must not run. (Registered only in code mode, which is off by default, so no risk today and a
      # certainty the day a session connects that way.)
      inner=$(printf '%s' "$input" | jq -r '(.tool_input // {}) | (.name // .tool // "") | tostring' 2>/dev/null) \
        || refuse "the dispatched tool name could not be read"
      inner=$(printf '%s' "$inner" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
      [ -n "$inner" ] || refuse "the tool $tool dispatches another tool but names none, and a call whose target cannot be read must not run"
      case "$inner" in
        *run_command*|*runcommand*|*execute_command*|*executecommand*)
          refuse "the tool $tool dispatches \`$inner\`, which exists to run an Obsidian command" ;;
        *execute*)
          case "$inner" in
            *obsidian*|*vault*) refuse "the tool $tool dispatches \`$inner\`, which runs something in the vault" ;;
          esac ;;
        obsidian_call_tool)
          refuse "the tool $tool dispatches itself, and this guard reads one level only" ;;
        obsidian_cli)
          inner_cmd=$(printf '%s' "$input" | jq -r '(.tool_input // {}) | (.args // .arguments // {}) | (.command // "") | tostring' 2>/dev/null) \
            || refuse "the dispatched command word could not be read"
          inner_cmd=$(printf '%s' "$inner_cmd" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
          case "$inner_cmd" in
            command|quickadd|quickadd:run|quickadd:run-template|quickadd:run-template-from-folder)
              refuse "the tool $tool dispatches obsidian_cli with the command word \`$inner_cmd\`, which runs an Obsidian command or a QuickAdd choice" ;;
            eval)
              inner_code=$(printf '%s' "$input" | jq -r '(.tool_input // {}) | (.args // .arguments // {}) | (.params // {}) | [.. | scalars | tostring] | join(" ")' 2>/dev/null) \
                || refuse "the dispatched eval body could not be read"
              inner_code=$(printf '%s' "$inner_code" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
              case "$inner_code" in
                *executecommandbyid\(*|*executechoice\(*)
                  refuse "the tool $tool dispatches an obsidian_cli eval whose code CALLS a command or a choice" ;;
              esac ;;
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
      # `commandname=` is the SAME road: the advanced-uri plugin runs a command by its display NAME, and a
      # verb is a named thing, so that is the spelling reached for first. (The plugin is not installed in
      # ~/obsidian today, only in a test vault — which is a reason to watch the road, not to ignore it.)
      for one in $nav; do
        case "$one" in
          obsidian://*commandid*|obsidian://*commandname*)
            refuse "the tool $tool is being asked to open an obsidian:// uri that names a command, which runs it" ;;
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
# CRLF is normalised so that a heredoc delimiter written on a CRLF line matches its terminator: bash sees
# the carriage return on BOTH, and stripping it from both keeps the guard reading what the shell reads.
$s =~ s/\r\n/\n/g;
# NOT lowercased here. A heredoc terminator is case-SENSITIVE to the shell, and lowercasing the payload
# first made a body line `eof` end a `<<EOF` body early, so the rest of the body was read as code and a
# documented call inside it was refused. The road tests lowercase their own copy instead.

# THE FAST PATH: is there anything here shaped like the road at all? Keyed on the grammar — a token whose
# basename begins with `obsidian` followed by an opaque command word — never on the word "obsidian",
# because this fleet writes `~/obsidian/...` in nearly every payload. It fails TOWARD the slow path.
my $OPAQUE_RE = qr{command|eval|quickadd(?::run(?:-template(?:-from-folder)?)?)?};
# THE FAST PATH IS TWO INDEPENDENT TESTS WITH NO CHAIN BETWEEN THEM, which is what "fail toward the parser"
# has to mean. The previous version matched the binary and the command word in ONE expression with a
# repetition between them, and that chain broke on three ordinary things — a QUOTED path (`.../obsidian`
# in quotes), any `;` `&` or `|` inside an earlier token, and more than about 65,000 tokens in between,
# where perl silently gives up on the repetition. Each break exited 0 BEFORE the parser, which would have
# refused all three. Two separate questions cannot break that way: is the word `obsidian` here at all, and
# is an opaque command word here as a whole word. Both true, and the parser decides.
my $lc = lc $s;
exit 0 unless index($lc, "obsidian") >= 0;
exit 0 unless $lc =~ m{(?:^|[^a-z0-9:_-])(?:$OPAQUE_RE)(?![a-z0-9_-])};

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
    # A dollar-quoted run is ANSI-C quoting, where a backslash escapes the closing quote. Treating it as a
    # plain single-quoted run ended it early on an escaped quote inside one, which shifted every quote pair
    # after it and made the rest of the payload read as quoted text.
    if ($q eq $SQ && $k > 0 && substr($t, $k - 1, 1) eq "\$") {
      my $j = $k + 1;
      while ($j < $n) { my $d = substr($t, $j, 1); last if $d eq $SQ; $j += ($d eq "\\") ? 2 : 1 }
      $close = ($j > $n) ? $n : $j;
    }
    elsif ($q eq $SQ) { $close = index($t, $SQ, $k + 1); $close = $n if $close < 0 }
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
    # BINARY SEARCH, not a walk. A walk here cost 9.58 s at 200 KB and 151 s at 800 KB on a line carrying
    # many heredoc openers, because each opener asked the whole region list again — the FOURTH time a
    # per-position question in this file was answered by walking a list, and the second time it was a
    # fail-open past the declared timeout.
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
    # The delimiter word may carry anything a shell word may carry — `<<EOF!` is a legal delimiter, and the
    # narrower class read it as `EOF` so the terminator never matched and the rest of the payload was
    # swallowed as body. It may also be quoted or backslash-escaped.
    while ($code =~ /<<(-?)\s*(?:\\([^\s;&|<>()]+)|$DQ([^$DQ]*)$DQ|$SQ([^$SQ]*)$SQ|([^\s;&|<>()`]+))/gi) {
      my $at = pos($code) - length($&);
      next unless $live->($at);
      next if substr($code, $at + 2, 1) eq "<";
      # An ARITHMETIC left shift is not a heredoc: in `$((1<<2))` the `<<` follows a digit, where a real
      # heredoc redirection follows whitespace or a file descriptor. Reading it as an opener created a
      # phantom body with delimiter `2` that swallowed every line after it, including a real call.
      next if $at > 0 && substr($code, $at - 1, 1) =~ /[a-z0-9_)]/i;
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
        # case-SENSITIVE, as a shell is: `eof` does not end a `<<EOF` body
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
my $code = lc code_only($s);
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
  # NOTHING IS COPIED PER TOKEN. Both loops below used `s///` on the remaining text, which copies the rest
  # of the stage every time: one stage of leading `VAR=value` assignments cost 10.26 s at 1.76 MB — past
  # the declared timeout, so a bypass — and 52.68 s at 4 MB, just under the old cap. `\G` matching walks
  # the same string in place.
  pos($stage) = 0;
  $stage =~ /\G\s+/gc;
  # every leading VAR=value assignment, one at a time but WITHOUT copying: `\G…/gc` advances the match
  # position in place. Two wrong ways were tried first. `while ($t =~ s/^…//)` copied the rest of the stage
  # per assignment, which cost 52 s at 4 MB. Then ONE match with a `(?:…)+` repetition, which hit perl
  # repetition limit at about 50,000 assignments and silently matched nothing — so the same payload refused
  # at 200 KB and ALLOWED at 400 KB. The property timing test caught that by noticing the verdict changed
  # with the size, which no verdict case would have.
  while ($stage =~ /\G[a-z_][a-z0-9_]*=(?:$DQ[^$DQ]*$DQ|$SQ[^$SQ]*$SQ|\S*)\s+/gc) { }
  # the command token, which may be a path, and may carry backslash-escaped spaces (`/opt/my\ dir/obsidian`
  # is one word to the shell; taking `\S+` truncated it before the basename). Its BASENAME decides, so
  # /usr/local/bin/obsidian, ./obsidian, a quoted path and the real binary name obsidian-cli all match.
  next unless $stage =~ /\G((?:[^\s\\]|\\.)+)\s+/gc;
  my $cmd = $1;
  $cmd =~ s/^[$DQ$SQ]+//;
  $cmd =~ s{^.*/}{};
  $cmd =~ s/^[$DQ$SQ]+//;
  next unless $cmd =~ /^obsidian/;
  # the first bare argument token, skipping key=value pairs, flags, and a bare --
  my $word = "";
  while (pos($stage) < length $stage) {
    $stage =~ /\G\s+/gc;
    last if pos($stage) >= length $stage;
    if ($stage =~ /\G--\s+/gc)                                          { next }
    if ($stage =~ /\G-[^\s]*\s*/gc)                                     { next }
    if ($stage =~ /\G[a-z_-]+=(?:$DQ[^$DQ]*$DQ|$SQ[^$SQ]*$SQ|\S*)\s*/gc) { next }
    if ($stage =~ /\G([a-z0-9:_-]+)/gc)                                 { $word = $1 }
    last;
  }
  next unless length $word;
  next unless $word =~ /^(?:$OPAQUE_RE)$/;
  if ($word eq "eval") {
    # eval is a SANCTIONED road — CLAUDE.md: drive live vaults via the obsidian CLI, eval and append — so
    # it is not refused for existing. What is refused is a CALL that invokes: the api name followed by an
    # open parenthesis. Testing the bare name refused code that merely MENTIONED it in a string or a
    # comment, which was the first version failure surviving inside the one place free text is still read.
    pos($stage) = undef;
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
