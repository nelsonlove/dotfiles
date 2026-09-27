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
# WHY THIS IS THE SECOND VERSION. The first (dotfiles #53) refused when a verb's NAME appeared anywhere
# in a payload beside any of several markers. That is a vocabulary test, and the fleet's vocabulary is
# exactly these words: within the hour it refused a python heredoc writing prose about `eval` and
# `executeChoice`, a heredoc adding the rule-19 sentence to a spec note, a heredoc appending a notebook
# section naming the four verbs, and the write of a test harness whose own code quotes
# `executeChoice('Verify current note')` to stub it. Three of the four were other sessions. Reverted (#54).
#
# THE RULE, as the captain put it on 2026-09-27, and the whole of what this file does: a verb name is a
# CALL when it sits in the VALUE of a known invoking key, and PROSE everywhere else — including every
# other quoted run, every heredoc body, and the harness's own metadata. Quote-awareness is how the value
# is found, not the rule itself; "a verb name inside quotes" can never be the test, because a real call
# carries its verb name inside quotes too.
#
# THE INVOKING KEYS, the whole list:
#   * `command=` and `code=` on the obsidian CLI — the value is the quoted run or bare token after `=`;
#   * `commandid=` in an `obsidian://advanced-uri` — the value runs to the next `&` and KEEPS the spaces
#     that `%20` decodes to. This road is why v2.1 exists rather than v2: it is the only road actually
#     present in this repo (a live tickle job at tickle/scripts/vault-skills-export/export.sh:21 fires
#     `open -g 'obsidian://advanced-uri?…&commandid=…'`, seven Alfred scripts build the same URI, and
#     info.plist:2967 aims one at QuickAdd), so it is the first shape a session copies;
#   * an obsidian CLI ` eval ` whose argument names a verb;
#   * keystroke automation — `keystroke`, `key code`, `cliclick` — with an `osascript` or `cliclick`
#     driver actually present, because those reach the palette with no API at all;
#   * a Local REST API `/commands` call on 127.0.0.1 / localhost / :27123, whose body carries the name;
#   * a run tool's own payload: a tool whose name carries `run_command` or `execute_command`, or a
#     looser `execute` only when the name also says obsidian or vault, so that widening the matchers
#     later cannot make this vault rule judge another server's `shortcuts_execute`.
#
# A quoted run is a value being USED, not text being carried, when it is handed to something that runs
# it: `sh`/`bash`/`zsh` with `-c`, a shell `eval`, `xargs`, `osascript`, `open` and `open location` /
# `openLocation(` (which hand a URI to Obsidian), and `curl`/`wget` (which send the REST call). So
# `bash -c "obsidian command=\"…\""` is caught, and the same text inside a `printf` is not.
#
# WHAT IS NOT AN INVOCATION, deliberately: `node -e`, `python3 -c` and `bash <file>` — code they run
# cannot reach Obsidian's `app` object, so a harness that stubs `executeChoice` and asserts against it
# invokes nothing however exactly it quotes the verbs it tests. Nor is the harness's own metadata: the
# normalised payload leaves out the Bash tool's `description` field, because Claude Code sends one on
# every call and nothing executes it. The general rule for that: only fields that can carry a call are
# normalised, never the harness's own metadata about the call.
#
# THE WALL is a heredoc and nothing else. Only `<<` puts unquoted written text inside a payload, and the
# normalisation collapses newlines, so nothing downstream can tell where the body ended — hence the four
# v1 regressions are held by position. A redirect is NOT a wall, and treating it as one was wrong twice:
# it refused prose written as `printf '…' > note.md` (v1's failure surviving in the trailing-redirect
# idiom), and it let a real call placed after an early `2>/dev/null` pass unread.
#
# THE WINDOW IS THE VALUE, never a character count. A key's value ends where the value ends, and a
# stage-shaped value ends at the next unquoted `;`, `&&`, `||`, `|` or `&`. That is what stops an
# ordinary choice call followed by a log line that names a verb from being refused.
#
# ONE TAIL RULE: `requestrevision` is the only verb with no distinctive ending, and the plural English
# word "request revisions" squashes to a superstring of it, so a match followed by `s` is prose. The
# real id form (`Request revision.md#choice`) is followed by `m`.
#
# THE ACCEPTED BOUNDARY, named rather than implied. A call whose argument this guard cannot READ is not
# refused: a payload decoded from base64 at runtime, a choice id fetched through a variable, or a name
# assembled through variables (a name split across ADJACENT literals IS caught, because squashing
# rejoins it). Beside those sits one readable shape: a real invocation placed after a heredoc write in
# the same compound command, which the wall reads as written text. The captain accepted it on
# 2026-09-27; dotfiles issue #59 holds it, and its closer is now this same value test carried into the
# heredoc body rather than the stage splitter first proposed. And one more, found by the soak: a name
# spelled in characters that are not ASCII letters or digits — full-width `ｖｅｒｉｆｙ`, or any homoglyph — is not
# matched, because the squash keeps only [a-z0-9]. Such a name also matches no real choice, so the
# call it makes invokes nothing; if a verb is ever named in non-ASCII, the matcher needs a Unicode
# fold (NFKC, or a `tr` of the full-width block) before the squash. Rule 19 stands above this hook: it
# closes the shapes a session reaches for by habit, and it is not an authentication boundary.
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
# The cost is bounded by reading the payload once into a scratch file and then jumping quote to quote
# and key to key with `index`, never walking it character by character. Every per-position question is
# then answered by binary search over two lists built once — the quoted runs, and the live stage
# separators — because the first version of this matcher walked them linearly and took 56 SECONDS on a
# 1.9 MB payload carrying 120,000 quoted markers. That is not a slow guard, it is an OPEN one: a hook
# killed by a harness timeout never reaches its EXIT trap, and anything but exit 2 reads as allow. With
# the searches in place the same payload answers in 1 s, a 10 MB payload with a real call at the front
# in 2 s, and an 8 MB payload carrying 200,000 markers in 2 s. Measured, not argued.
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
  printf 'If you are writing ABOUT a verb rather than calling one: the name is only ever read as a call when it sits in the VALUE of an invoking key, so quote it as text, put it in a heredoc body, or write it with Edit/Write, which this hook does not watch.\n' >&2
  printf 'Writing a commit message or an issue body that quotes a call: `git commit -F -` with a heredoc, or `gh issue create --body-file <path>` after writing the file, both pass.\n' >&2
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
# are decoded, case is dropped, non-breaking spaces and leftover escapes become spaces. `description` is
# dropped first: it is the harness's own note about the call, nothing runs it, and leaving it in let a
# description naming a verb refuse an ordinary choice call beside it.
scratch=$(mktemp -t accept-verb-guard) || refuse "no scratch file could be made, so this call cannot be read"
printf '%s' "$input" | jq -r '(.tool_input // {}) | del(.description) | [.. | scalars | tostring] | join(" ")' 2>/dev/null \
  | perl -pe 's/\\[nrt]/ /g; s/\\u00a0/ /gi; s/%([0-9a-fA-F]{2})/chr(hex($1))/ge; $_ = lc $_; s/\xc2\xa0/ /g; s/\s+/ /g' > "$scratch" \
  || refuse "the tool input could not be normalised"
[ -s "$scratch" ] || printf '{}' > "$scratch"

# --- one pass: is a verb named, and does it sit in the value of an invoking key? --------------------
# Prints "<verb><TAB><why>" for a call, "<verb><TAB>" when a verb is only named, nothing when no verb is
# named at all. One perl run rather than two, because the second used to re-read the same file.
found=$(perl -e '
use strict;
my $SQ = chr(39);
my $DQ = chr(34);

my $file = shift; open my $fh, "<", $file or exit 0; local $/; my $s = <$fh>; exit 0 unless defined $s;
my $n = length $s;
my @verbs = qw(verifycurrentnote reopencurrentnote requestrevision answercurrentnote);

sub verb_in {
  my $w = shift; return "" unless defined $w; $w =~ s/[^a-z0-9]//g;
  for my $v (@verbs) {
    my $p = 0;
    while ((my $j = index($w, $v, $p)) >= 0) {
      $p = $j + 1;
      my $next = ($j + length($v) < length($w)) ? substr($w, $j + length($v), 1) : "";
      next if $v eq "requestrevision" && defined($next) && $next eq "s";
      return $v;
    }
  }
  return "";
}

my $named = verb_in($s);
exit 0 unless $named;

# --- the quoted regions, found by jumping quote to quote --------------------------------------------
my @reg;
my $i = 0;
while ($i < $n) {
  my $a = index($s, $SQ, $i);
  my $b = index($s, $DQ, $i);
  my $k = ($a < 0) ? $b : (($b < 0) ? $a : ($a < $b ? $a : $b));
  last if $k < 0;
  if ($k > 0 && substr($s, $k - 1, 1) eq "\\") { $i = $k + 1; next }
  my $q = substr($s, $k, 1);
  my $close;
  if ($q eq $SQ) {
    $close = index($s, $SQ, $k + 1);
    $close = $n if $close < 0;
  } else {
    my $j = $k + 1;
    while ($j < $n) {
      my $d = substr($s, $j, 1);
      last if $d eq $DQ;
      $j += ($d eq "\\") ? 2 : 1;
    }
    $close = ($j > $n) ? $n : $j;
  }
  push @reg, [$k, $close];
  $i = $close + 1;
}

# A key found inside a quoted run is text the command is CARRYING, not a key the command is using —
# unless the run is itself handed to something that runs it: a shell with -c, a shell eval, xargs,
# osascript (which reaches the palette through the GUI), or `open`/`open location` (which hands a
# URI to Obsidian). `node -e` and `python3 -c` are deliberately not on that list: code they run cannot
# reach Obsidian.
# Which quoted region holds a position, by binary search: the regions are in order and do not overlap.
# A linear walk here cost 56 seconds on a 1.9 MB payload carrying 120,000 quoted markers, because every
# marker rescanned every region — and a hook that slow is killed by the harness, never reaches its EXIT
# trap, and so reads as ALLOW. Speed is safety in this file.
sub region_at {
  my $p = shift;
  my ($lo, $hi) = (0, $#reg);
  while ($lo <= $hi) {
    my $mid = int(($lo + $hi) / 2);
    if    ($p < $reg[$mid][0]) { $hi = $mid - 1 }
    elsif ($p > $reg[$mid][1]) { $lo = $mid + 1 }
    else                       { return $mid }
  }
  return -1;
}
my %runs_it;   # region index -> is its content handed to something that runs it
sub live {
  my $p = shift;
  my $idx = region_at($p);
  return 1 if $idx < 0;
  return $runs_it{$idx} if exists $runs_it{$idx};
  {
    my $r = $reg[$idx];
    my $back = $r->[0] > 60 ? 60 : $r->[0];
    my $ctx = substr($s, $r->[0] - $back, $back);
    my $runs = 0;
    $runs = 1 if $ctx =~ /(?:^|[\s;&|(])(?:ba|z|da|k)?sh\s+-[a-z]{0,3}c\s*$/;
    $runs = 1 if $ctx =~ /(?:^|[\s;&|(])eval\s+$/;
    $runs = 1 if $ctx =~ /(?:^|[\s;&|(])xargs\b[^|;&]*$/;
    $runs = 1 if $ctx =~ /osascript\b[^|;&]*$/;
    $runs = 1 if $ctx =~ /(?:^|[\s;&|(])open\b[^|;&]*$/;
    $runs = 1 if $ctx =~ /open\s*location\s*$/;
    $runs = 1 if $ctx =~ /openlocation\s*\(\s*$/;
    $runs = 1 if $ctx =~ /(?:^|[\s;&|(])(?:curl|wget)\b[^|;&]*$/;
    $runs_it{$idx} = $runs;
    return $runs;
  }
}

# --- the wall ---------------------------------------------------------------------------------------
# Only a heredoc puts unquoted written text in the payload, and the normalisation has collapsed the
# newlines, so nothing downstream can tell where the body ended. A redirect is not a wall: what it
# writes is either quoted (the quote rule covers it) or comes from a heredoc.
my $wall = $n + 1;
{
  my $p = 0;
  while ((my $k = index($s, "<<", $p)) >= 0) {
    $p = $k + 1;
    if (live($k)) { $wall = $k; last }
  }
}

# Every live stage separator, found once. Doing this per marker meant five fresh scans of the rest of the
# payload each time, which is the same trap as the region walk.
my @sep;
{
  my %seen;
  for my $sepchar (";", "|", "&") {
    my $q = 0;
    while ((my $k = index($s, $sepchar, $q)) >= 0) {
      $q = $k + 1;
      next unless live($k);
      $seen{$k} = 1;
    }
  }
  @sep = sort { $a <=> $b } keys %seen;
}
sub stage_end {
  my $from = shift;
  my ($lo, $hi) = (0, $#sep);
  my $found = $wall;
  while ($lo <= $hi) {
    my $mid = int(($lo + $hi) / 2);
    if ($sep[$mid] >= $from) { $found = $sep[$mid] if $sep[$mid] < $found; $hi = $mid - 1 }
    else { $lo = $mid + 1 }
  }
  return $found;
}

sub present {
  my $word = shift;
  my $q = 0;
  while ((my $k = index($s, $word, $q)) >= 0) { $q = $k + 1; return 1 if live($k) }
  return 0;
}

# The VALUE of a key: the quoted run that follows it, or the bare token up to the next separator. This
# is the whole of the ruled test — a verb name in a value is a call, a verb name anywhere else is
# prose — so the window is the value and never a character count.
sub value_at {
  my ($from, $stop_amp) = @_;
  my $p = $from;
  $p++ while $p < $n && substr($s, $p, 1) =~ /\s/;
  return "" if $p >= $n;
  my $c = substr($s, $p, 1);
  if ($c eq $SQ || $c eq $DQ) {
    my $close;
    if ($c eq $SQ) {
      $close = index($s, $SQ, $p + 1);
      $close = $n if $close < 0;
    } else {
      # a double-quoted value ends at an UNESCAPED quote: `code="executeChoice(\"Verify current
      # note\")"` is one value, and stopping at the first \" read only `executeChoice(`, which let six
      # battery cases through the prototype.
      my $j = $p + 1;
      while ($j < $n) {
        my $d = substr($s, $j, 1);
        last if $d eq $DQ;
        $j += ($d eq "\\") ? 2 : 1;
      }
      $close = ($j > $n) ? $n : $j;
    }
    # No cap. The value is bounded by its own closing quote, and a cap is a bypass: pad a choice id
    # with 400 characters and the name falls outside the window.
    return substr($s, $p + 1, $close - $p - 1);
  }
  my $end = $p;
  while ($end < $n) {
    my $d = substr($s, $end, 1);
    last if $d =~ /[;|)]/;
    last if !$stop_amp && $d =~ /\s/;   # a plain token ends at whitespace
    last if $d eq $SQ || $d eq $DQ;
    last if $stop_amp && $d eq "&";      # a uri parameter ends at & and KEEPS its decoded spaces
    $end++;
  }
  return substr($s, $p, $end - $p);
}

# marker, must-start-a-word, what must also be present, how to take the value, and what it means
my @shapes = (
  ["command=",   1, "obsidian", "token", "the obsidian CLI with command= whose value names a verb"],
  ["code=",      1, "obsidian", "token", "the obsidian CLI with code= whose value names a verb"],
  ["commandid=", 1, "obsidian", "uri",   "an obsidian advanced-uri whose commandid names a verb"],
  [" eval ",     0, "obsidian", "token", "an obsidian CLI eval whose argument names a verb"],
  ["keystroke",  0, "driver",   "token", "keystroke automation typing a verb name into the palette"],
  ["key code",   0, "driver",   "stage", "keystroke automation typing a verb name into the palette"],
  ["cliclick",   0, "driver",   "stage", "keystroke automation typing a verb name into the palette"],
  ["/commands",  0, "rest",     "stage", "a Local REST API command call whose body names a verb"],
);

my %gate = (
  obsidian => present("obsidian"),
  driver   => (present("osascript") || present("cliclick")),
  rest     => (present("127.0.0.1") || present("localhost") || present("27123")),
);

for my $sh (@shapes) {
  my ($marker, $at_word_start, $needs, $kind, $why) = @$sh;
  next unless $gate{$needs};
  my $pos = 0;
  while ((my $k = index($s, $marker, $pos)) >= 0) {
    $pos = $k + 1;
    next if $k >= $wall;
    next unless live($k);
    if ($at_word_start && $k > 0) {
      my $before = substr($s, $k - 1, 1);
      next unless $before =~ /[\s;&|()?=]/;
    }
    my $value;
    if ($kind eq "stage") {
      my $end = stage_end($k + length($marker));
      my $len = $end - $k;
      $value = ($len > 0) ? substr($s, $k, $len) : "";
    } else {
      $value = value_at($k + length($marker), ($kind eq "uri") ? 1 : 0);
    }
    my $v = verb_in($value);
    if ($v) { print "$v\t$why"; exit 0 }
  }
}

print "$named\t";
exit 0;
' "$scratch") || refuse "the tool input could not be examined"
verb=${found%%$'\t'*}
how=${found#*$'\t'}
[ -n "$verb" ] || exit 0

# A run tool carries no shell text, so its whole payload is the argument.
if [ -z "$how" ]; then
  case "$tool_l" in
    *run_command*|*runcommand*|*execute_command*|*executecommand*)
      how="the tool $tool exists to run a command, and its payload names a verb" ;;
    *execute*)
      case "$tool_l" in
        *obsidian*|*vault*) how="the tool $tool exists to run something, and its payload names a verb" ;;
      esac ;;
  esac
fi

[ -z "$how" ] || refuse "this call invokes the accept verb '$verb': $how"

# A verb named in text that invokes nothing — a note being written, a harness being generated, a log
# line, a printf, a grep pattern, a commit message — passes. That is the whole point of this version.
exit 0
