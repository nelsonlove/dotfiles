# How a suite in here earns its greens

Nothing in `claude/tests/` installs. `install/manifest.yaml` maps `claude/hooks` and `claude/bin` into `~/.claude/`; this directory is deliberately not in it, because these are tests, not machinery.

Each suite has its own README or its own header. What follows binds all of them, and both rules are here because a suite in this directory broke them and reported success while doing it. They are written as the evidence rather than as advice, so the next writer can see what it cost.

## 1. Prove the suite can FAIL before its greens mean anything

**Watch every new assertion fail once, on purpose.** Flip the expected value, run it, see the red, flip it back. It costs one line and one second per assertion.

Why, measured 2026-09-27 in `fleet-ranks/status-dual-read.sh`: that suite used `pass` and `fail` helpers **which it never defined** — the sibling suites define them, it did not. Under `set -u` a missing command does not stop a script, so each call was a silent `command not found` on stderr and the run printed **"0 failed"**. Two assertions were affected and one of them was the headline claim of the package it shipped in: that an unrelated record must not poison the renamer. It could not fail in either direction. One deliberate flip would have shown it in a second.

Two habits follow, and they are cheap:

* **One deliberately broken assertion per suite, run once**, before you believe any of it.
* **A count you can check.** The suite prints `N checks` — know what N should be from reading the file, and notice when it changes for no reason. When the same file's count fell from 87 to 61 the same evening, that was a broken line swallowing whole sections, and the count was the only thing that said so.

### 1a. And run the mutation from a file, not from memory

`fleet-ranks/mutants.sh` breaks each guard in `fleet-ranks/session-roster.sh` on a copy of the tree and requires the suite to notice. Run it when you add a guard, and **add a mutant in the same commit** — a guard with no mutant is a guard nobody has watched fail.

Why a file rather than a habit, measured across eight review rounds on #71: three assertions in that suite were green for a reason that had nothing to do with the code they named. One fixture had its trigger line indented, so the whole-file grep it existed to catch never matched it. One had a comment carrying no apostrophe, so a greedy match and a first-match match gave the same answer. One was named for indented keys and contained none. Each was counted as coverage, and each was found by running a mutation by hand — which happens only when somebody remembers, and twice it happened only because a reviewer asked.

Three things that runner must do, each learned by getting it wrong in the first version:

* **Run an unmutated baseline first, and report nothing if it is red.** The first version copied `bin`, `lib` and `tests` and not `hooks`, so the unmutated copy was already failing thirty checks and every mutant was reported as caught. A mutation runner with a broken baseline is a machine for producing false confidence — the same defect it exists to catch, one level up.
* **Say when a mutant matched nothing.** An anchor moves whenever the code is edited, and a mutant that silently changes nothing reads exactly like a caught one. Six of the first twenty-one matched nothing, through doubled escaping, and said so.
* **Kill a redundant pair together.** Where two layers each prevent the same bad outcome, removing either alone changes no output, and a single-layer mutant reports "not caught" for a guard that is working perfectly. That is a property of the design, not a hole: `roster_state_for_id`'s two early returns and the sweeper's reason chain are exactly this, and the mutant removes both, whereupon the fork fixture turns into `WOULD REMOVE`.

## 2. A suite that only meets its own fixtures is a test of the fixtures

**Run against the real population, read-only, under the shell options the caller really uses.**

Why, the same day, the same file: it passed **48 checks** over a library that could not survive its own notebook. Two fatal defects were invisible to every fixture — a value the vault writes on hundreds of notes read as something it is not, and a `grep` that exits 1 on a missing key aborting its `set -euo pipefail` caller mid-loop. One read-only pass over the 517 live entries killed both in the first second, and that case is now the suite's **first** case.

The corollaries that make it honest:

* **Assert that the population is real.** `grep -c` over nothing is `0`, which looks exactly like a clean population. If the section can read zero entries and still pass, it proves nothing.
* **A skip is counted, never printed and forgotten.** A machine without the vault must not run the suite green while missing the only section that meets reality.
* **Never assert a count over live data.** It changes while you measure — the census above moved three times in one evening because sessions were writing. Assert the properties that must hold whatever the fleet is doing; print the counts beside them to be read.

## 3. Two copies of one rule are acceptable only with a loop that compares them

Some rules exist twice for a real reason — `claude/lib/session-status.sh` and the one-pass `awk` index inside `claude/bin/wake-session.sh` are the same rule, because a shell function per file would turn one survey into hundreds of processes. That is allowed **only** while a case runs every fixture through both roads and compares them word for word.

It is not a formality. That loop caught two divergences in five minutes: one introduced by a fix, and the second created while fixing the first. Both were shapes no well-formed fixture had — a quoted value carrying a comment, and a malformed value beside a valid one. So put the **cross-products** in, not just each feature alone, and if the comparison is ever deleted the duplication stops being acceptable with it.

## 4. The rest, in one line each, each learned the hard way

* **`grep -c` prints `0` and exits 1** when it finds nothing, so `c=$(grep -c x f || echo 0)` yields two lines. Use `|| true`.
* **A command substitution in an assertion's label** runs before `$?` expands and clobbers the code you are asserting. Capture the status on its own line.
* **A function called through `$( )` runs in a subshell**, so anything it sets never comes back. Four separate cases of this in one evening: set globals and call it plainly, or write the output to a file.
* **An apostrophe inside a single-quoted `awk` program** ends the string and the shell parses awk source as commands. `fleet-ranks/status-dual-read.sh` now fails on one, because it happened twice in an evening, both times inside a careful comment.
* **An exclusion list is where a filter quietly becomes a blindfold.** Every term must name the KIND of line it removes, never a character that also appears in the lines you are hunting.
* **A fixture is never a live fleet id, and never named as a rank above a lieutenant.** A throwaway is named for what it TESTS and dispatched `--agent lieutenant`; a wake or promote case passes `--dry-run` and `--log` to a temp file.
* **Write the test's own bug into the test** when you find one, as a comment saying what it hid. Every item on this page is here because someone did that instead of quietly fixing it.
