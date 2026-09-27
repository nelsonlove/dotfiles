# Tests for `claude/hooks/accept-verb-guard.sh`

Nothing here installs. `install/manifest.yaml` maps `claude/hooks` and `claude/bin` to `~/.claude/`; this directory is deliberately not in it, because these are tests, not machinery.

**No test here ever invokes anything.** Every case is the hook's own answer to a payload fed on stdin. No accept verb is invoked, no Obsidian command is issued, no `obsidian` CLI call is made, and nothing is run against the vault — 01.65 rule 19 forbids invoking a verb even on a test artifact, so the test is always the hook's answer to text, never a call.

## Run them

```sh
python3 claude/tests/accept-verb-guard/make-battery.py            # writes the payload corpus to /tmp/v3/cases
python3 claude/tests/accept-verb-guard/run-battery.py claude/hooks/accept-verb-guard.sh
python3 claude/tests/accept-verb-guard/timing.py  claude/hooks/accept-verb-guard.sh
```

## What each one is for

| file | what it asserts | status |
|---|---|---|
| `make-battery.py` | writes 63 payloads plus a manifest of expected verdicts: the four invocation roads refuse whatever they name, prose and reads and writes pass, and a call the guard cannot read refuses | current |
| `run-battery.py` | runs that corpus and reports only failures | current |
| `timing.py` | five cases that fail on TIME as well as verdict, and the cap's behaviour on both sides | current |
| `timing-floor.sh` | the soak session's original timing floor, written against the version that matched verb names | superseded by `timing.py`, kept because its threshold argument is the clearest statement of why a slow guard is an *open* guard |
| `verb-list-drift.sh` | that the two hardcoded verb-name lists in the old guard agreed with each other | **obsolete by design**: the inversion removed every verb name from the code, so there is nothing left to drift. Kept for its finding — its author first claimed the battery would stay green on a rename, tested it instead of asserting it, and found the opposite (10 of 39 cases fail on one list, 2 of 39 on the other) |
| `prove-shared-lib-path.sh` | that one shared file resolves from both install roads — the hook's `~/.claude/hooks` symlink and tickle's own config home | not this hook's test at all; it is the proof a later package was ruled to produce before unifying the duplicated pause-flag parser, kept here so it is not lost |

## Two warnings earned the hard way

**Payload bytes must not pass through a shell.** Two hand-quoted shell batteries in this package produced false results before the corpus moved to python. A `\b` inside a `python3 -c` string is a BACKSPACE, not a word boundary, so a fast-path pattern could never match and a road-at-the-end case reported "no road" — a design failure that was a test bug. And `'` escapes lost their spaces before `jq` ever saw them, so two prose cases appeared to refuse when the payload they tested was not the payload intended. Both cost time and both nearly produced a wrong fix.

**A case list that every build passes is decoration.** The original 39-case battery passed on the build with 18 wrong refusals and 6 bypasses, and on every build that fixed them, and never distinguished any of them. What caught those was a probe corpus with expected verdicts, a verdict diff between builds, and a test that fails on time. If you add to this directory, add the kind of test that can go red.
