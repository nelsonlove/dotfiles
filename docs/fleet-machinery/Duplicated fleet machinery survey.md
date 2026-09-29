# Duplicated fleet machinery in `claude/bin/*.sh` and `claude/hooks/*.sh`

Surveyed in the worktree `feat/accept-verb-guard-v2` on the stamp recorded at the end of this note. Nine scripts were read: `claude/bin/promote-session.sh`, `claude/bin/rename-notebook.sh`, `claude/bin/wake-session.sh`, and the six hooks `accept-verb-guard.sh`, `block-edit-shared-files.sh`, `notebook-name-sync.sh`, `pause-guard.sh`, `protect-new-repo.sh`, `shell-move-safety.sh`.

Only two files carry the rank line: `wake-session.sh` and `promote-session.sh`. Nothing in `claude/hooks/` reads a rank at all, so a shared rank file has exactly two consumers today.

## The named functions

| Name | Defined in | Lines | Bodies |
|---|---|---|---|
| `rank_of_name` | `claude/bin/wake-session.sh` | 161–171 | differ, comment only |
| | `claude/bin/promote-session.sh` | 132–142 | |
| `word_of_rank` | `claude/bin/wake-session.sh` | 172–174 | byte-identical |
| | `claude/bin/promote-session.sh` | 151–153 | |
| `bare_code_of_rank` | `claude/bin/promote-session.sh` | 143–145 | single definition; no duplicate |
| `ship_is_known` | `claude/bin/wake-session.sh` | 187–189 | byte-identical |
| | `claude/bin/promote-session.sh` | 162–164 | |
| `code_of_rank` | `claude/bin/promote-session.sh` | 148–150 | single definition; no duplicate |
| `KNOWN_SHIPS` | `claude/bin/wake-session.sh` | 183 | byte-identical (`KNOWN_SHIPS="CC OB HS FL"`) |
| | `claude/bin/promote-session.sh` | 157 | |
| `ship_of_name` | `claude/bin/wake-session.sh` | 184–186 | byte-identical |
| | `claude/bin/promote-session.sh` | 159–161 | |

## The one real difference

`rank_of_name` differs in its comment, not in a single line of code. The `case` arms are byte-identical in both files. The comment:

```diff
 rank_of_name() {
-  # Both forms of the code: the bare `[L0]`, which running sessions keep until Nelson renames them
-  # in the view, and the ship-coded `[L0-CC]` ruled on 2026-09-26.
+  # Both forms of the code: the bare `[L0]` and the ship-suffixed `[L0-CC]` / `[L0-OB]` the rank
+  # files took on 2026-09-26, where CC is the Claude Code ship and OB the obsidian ship.
   case "$1" in
     "[C0]"*|"[C0-"*) echo 0 ;;
     "[C1]"*|"[C1-"*) echo 1 ;;
```

`promote-session.sh` has the better sentence, because it says what the bare form *means* now (a name Nelson has not yet renamed in the view) rather than only what date it changed. Take that one into the shared file.

## The rest of the duplication, found on the way

These were not on the list but appear in more than one file, and the extraction package should decide about each of them rather than meet them by surprise.

**`rank_of_agent`** — `wake-session.sh` 152–160 and `promote-session.sh` 123–131. **Byte-identical.** Maps an agent-definition name (`captain`, `lieutenant-commander-repository`, …) to the same 0–3 scale. It belongs in the shared file with the other five; it was simply left off the brief's list.

**`FLOATING_SHIP="FL"`** — `promote-session.sh` 158 only. Single definition, but note that it sits directly under `KNOWN_SHIPS` and `FL` is also listed *inside* `KNOWN_SHIPS`. If `KNOWN_SHIPS` moves to a shared file, `FLOATING_SHIP` should move with it or the two will drift apart. `promote-session.sh` leans on it eight times — lines 179, 225, 226, 228, 230, 231, 238, 239 — for the whole floating-session policy: a promoter may move a session onto the floating marker but onto no other ship (179), a rank acts only on its own ship unless the target floats (225–226), and marking a session floating must be deliberate rather than a side effect of a rename (228–231).

**`die`** — three definitions, all the same shape, all with a different program name baked in:

```
claude/bin/rename-notebook.sh:78:die() { printf 'rename-notebook: %s\n' "$*" >&2; exit 2; }
claude/bin/wake-session.sh:107:die() { printf 'wake-session: %s\n' "$*" >&2; exit 2; }
claude/bin/promote-session.sh:84:die() { printf 'promote-session: %s\n' "$*" >&2; exit 2; }
```

One shared `die` needs a `PROG` variable each script sets before sourcing. Cheap, but it is a behaviour change in the error text if anyone gets `PROG` wrong, so it deserves its own commit rather than riding along with the rank line.

**`on_exit`** — four definitions, **all four genuinely different**, and none of them should be shared. `accept-verb-guard.sh` 87–92 removes a scratch file and normalises the exit code to 0 or 2. `pause-guard.sh` 42–46 does the same normalisation without the scratch file. `wake-session.sh` 111–116 warns that a woken session was not logged. `promote-session.sh` 88–93 warns that a stopped session was not resumed. Same name, four different jobs — a trap for anyone extracting by name.

**`fm_value`** — two definitions with the **same name and incompatible signatures**, which is the worst case in this survey:

- `claude/bin/rename-notebook.sh` 152–165 takes **two** arguments (`$1` = file, `$2` = key) and reads frontmatter out of that file with `awk`, stopping at the closing `---`.
- `claude/hooks/pause-guard.sh` 76–84 takes **one** argument (`$1` = key) and reads it out of the global `$flag_block` with `grep`/`sed`. It also depends on a second global, `$sq`.

A shared `fm_value` cannot be both. Whoever writes the extraction package must pick one contract and convert the other call site, or name them apart (`fm_value_of_file` and `fm_value_of_block`). Do not let the two meet in one file under one name.

**The pause-gate call** — the same six-line shape in all three `bin` scripts: `wake-session.sh` 340–349 (wrapped as `read_pause_gate`), `promote-session.sh` 246–251, `rename-notebook.sh` 106–119 (inline). All three set `PAUSE_NOTE` when `$pause_note` is given and `env -u PAUSE_NOTE` when it is not, and all three pass their own program name as the gate's argument. The two differences are worth keeping: `wake-session.sh` and `promote-session.sh` treat a missing gate as fatal (`die "refused: the pause gate is not at …"`), while `rename-notebook.sh` records `pause_state="the pause gate is not at $PAUSE_GATE"` and carries on. That is a deliberate policy difference, not drift — a rename is not a wake. A shared helper must take "fatal or not" as a parameter.

**Path constants** — duplicated across the three `bin` scripts and one hook:

- `FLEET_LOG` — identical in all three `bin` scripts (`promote-session.sh` 70, `rename-notebook.sh` 66, `wake-session.sh` 93).
- `PAUSE_GATE` — identical in all three (`promote-session.sh` 74, `rename-notebook.sh` 74, `wake-session.sh` 97), each derived the same way from `REPO_ROOT`.
- `REPO_ROOT` — identical `cd "$script_dir/../.." && pwd -P` in all three (`promote-session.sh` 73, `rename-notebook.sh` 73, `wake-session.sh` 96).
- `NOTEBOOK_DIR` — `rename-notebook.sh` 69 and `wake-session.sh` 99 hardcode it; `claude/hooks/notebook-name-sync.sh` 25 wraps the same default in an override (`${NOTEBOOK_NAME_SYNC_DIR:-…}`). The hook's shape is the better one — it is the only one that can be pointed at a fixture directory in a test.
- `JOBS_DIR` — `promote-session.sh` 76 and `wake-session.sh` 98, identical.
- `SESSIONS_DIR` — `rename-notebook.sh` 70 and `notebook-name-sync.sh` 27, identical.
- `REPORTS_TO_KEY="reports-to"` — `promote-session.sh` 80 and `wake-session.sh` 103, identical.

## Recommendation for the extraction package

Three files, not one, because the three groups have different consumer sets and different risk:

1. **`claude/lib/fleet-ranks.sh`** — `rank_of_agent`, `rank_of_name`, `word_of_rank`, `bare_code_of_rank`, `code_of_rank`, `KNOWN_SHIPS`, `FLOATING_SHIP`, `ship_of_name`, `ship_is_known`. Two consumers, all bodies already byte-identical except one comment. This is the safe one and should ship first, alone.
2. **`claude/lib/fleet-paths.sh`** — the path constants, each written in the `${OVERRIDE:-default}` shape `notebook-name-sync.sh` already uses, so the scripts become testable against a fixture vault.
3. **Leave `die`, `on_exit`, `fm_value` and the pause-gate call alone for now.** `on_exit` must not be shared at all. `fm_value` needs a naming decision first. `die` and the pause-gate call are each a one-commit job with a visible behaviour surface, and neither belongs in the same change as the rank line.

Surveyed 2026-09-27T04:58 EDT

---

# Second pass

Done on dotfiles' request, because the first pass was thin in one place. It was thin: I searched only `claude/bin/` and `claude/hooks/` as briefed, and the repo has a **third** directory of shell machinery that changes the recommendation.

## The biggest duplication in the repo is not the rank line

`tickle/scripts/_lib/` already exists, and it is the repo's own precedent for a shared shell library: `gated.sh`, `git-autocommit.sh`, `on-host.sh`, `pause-gate.sh`. Counting it in, the duplicate tally across all three directories is:

| Name | Copies | Files |
|---|---|---|
| `on_exit` | 5 | `accept-verb-guard.sh` 90, `pause-guard.sh` 42, `pause-gate.sh` 49, `wake-session.sh` 111, `promote-session.sh` 88 |
| `fm_value` | 3 | `pause-guard.sh` 76–83, `pause-gate.sh` 97–104, `rename-notebook.sh` 152–165 |
| `die` | 3 | `wake-session.sh` 107, `promote-session.sh` 84, `rename-notebook.sh` 78 |
| `read_pause_flag` | 2 | `pause-guard.sh` 85–135, `pause-gate.sh` 106–156 |
| the six rank helpers | 2 each | `wake-session.sh`, `promote-session.sh` |

**`read_pause_flag` is 51 lines and byte-identical between `claude/hooks/pause-guard.sh` and `tickle/scripts/_lib/pause-gate.sh`.** `fm_value` is 8 lines and byte-identical between the same two. That is 59 lines of exact duplicate — more than the whole rank line, which is six small functions and two constants, about 40 lines including comments.

And it is **deliberate, hand-maintained duplication.** `claude/hooks/pause-guard.sh:66` says so in a comment:

```
# ---- flag parser (keep identical to tickle/scripts/_lib/pause-gate.sh) ----
```

A comment asking a human to keep two 59-line blocks byte-identical is the strongest candidate for extraction in the repository. It is also the highest-stakes one: both copies parse the fleet pause flag, both are documented as failing closed, and a drift between them means a hook and a tickle gate disagree about whether the fleet is paused. The rank line, by contrast, has already stayed in step on its own — five of six functions are byte-identical and the sixth differs only in a comment.

`fm_value`'s three copies also resolve the puzzle from the first pass. It is not two incompatible implementations; it is **two copies of one implementation plus one different one.** The block-reading form (one argument, reads `$flag_block`, needs the global `$sq`) is the duplicated pair in `pause-guard.sh` and `pause-gate.sh`. The file-reading form (two arguments, `awk` over a file's frontmatter) is `rename-notebook.sh`'s alone. So the naming decision is easier than I first said: extract the duplicated pair under the name they already share, and rename `rename-notebook.sh`'s to `fm_value_of_file`, which touches one file and no behaviour.

## A hook can source the shared file — there is no technical reason for the copy

I expected the duplication to exist because a hook cannot find the repo root: hooks run as `/Users/nelson/.claude/hooks/<name>.sh`, and `~/.claude/hooks` is a **directory symlink** to `claude/hooks` in the repo (as `~/.claude/bin` is to `claude/bin`). A naive `cd "$(dirname "$0")/../.."` would resolve `..` logically against the symlinked path and land on `/Users/nelson`, not on the repo.

The `bin` scripts already avoid that, in two steps, and `wake-session.sh:94` states the intent outright — "the repo root, resolved through the `~/.claude/bin` symlink, so the tickle gate beside us is found":

```sh
script_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || script_dir=""
REPO_ROOT=$(cd "$script_dir/../.." 2>/dev/null && pwd -P) || REPO_ROOT=""
```

The first `pwd -P` resolves the symlink before `..` is ever applied, so the second `cd` walks up the real path. I checked it both ways rather than trust the reading:

- from `~/.claude/bin` → `REPO_ROOT=/Users/nelson/repos/system/dotfiles`, pause gate present.
- from `~/.claude/hooks` → `REPO_ROOT=/Users/nelson/repos/system/dotfiles`, pause gate reachable.

So the same two lines work from a hook. The duplicated parser is a choice, not a constraint, and whoever wrote the "keep identical" comment can replace it with a `source`.

One caveat worth carrying into the package: a **worktree** resolves to its own root, not the main checkout's. From this worktree, `$script_dir/../..` gives the worktree path, and `tickle/scripts/_lib/pause-gate.sh` exists there too, so it works — but it means a hook sources the *worktree's* copy of a shared library when it runs from a worktree checkout. For a pause parser that is arguably correct, and for the rank line it is certainly harmless. It should be stated rather than discovered.

## Revised recommendation

The ordering from the first pass was wrong. Corrected:

1. **`claude/lib/pause-flag.sh`** — `read_pause_flag` and the block-reading `fm_value`, sourced by `claude/hooks/pause-guard.sh` and `tickle/scripts/_lib/pause-gate.sh`. Biggest duplicate, highest stakes, already byte-identical so the diff is provably behaviour-free, and it retires a hand-maintained "keep identical" comment. Ship this first, alone. Rename `rename-notebook.sh`'s `fm_value` to `fm_value_of_file` in the same commit, since that is what makes the shared name unambiguous.
2. **`claude/lib/fleet-ranks.sh`** — `rank_of_agent`, `rank_of_name`, `word_of_rank`, `bare_code_of_rank`, `code_of_rank`, `KNOWN_SHIPS`, `FLOATING_SHIP`, `ship_of_name`, `ship_is_known`. Two consumers, safe, take `promote-session.sh`'s comment for `rank_of_name`.
3. **`claude/lib/fleet-paths.sh`** — the path constants, each in the `${OVERRIDE:-default}` shape `notebook-name-sync.sh:25` already uses, so the scripts become testable against a fixture vault.
4. **Still leave `die`, `on_exit` and the pause-gate call alone.** `on_exit` now has five copies and all five do different jobs — it is the clearest "do not extract by name" case in the repo. `die` needs a `PROG` variable and has a visible error-text surface. The pause-gate call's three copies differ on purpose about whether a missing gate is fatal.

Everything in the first pass still stands; nothing in it was wrong except the ordering and the `fm_value` diagnosis.

Second pass 2026-09-27T05:12 EDT

---

# Re-verified at the close of the soak

Every claim in this file was re-run against the worktree at 2026-09-27T06:12 EDT, build `930f26d`, and all of it still holds. This matters because the guard itself was rewritten four times during the soak, so a reader may reasonably wonder whether these line numbers went with it.

They did not. `git status --short` is clean, and none of the five files this survey covers has been touched since before the soak began — `wake-session.sh`, `pause-guard.sh`, `pause-gate.sh` and `rename-notebook.sh` all date from 2026-09-26 21:44, and `promote-session.sh` from 04:50 on the 27th, which is five minutes before the first measurement here. Only `claude/hooks/accept-verb-guard.sh` changed, and this survey does not cite it.

Spot-checked rather than assumed:

- The two "keep identical" markers are still at `pause-guard.sh:66` and `pause-gate.sh:87`, each naming the other file.
- The two 69-line parser blocks still differ by exactly two lines, which are the same comment with one word changed — "the guard wide open" against "the gate wide open".
- `rank_of_agent`, `word_of_rank`, `ship_of_name` and `ship_is_known` are still byte-identical between `wake-session.sh` and `promote-session.sh`.

The one thing I would add with hindsight, from re-reading the guard at the close: **the accept verbs' four names are now hardcoded in three places inside `accept-verb-guard.sh`** — line 114 as prose in its dependency note, line 200 as `my @verbs = qw(...)`, and line 477 as the same four words in a nested `qw` inside the matcher. Two of those are live. They were two places at the start of the soak and are three now.

That is the same class of defect as everything else in this file, arriving in a new file while the survey was being written, and it is worth saying because the guard's own header warns about it only halfway. Line 114 correctly says a rename on the Obsidian side must come to this file. It does not say that arriving at this file means editing two `qw` lists 277 lines apart. A single list, referenced twice, costs one line.

**One correction to my own first draft of this paragraph, because it matters for how much the duplication is worth worrying about.** I wrote that nothing fails if only one list is updated — that every battery case would stay green either way. I tested it instead of leaving it asserted, and it is false: mutating the line-200 list alone makes the battery fail 10 of 39, and mutating the line-477 list alone makes it fail 2 of 39. Both are consulted on paths the battery exercises, so a rename *is* caught.

What is not caught is a **fifth** verb added to one list and not the other, since no battery case names a fifth verb. And what the battery cannot do either way is say *why*: a drift surfaces as two or ten unrelated-looking verdict failures rather than as "your two lists disagree". I wrote a standing check for exactly that, `verb-list-drift.sh` in this directory, and proved it fails on a simulated rename before trusting it — which is how I found out my own justification for it was wrong. It is kept with the correction visible in its own header comment. *(Retired 2026-09-29, #82 and #84: the guard lost its verb lists by design in 51b7bf0, so the check had nothing left to compare. The file is in git history, and its finding is kept in `claude/tests/accept-verb-guard/README.md`.)*
