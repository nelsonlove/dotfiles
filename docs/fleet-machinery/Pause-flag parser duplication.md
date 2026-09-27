# The pause-flag parser is duplicated in two files, by hand, on purpose

What a shared file would have to take as parameters, and what breaks if the two copies ever drift. Written for the extraction package. Measured in the worktree `feat/accept-verb-guard-v2`; every line number and every comparison below was run, not remembered.

## What is duplicated

Two files carry the same parser, each between explicit markers:

| File | Block | Marker text |
|---|---|---|
| `claude/hooks/pause-guard.sh` | lines 66–136 | `---- flag parser (keep identical to tickle/scripts/_lib/pause-gate.sh) ----` … `---- end flag parser ----` |
| `tickle/scripts/_lib/pause-gate.sh` | lines 87–157 | `---- flag parser (keep identical to claude/hooks/pause-guard.sh) ----` … `---- end flag parser ----` |

Inside each block: `sq="'"`, three initialised globals, `fm_value()` (8 lines) and `read_pause_flag()` (51 lines). 69 lines of body each, in files of 430 and 180 lines — so it is 16% of the hook and 38% of the gate.

Both headers also announce it in prose. `pause-gate.sh:41`: "The flag parser below is duplicated verbatim in claude/hooks/pause-guard.sh, the session-side half of the same rule. The two install through different paths (TICKLE_CONFIG_HOME here, the ~/.claude/hooks symlink there) and must never disagree about what 'paused' means: change both together." `pause-guard.sh:33` says the same in the other direction.

## It has already drifted

`read_pause_flag` and `fm_value` are byte-identical between the two files — I extracted each and compared with `cmp`. But the 69-line blocks as a whole are **not**, and both headers claim "duplicated verbatim":

```diff
 # CR is stripped everywhere: a CRLF note otherwise never matches the `---`
-# fence, which used to leave the frontmatter empty and the gate wide open.
+# fence, which used to leave the frontmatter empty and the guard wide open.
```

One word, in a comment, and each file names itself correctly — so this particular drift is harmless and probably deliberate. That is exactly why it is worth showing. A hand-maintained "keep identical" block has already stopped being identical, in the most benign way available, and nothing noticed. The next divergence will arrive the same way and will not necessarily be benign.

## The stated reason for the duplication does not hold

The headers give the reason as different install paths. I checked both, and both resolve into the same checkout:

- `TICKLE_CONFIG_HOME=/Users/nelson/repos/system/dotfiles/tickle`, so a job's `@config/scripts/_lib/pause-gate.sh` is the repo's own file.
- `~/.claude/hooks` is a directory symlink to `claude/hooks` in the repo, so the hook is the repo's own file too.

And a hook can resolve the repo root, which is the thing I expected to be the blocker. The `bin` scripts already do it in two steps, and `wake-session.sh:94` states the intent — "the repo root, resolved through the `~/.claude/bin` symlink, so the tickle gate beside us is found":

```sh
script_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || script_dir=""
REPO_ROOT=$(cd "$script_dir/../.." 2>/dev/null && pwd -P) || REPO_ROOT=""
```

The first `pwd -P` resolves the symlink before `..` is applied, so the second `cd` walks up the real path. I ran those two lines from both directories rather than trust the reading: from `~/.claude/bin` and from `~/.claude/hooks`, both give `/Users/nelson/repos/system/dotfiles` and both reach the pause gate. So each half can source a shared file by relative path today, and the duplication is a choice.

## What the shared file must take, and what it must NOT take

The parser's contract is already clean, which is the good news — the two callers diverge **after** it, never inside it.

**Input, one parameter:** `PAUSE_NOTE`, the path to the flag note. Both callers set it the same way and for the same reason, and the shape matters:

```sh
if [ -z "${PAUSE_NOTE:-}" ]; then
  PAUSE_NOTE="$HOME/obsidian/00-09 System/00 System management/00.08 Operator's console/Pause.md"
fi
```

Both files carry a comment saying this is deliberately an if-guard rather than `PAUSE_NOTE="${PAUSE_NOTE:-…}"`. Keep that. The shared file should **require** `PAUSE_NOTE` to be set by the caller and not default it, or it should default it in exactly this shape — not a one-liner that differs in how an empty-but-set value behaves. An empty `PAUSE_NOTE` that silently becomes the real path, or a real path that silently becomes empty, is the whole failure mode in one variable.

**Internal dependency:** `fm_value` reads two globals, `$flag_block` and `$sq`. Both must be set by the shared file, not by the caller. `sq="'"` exists because a single quote cannot be written inside the `sed -E` expressions any other way; it is not decoration.

**Output, three globals:** `flag_state` (one of `absent`, `paused`, `clear`, `bad`), `flag_reason` (prose, set only when `flag_state=bad`), and `flag_block` (the raw frontmatter, kept because both callers read `paused-by`, `paused-since` and `paused-why` out of it afterwards with `fm_value` — `pause-guard.sh:417–419`, `pause-gate.sh:171–173`).

**What must stay out of the shared file:** every exit path, because the two callers' exit contracts are incompatible.

| `flag_state` | `pause-gate.sh` (a tickle script trigger) | `pause-guard.sh` (a PreToolUse hook) |
|---|---|---|
| `absent` / `clear` | exit 0 — run the job | exit 0 — allow the call |
| `paused` | sets `pause_gate_skip=1`, exit **1** — skip, recorded as "skipped" | classify the call first; block only if it is write-shaped, so reads continue |
| `bad` | exit **2** — "check failed", job does not run | does **not** exit; falls through to the same classify step, so a broken flag never blocks a read |

Those are different policies for the same state, and both are correct for their side. `pause-gate.sh`'s exit 1 is reachable only from the deliberate paused path, and its EXIT trap rewrites every other non-zero to 2 — because `set -u` on an unbound variable exits 1, and a stray 1 would be an invisible permanent skip indistinguishable from a healthy quiet period. Its header names the precedent: that class of silent failure hid a 29-hour `obsidian-backup` outage. `pause-guard.sh` instead follows 01.65 rule 10, that reads continue during a pause, and it says why in its own words — blocking reads "would wedge the session out of reading or fixing the note that is the whole problem."

So the extraction boundary is exactly where the markers already are. Move the 69 lines; leave `read_pause_flag`'s three call sites' worth of policy behind.

## What breaks if the two drift

Ranked by how badly, because they are not equally bad.

**1. The parser gets stricter on one side only, and the fleet half-stops.** If `pause-guard.sh` starts returning `bad` for a note that `pause-gate.sh` still reads as `clear`, then sessions are blocked from write-shaped calls while every scheduled job keeps running. Nobody sees a pause; they see agents that cannot write and cron that works. The reverse is worse: `pause-gate.sh` returning `clear` for a note that says `paused: true` means Nelson has said stop and the jobs carry on, which is the precise failure the gate exists to prevent.

**2. A new `paused` value is accepted on one side.** Today both accept `true|yes` as paused and `false|no` as clear, and treat anything else as `bad`. Add `on`/`off` to one copy and the same note means paused to one half and unreadable to the other — and "unreadable" has opposite consequences on the two sides (job refuses to run; session keeps reading). The vocabulary of that one key is a contract between the two files, and it currently lives in two `case` statements.

**3. The CR stripping is removed or weakened on one side.** The comment in the block records that a CRLF note "used to leave the frontmatter empty and the guard wide open". Both copies strip CR in three places — the first-line check, the block extraction, and the trailing-space trims. A copy that loses one of them reads a CRLF note as having no frontmatter, which is `bad`, which diverges per rule 1 above. This is a real regression that already happened once.

**4. The fence rule is loosened.** `read_pause_flag` requires the opening `---` to be the **first line**, and its comment says why: matching any `---` anywhere would read a thematic break in the body as the start of frontmatter. A copy that relaxes this reads a different block on a note with a horizontal rule in it.

**5. `fm_value`'s quote stripping diverges.** Only cosmetic — it feeds the `paused-by` / `paused-since` / `paused-why` fields in the log lines, not the decision. Worth naming so nobody ranks it with the others.

The common thread: **a drift does not announce itself.** Every one of these five leaves both scripts exiting 0 in the ordinary case, so nothing fails until the day Nelson actually pauses the fleet — the one day the mechanism has to work.

## Recommendation

Extract the 69 lines to `claude/lib/pause-flag.sh` (or a neutral top-level `lib/`, since one consumer lives under `tickle/` and one under `claude/` — a `claude/`-named path makes the tickle gate look like a guest in someone else's directory). Have it require `PAUSE_NOTE`, define `sq` and `fm_value`, and set the three output globals. Source it from both. Delete both "keep identical" comments, because they are the defect being fixed, and replace them with one line in each caller naming the shared file.

Do it in its own commit, with nothing else in it. The diff is provably behaviour-free on the code — `read_pause_flag` and `fm_value` are already byte-identical, so a reviewer can confirm the move by `cmp` rather than by reading — and that property is worth not spending on a commit that also does something else. Ship it before the rank-line extraction: the rank line has stayed in step on its own (five of six functions byte-identical, the sixth differing only in a comment), while this block has already drifted and carries the higher cost when it does.

Written 2026-09-27T05:27 EDT

---

# Correction and proof, after the ruling

The ruling on package 4 attaches a condition: a single sourced file must be **proven** to resolve from both install roads before anything is unified, and if it does not, the copies stay and the package adds a generated-from marker plus a drift test. I hardened the half-proof above into a script, `prove-shared-lib-path.sh` in this directory, and it corrected me.

## What I had wrong

Above, I showed that the two-step `script_dir` / `REPO_ROOT` idiom resolves to `/Users/nelson/repos/system/dotfiles` from both `~/.claude/bin` and `~/.claude/hooks`, and concluded that each half can source a shared file by relative path. The conclusion holds. The implied detail — that both halves can use the **same** expression — does not.

The bin scripts and the hook are two levels below the repo root. **The tickle gate is three.**

```
the hook is at  <repo>/claude/hooks/           so $script_dir/../..    is <repo>          — correct
the gate is at  <repo>/tickle/scripts/_lib/    so $script_dir/../..    is <repo>/tickle   — NOT the root
```

My first version of the proof script asked whether the two roads compute the same root from `../..`, got two different answers, and printed NOT PROVEN — keep both copies. That verdict was wrong, and it was wrong because the question was wrong. The roads do not need to agree on an expression; they need to name one identical absolute file. Asking it properly, with each road using its own depth:

```
ROAD 1  hook  script_dir /Users/nelson/repos/system/dotfiles/claude/hooks        up 2 → /Users/nelson/repos/system/dotfiles
ROAD 2  gate  script_dir /Users/nelson/repos/system/dotfiles/tickle/scripts/_lib up 3 → /Users/nelson/repos/system/dotfiles
both resolve claude/lib/pause-flag.sh to /Users/nelson/repos/system/dotfiles/claude/lib/pause-flag.sh
PROVEN — exit 0
```

So the ruling's condition is met and package 4 may unify. `TICKLE_CONFIG_HOME` is `/Users/nelson/repos/system/dotfiles/tickle`, which is why road 2 lands inside the same checkout at all.

## The gotcha to carry into the package

**The two callers need different depths for the same file: the hook two, the gate three.** A line copied from one into the other resolves to a path that does not exist, and the failure is quiet in the worst place — a `source` of a missing file under `set -u` exits non-zero, and `pause-gate.sh`'s EXIT trap rewrites every unexpected non-zero to 2, which tickle records as "check failed" and the job does not run. So a copy-paste error in the shared-file path stops scheduled jobs while looking like a pause-flag problem. That is precisely the silent-failure class its own header warns about, citing the 29-hour `obsidian-backup` outage.

Two ways to avoid it, and I would take the second:

1. Each caller computes its own depth, with a comment saying how many levels and why. Correct, and one edit away from being wrong again.
2. Neither caller counts levels. Have each walk **up** from `$script_dir` until it finds a marker that identifies the repo root — `.git` is present in the main checkout, and in a worktree `.git` is a file rather than a directory but still present, so `[ -e "$d/.git" ]` holds for both. Then the same three lines work verbatim in both files, at any depth, and survive either script being moved. That also removes the last reason the parser was ever duplicated: a shared file whose location is found rather than counted to.

Worth noting for whoever writes it: from this worktree the marker walk stops at the worktree root, not the main checkout, because `.claude/worktrees/<name>/.git` exists there. For the pause parser that is the right answer — a hook running from a worktree should read that worktree's copy — but it should be stated rather than discovered, since it is the same question the extraction package will face for the rank line.

## Re-running the proof

```
TICKLE_CONFIG_HOME=/Users/nelson/repos/system/dotfiles/tickle bash /tmp/v2/soak-workspace/prove-shared-lib-path.sh
```

Optionally takes the candidate path as `$1` (default `claude/lib/pause-flag.sh`). It exits 0 for proven, 1 for not proven, and **2 for "could not be measured here"** — deliberately a third state, because an environment missing `TICKLE_CONFIG_HOME` or the installed hook tells you nothing about the design, and a script that returned "not proven" for that would be lying.

Correction appended 2026-09-27T05:40 EDT

---

# What the `.git` walk must do when there is no `.git`

Asked for by the ruling, because the walk is the part going into package 4's code. The answer is that it must **refuse, not guess.**

## The rule

Walk up from `$script_dir` while a parent remains. Take the first directory that contains `.git`, whether `.git` is a directory (a normal checkout) or a file (a worktree or a submodule) — so the test is `[ -e "$d/.git" ]`, never `[ -d … ]`. If the walk reaches the filesystem root without finding one, **die with a message naming the directory the walk started from and the fact that no `.git` was found.** Do not fall back to a fixed depth.

```sh
find_repo_root() {  # $1 = a directory inside the repo; prints the root, or dies
  local d; d=$(cd "$1" 2>/dev/null && pwd -P) || return 1
  while [ "$d" != "/" ]; do
    [ -e "$d/.git" ] && { printf '%s' "$d"; return 0; }
    d=$(dirname "$d")
  done
  return 1
}
```

## Why a fallback is worse than a failure

This is the whole reason the question matters. The two callers need **different depths** — the hook is two levels below the repo root, the gate is three — so there is no single count to fall back to. A wrong count resolves to a path that does not exist, and a `source` of a missing file fails. On the gate that failure is silent in the worst possible way: a non-zero exit under `set -u`, rewritten to 2 by the EXIT trap, recorded by tickle as "check failed", and the job does not run. Nothing says "the shared library moved"; it looks like a pause-flag problem. That is exactly the class of silent failure `pause-gate.sh`'s own header warns about when it cites the 29-hour `obsidian-backup` outage.

A loud failure naming the searched path is diagnosable in seconds. A guessed depth is diagnosable after someone notices a job has not run for a day.

## When `.git` is genuinely absent

Three cases, and none of them wants a guess:

- **A tarball or zip export of the repo.** No `.git` anywhere. Nothing in this repo is meant to run from an export — the hook is reached through a symlink into a checkout and the gate through `TICKLE_CONFIG_HOME` pointing at one — so an export that tries to run them is already misconfigured, and saying so is the correct behaviour.
- **A vendored copy**, one or both files lifted into another project. The shared file is not there either, so failing at path resolution and failing at `source` are the same outcome; the difference is only whether the message is useful.
- **A single file moved out of the tree** for testing. This is the one a person actually does, and it is precisely when a clear "no `.git` found above `<dir>`" saves time.

If a future caller genuinely needs to run outside a checkout, the escape hatch is an explicit environment variable — the shape `notebook-name-sync.sh:25` already uses, `${SHARED_LIB_DIR:-<the walk>}` — checked *before* the walk, so an operator can state the answer rather than have one inferred. That keeps "guessing" out of the code while leaving a documented way to override it.

## The worktree case, which will confuse someone

From a git worktree the walk stops at the **worktree** root, not the main checkout, because `.claude/worktrees/<name>/.git` exists there as a file. So a hook running from a worktree sources that worktree's copy of the shared file.

For the pause parser that is the right answer: a hook running out of a worktree should read the parser that worktree holds, or a change under test would be silently bypassed. But it is not obvious, and it is the same question the rank-line extraction will face, so it belongs in a comment beside the walk rather than in anyone's memory. Verified here: this soak ran from `/Users/nelson/repos/system/dotfiles/.claude/worktrees/feat+accept-verb-guard-v2`, and `TICKLE_CONFIG_HOME` points at the **main** checkout's `tickle/` — so on this machine, right now, the hook road and the gate road would resolve to different checkouts if the hook were invoked from inside the worktree. `prove-shared-lib-path.sh` reports PROVEN because it measures the installed roads (`~/.claude/hooks`, which points at the main checkout), which is the configuration that actually runs. Both facts are true and they are not in conflict — but anyone testing the package from a worktree needs to know which one they are measuring.

Git-walk section 2026-09-27T05:51 EDT
