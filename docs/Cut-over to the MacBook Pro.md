# Cut-over to the MacBook Pro — the macOS side

> [!warning] Draft, not reviewed
> This checklist is a draft. It stays a draft until the Pro is back on Tailscale and can be measured. On the day, Nelson walks it with a session, which checks each step against the Pro. It is not reviewed before then.

This is the checklist for moving the macOS side of the fleet from the MacBook Air (`Nelsons-MacBook-Air`) to the MacBook Pro (`Nelsons-MacBook-Pro`). It covers tickle, the job gates, the LaunchAgents, `install/install.sh` and the shell. The Claude Code steps (login, MCP servers, transcripts, resumes) belong to the claude code ship and are not here.

The source is the vault note `00-09 System/05 Apps & config/05.02 Tasks for 05 Apps & config/Proposal — move the fleet to the MacBook Pro.md`. Nelson ruled "All A" on it on 2026-09-29: the vault reaches the Pro through Obsidian Sync, `~/repos` moves by one rsync to the same path, `obsidian-backup` stays and is re-gated to the Pro while `vault-backup` is retired, and `task-curator` is disabled until it is reviewed. The cut-over itself waits for his Tailscale sign-in on the Pro and his go on the day.

## What PR #91 changes

- `tickle/jobs/obsidian-backup.yaml`: the host gate is `Nelsons-MacBook-Pro` (it was `Nelsons-MacBook-Air`).
- `tickle/jobs/vault-backup.yaml`: `status: disabled`, retired. Its script stays in `tickle/scripts/vault-backup/`.
- `tickle/jobs/task-curator.yaml`: `status: disabled` until it is reviewed.
- The checklist itself is in draft PR #93, apart from #91.

**When PR #91 merges is a step of the cut-over, not before it.** Each Mac's tickle reads its jobs straight from its own dotfiles checkout (`TICKLE_CONFIG_HOME` in `install/launchagents/dev.tickle.daemon.plist`). The Pro has been off the tailnet for weeks, so nothing about it is proven. The order below brings tickle up on the Pro and proves one `obsidian-backup` run there before the Air stops. The Air keeps its old, Air-gated jobs until the end, so the vault is never without a backup.

## Hard rules

1. Only one Mac runs the fleet at a time. With Sync on, both Macs hold the vault, and two writers race through Sync.
2. Only one Mac runs tickle, except for the short overlap from step 5 to step 6, which happens only while the fleet is paused. Nothing in steps 1 to 4 starts tickle on the Pro.
3. Nothing in this checklist is run by an agent. Every step is Nelson's, or a step he says go to on the day.

## Before the day

- [ ] Nelson signs the Pro in to Tailscale again (its key expired on 2026-08-17). Check: `tailscale status` on the Pro shows it online, with no "expired" note.
- [ ] Check the Pro's names. Both must be exact, because the tickle gates read them (`tickle/scripts/_lib/on-host.sh`): `scutil --get LocalHostName` prints `Nelsons-MacBook-Pro`, and the user is `nelson` with home `/Users/nelson`.
- [ ] Check what the Pro runs today, before anything moves: `launchctl print gui/$(id -u)/dev.tickle.daemon` (is tickle loaded there already?), `ls ~/Library/LaunchAgents/`, `ls -d ~/vault-backup.git ~/obsidian-backup.git ~/governor-history-backup.git`. If `~/obsidian-backup.git` or `~/governor-history-backup.git` is already there, move it aside (for example to `~/obsidian-backup.git.old-pro`) before step 2, so the Air's copy lands in an empty path and does not mix with old refs.
- [ ] If `~/Library/LaunchAgents/dev.tickle.daemon.plist` is present on the Pro, loaded or not, stop tickle there and move the plist away before the day, so only the Air runs tickle until step 5: `launchctl bootout "gui/$(id -u)" ~/Library/LaunchAgents/dev.tickle.daemon.plist; mv ~/Library/LaunchAgents/dev.tickle.daemon.plist ~/Library/LaunchAgents/dev.tickle.daemon.plist.old-pro`. (A plist left in place starts tickle at the next login or reboot, because it has `RunAtLoad`.) It runs the Pro's old checkout, where `pickle-resume` and `vault-backup` are active. Moving the plist away also matters in step 5: `install.sh` skips (and does not load) a plist that is byte-identical to the repo copy, and replaces and loads one that differs.
- [ ] Any other login agent on the Pro that starts a Claude session or writes the vault (for example `com.nelson.comms-agent`, if it is still there from when the Pro was the comms host) is a second writer while the fleet runs on the Air. For each plist in `~/Library/LaunchAgents/`, Nelson decides: stop it and move it aside the same way, or keep it. That includes `com.nelson.vault-mcp-remote` and `com.nelson.cloudflared-obsidian`: the obsidian.nelson.love proxy can write the vault for a remote client, and the pause does not stop it. Stopping `com.nelson.cloudflared-obsidian` from step 4 until the unpause closes it.
- [ ] The Pro may still hold checkouts that the Air does not have. The running proxy is one: check which path it starts from with `plutil -p ~/Library/LaunchAgents/com.nelson.vault-mcp-remote.plist`. So the rsync of `~/repos` in step 2 must NOT use `--delete` on `~/repos` as a whole. But a repo that exists on BOTH Macs must not be merged: its old refs and deleted files (old tickle job files, for example) survive a merge. List the repos the Pro already has (`find ~/repos -maxdepth 3 -name .git`), and move each one the Air also has aside (for example `~/repos/system/dotfiles` to `~/repos/system/dotfiles.old-pro`) before the copy.
- [ ] The copies in step 2 go from the Air to the Pro over the network. Turn on Remote Login on the Pro (System Settings, General, Sharing), and test from the Air: `ssh nelson@macbook-pro true` (the Pro's tailnet name). The rsync commands below use that target. (A disk is the other way.)
- [ ] Check for an old vault on the Pro: `ls -d ~/obsidian`. If one is there, stop, and do not connect Sync to it: Sync would merge its old files up to the remote vault, and notes deleted since would come back on every device. Nelson and the obsidian ship decide (for example, move it aside, and give Sync an empty folder).
- [ ] Nelson decides what to do with the uncommitted edits in the Air's main checkout. The rsync carries them as they are, uncommitted. On the macOS side: `TODO.md`, `zsh/.zshrc`, the deleted `jd/jd.yaml`, and four tickle job files set to `status: disabled` that are `active` in git: `rex-briefing`, `plugin-fork-drift`, `pickle-resume` (these three wait on the queue item "Commit the three disabled tickle jobs") and `vault-skills-export`. On the claude code side (that ship's question): `claude/settings.json` and the untracked `claude/skills/synced/`. **If the four job edits are dropped, the four jobs are active again**, and `pickle-resume` is gated to the Pro and starts `claude` sessions. Step 5 checks this before tickle starts.
- [ ] Homebrew on the Pro. Then `install/install.sh` from the dotfiles checkout once it is there: see step 4, "Set up the Pro", below.

## On the day

Both Macs run tickle for a short time (from step 5 to step 6). That is safe only while the fleet is paused and only the jobs checked in step 5 are active: `governor-docs-mirror` (it writes the vault and has no host gate) stops at the pause gate, and `obsidian-backup`, which runs through the pause, only reads the vault and writes each Mac's own `~/obsidian-backup.git`. `pickle-resume` has no pause gate, so it must be disabled (step 5). The pause stays on until step 7.

### 1. Pause

- [ ] Pause the fleet (the Pause note). The claude code ship stops the sessions.
- [ ] On the Air, check the pause holds for tickle: `tickle check governor-docs-mirror` runs the pause gate at once and reports it skipped.

### 2. Final backup on the Air, and copy

- [ ] On the Air, wait for a scheduled `obsidian-backup` run (it runs at :00, :10, :20 and so on, through the pause), and record its commit: `git --git-dir="$HOME/obsidian-backup.git" log -1 --format='%h %ci'`. A manual `tickle run` does not move the schedule, so the next run could start a minute later.
- [ ] Right after that run, copy the two backup repos FIRST: `~/obsidian-backup.git` and `~/governor-history-backup.git`. A copy that is still going at the next run (10 minutes later) can catch a half-written commit. Copy each one whole into a path that does not exist yet, for example `rsync -a ~/obsidian-backup.git/ nelson@macbook-pro:obsidian-backup.git/` (the trailing slashes matter).
- [ ] On the Pro: `git --git-dir="$HOME/obsidian-backup.git" fsck --no-dangling` is clean, and `log -1` shows the commit recorded above. If it shows a newer commit or fsck fails, copy the repo again right after the Air's next run.
- [ ] Then the rest. The full copy list is in the proposal, section 10 step 5. The macOS-side part is `~/repos` by one rsync to the same path (38 GB; it carries dotfiles with its uncommitted files and worktrees), without `--delete` (see "Before the day").
- [ ] Not copied: `~/Library/Application Support/tickle` (runs, state, logs). It is per machine. The Pro builds its own.

### 3. Merge PR #91, and pull on the Pro only

- [ ] Nelson merges PR #91 (skip if it is already merged).
- [ ] On the Pro, before the pull: `git -C ~/repos/system/dotfiles fetch` and compare `git -C ~/repos/system/dotfiles diff --name-only HEAD origin/main` with `git -C ~/repos/system/dotfiles status --short`. The pull brings every commit on main since the Air's HEAD, not only PR #91. If a file is in both lists, or a new file falls under an untracked folder in the status list (such as `claude/skills/synced/`), the pull refuses. A refused `--ff-only` pull changes nothing: stop and ask, and never use `--autostash` (on 2026-09-22 it broke the token symlink).
- [ ] On the Pro: `git -C ~/repos/system/dotfiles pull --ff-only`.
- [ ] Check on the Pro: `grep -n 'on-host.sh' ~/repos/system/dotfiles/tickle/jobs/obsidian-backup.yaml` shows `Nelsons-MacBook-Pro` (the gate line itself, not the comments).
- [ ] Do NOT pull on the Air yet. The Air keeps backing up until step 6.

### 4. Set up the Pro

- [ ] `git -C ~/repos/system/dotfiles config --local --get core.hooksPath` prints `githooks`. If not, `install/install.sh` sets it (it is a local git setting, so the rsync of `.git/config` also carries it).
- [ ] `~/repos/system/dotfiles/install/install.sh --skip launchagents` (the same as `--only links,ssh,packages,npm,pipx,uv,cargo,shell`). Skip the LaunchAgents here, so tickle does not start before step 5.
- [ ] The tickle binary: copy the Air's own, so the move changes the host and not the tickle version. On the Air, `~/.local/bin/tickle` (the CLI the steps call) and `~/Library/Application Support/tickle/bin/tickle` (the daemon's) are the same file, built 2026-07-14. Copy it to BOTH paths on the Pro, with `mkdir -p "$HOME/Library/Application Support/tickle/bin" ~/.local/bin` first. Check on the Pro: `cmp ~/.local/bin/tickle "$HOME/Library/Application Support/tickle/bin/tickle"` prints nothing, and `command -v tickle` prints `/Users/nelson/.local/bin/tickle`. **Do not run agent-stack's `setup.sh` or `tickle service install`.** `setup.sh` also builds pickle, installs the agent-approvals plugin, copies files into `dotfiles/tickle/scripts/pickle-resume/`, and starts tickle with its own LaunchAgent, all before step 5.
- [ ] `~/.claude/governor/history` exists on the Pro and holds files (`find ~/.claude/governor/history -type f | head -1` prints a path). It is the claude code ship's copy, and `obsidian-backup` fails with FATAL on every run without it.
- [ ] Obsidian Sync on the Pro says "Fully synced", and the vault is whole. Sync does not carry `.trash`, and by default skips file types it does not support (on the Air, about 7,000 of the vault's 31,000 files are in `.trash`). Before Sync starts on the Pro, turn on "Sync all other types" in its Sync settings, so scripts (`.js`), Bases (`.base`), `.json`, images and PDFs come across. Then compare the counts per file type on both Macs: `find ~/obsidian -type f -not -path '*/.trash/*' -not -path '*/.obsidian/*' | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -15`. Each count must be close. (`.obsidian/` is copied apart, by the obsidian ship.)
- [ ] From now until step 6, Obsidian is open on both Macs, and its plugins (the Linter, the automatic linker, TaskNotes) can write a note on load or on save. So from here to step 6, nobody edits notes on either Mac, and Obsidian on the Air stays closed if it can.
- [ ] `refresh-contacts` calls `~/.local/bin/refresh-contacts`. Check it exists on the Pro: `ls -la ~/.local/bin/refresh-contacts`. (It does not exist on the Air.) If it is missing, the job fails every night at 03:55; it spends nothing, but it is a red run.
- [ ] `rex-briefing` is still gated to `Nelsons-MacBook-Air` (it is disabled, by an uncommitted edit). If Nelson turns it on again after the cut-over, its gate must name the Pro, or it skips every morning without a sign. That is his call with the queue item on the disabled jobs; PR #91 does not touch it.
- [ ] The dangling `~/.config/jd` symlink: the manifest links `~/.config/jd` to `dotfiles/jd`, and `jd/` no longer exists in the Air's checkout (its only file, `jd/jd.yaml`, is deleted but not committed). After the rsync the link dangles on the Pro too. Nelson decides: restore `jd/jd.yaml`, or commit the deletion and drop the `jd` line from `install/manifest.yaml` (a shared path: both captains review it).

### 5. Tickle up on the Pro

The plists are in `install/launchagents/`. Each Mac picks its own. On the Pro:

| Label | On the Pro | Note |
| --- | --- | --- |
| `dev.tickle.daemon` | **yes** | tickle up on the Pro, after step 3. |
| `love.nelson.obsidian` | yes | Obsidian at login, with the performance flags. The heap cap (8 GB) is not changed here. |
| `com.nelson.vault-mcp-remote` | already there | The obsidian.nelson.love proxy. Check its `VAULT_PATH` (see the proposal, section 2). |
| `com.nelson.cloudflared-obsidian` | already there | The tunnel for the same proxy. |
| `com.nelson.legal-mail.poll` | **no, not without Nelson's word** | It writes into `80-89 Divorce/84 Communications/84.11 Legal email archive`, a guarded area. Its plist also points at `/Users/nelson/repos/legal-mail`, which does not exist any more (the repo is at `~/repos/etc/legal-mail`), so it would fail as written. It is not installed on the Air today. |

- [ ] BEFORE loading tickle, check the job states on the Pro: `grep -H '^status:' ~/repos/system/dotfiles/tickle/jobs/*.yaml`. `vault-backup`, `task-curator` and `pickle-resume` must say `disabled`. If `pickle-resume` says `active`, stop here: it calls `claude` and has no pause gate. The states of `rex-briefing`, `plugin-fork-drift` and `vault-skills-export` are what Nelson decided before the day; whatever is active runs on the Pro after the unpause.
- [ ] Quit Obsidian on the Pro first (it ran for Sync in step 4). `love.nelson.obsidian` starts it with the performance flags only if no Obsidian is running already.
- [ ] Refresh the backup index once by hand, before the daemon runs the job: `git --git-dir="$HOME/obsidian-backup.git" --work-tree="$HOME/obsidian" status --short | wc -l`. The index came from the Air, and every file on the Pro has a new time stamp, so git must read the whole vault once. By hand that has no time limit; inside the job it has 5 minutes, and a run that times out leaves the index stale for the next one.
- [ ] Then load it: `install/install.sh --only launchagents --launchagents dev.tickle.daemon,love.nelson.obsidian`.
- [ ] Check: `launchctl print "gui/$(id -u)/dev.tickle.daemon"` shows it running, and `tickle list` shows the same states as the grep above.
- [ ] `tickle check obsidian-backup` passes (the gate matches the Pro).
- [ ] One run on the Pro: do not start one by hand, because a manual run can collide with the daemon's own run on the same repo. Wait for the next scheduled run (:00, :10, :20 and so on), then check `tickle logs obsidian-backup` shows it succeeded (a FATAL fails the run even after it commits the vault). Then `git --git-dir="$HOME/obsidian-backup.git" log -1 --format='%h %ci'` shows a new commit after the one from step 2, and no note outside `.trash` was deleted: `git -c core.quotePath=false --git-dir="$HOME/obsidian-backup.git" diff --diff-filter=D --name-only <the commit from step 2> HEAD | grep -v -e '^\.trash/' -e '^\.obsidian/' | wc -l` prints `0` or a small number (`core.quotePath=false`, or names with a dash or a curly quote are printed quoted and slip past the filter). The first Pro commits delete the `.trash` files and the file types Sync skips; that is expected, and those files stay in the backup's history.

### 6. Tickle down on the Air

Only after step 5 shows a good run on the Pro.

- [ ] On the Air: `launchctl bootout "gui/$(id -u)" ~/Library/LaunchAgents/dev.tickle.daemon.plist`.
- [ ] Keep it down after a reboot: `mv ~/Library/LaunchAgents/dev.tickle.daemon.plist ~/Library/LaunchAgents/dev.tickle.daemon.plist.disabled-air`. (The copy in the repo stays. It is the Pro's source.)
- [ ] Check: `launchctl print "gui/$(id -u)/dev.tickle.daemon"` says it is not found, and `pgrep -fl 'tickle daemon'` prints nothing.
- [ ] On the Air: the same check as in step 3, then `git -C ~/repos/system/dotfiles pull --ff-only` (never `--autostash`), so the Air's copy also gates `obsidian-backup` to the Pro. Then even a tickle started by mistake on the Air does not back up there. If the pull refuses, take only that file: `git -C ~/repos/system/dotfiles checkout origin/main -- tickle/jobs/obsidian-backup.yaml`, and sort out the rest later.
- [ ] Obsidian on the Air: the proposal allows it to stay open for Nelson's own reading. But its plugins can write notes on load or on save (the Linter, the automatic linker, TaskNotes and others), and Sync carries those writes, so it is a second writer. Nelson decides: quit it and move `love.nelson.obsidian` aside on the Air the same way as tickle, or keep it and accept that.

### 7. Prove the Pro, then unpause

- [ ] Two more scheduled backup runs on the Pro succeed: `tickle logs obsidian-backup` (or `tickle status`). Prove it by the run history, not by new commits: a run commits only when the vault changed, and a paused vault may not change.
- [ ] Before the unpause, check what each other active job needs on the Pro. From now on they run on the Pro only.
  - `governor-docs-mirror` (no host gate): `~/repos/system/obsidian-mcp-suite`. It writes the vault.
  - `refresh-contacts` (Pro gate): `~/.local/bin/refresh-contacts` (step 4).
  - `comms-ping` (Pro gate): `~/repos/agent-stack/plugins/agent-approvals/skills/comms-send/comms-send.sh`, a pre-move path. It does not exist on the Air, so there the job fails and spends nothing. If an old flat `~/repos/agent-stack` is still on the Pro, it sends pings every 5 minutes from 21:00 to 21:55.
  - `vault-mcp-remote-update` (Pro gate): `~/repos/obsidian-vault-mcp-plugin`, also a pre-move path. Without it the job exits green with "repo not present" and checks nothing. The same comms-send path as `comms-ping`.
  - If Nelson left them active: `plugin-fork-drift` (no host gate; the repos under `~/repos/system`) and `vault-skills-export` (no host gate; every hour at :17).
  - Every job that calls comms-send needs `pickle`: comms-send runs the first `pickle` on the job's PATH, which has `~/.local/bin` and `/opt/homebrew/bin`. The Air's is `~/.local/bin/pickle` (built 2026-07-14), which is not in the `~/repos` rsync, and the Brewfile can also install one from Homebrew. Copy the Air's to `~/.local/bin/pickle` on the Pro, so the same build answers.
- [ ] Nelson lifts the pause.
- [ ] `~/vault-backup.git` on the Pro is left in place. `vault-backup` no longer writes it. What happens to it is Nelson's call.
- [ ] The claude code ship resumes the sessions on the Pro.

## Undo

Undo only the gate. The other two changes in PR #91 (`vault-backup` retired, `task-curator` disabled) are Nelson's rulings, and do not depend on which Mac hosts the fleet.

- Before step 6: stop tickle on the Pro and move its plist away, so a reboot does not start it again: `launchctl bootout "gui/$(id -u)" ~/Library/LaunchAgents/dev.tickle.daemon.plist; mv ~/Library/LaunchAgents/dev.tickle.daemon.plist ~/Library/LaunchAgents/dev.tickle.daemon.plist.undone` (on the Pro). The Air never stopped. But main now gates `obsidian-backup` to the Pro, so **do not pull on the Air** until a new PR sets that one file back to `Nelsons-MacBook-Air` and merges. A pull before that makes the Air's backup skip every run, with no error.
- After step 6: stop tickle on the Pro and move its plist away, as above. At once, so the vault is not left without a backup while that PR waits for review: on the Air, `git -C ~/repos/system/dotfiles checkout <the commit before the merge> -- tickle/jobs/obsidian-backup.yaml` (this gives the Air its gate back as a local edit), then load tickle on the Air again: `mv ~/Library/LaunchAgents/dev.tickle.daemon.plist.disabled-air ~/Library/LaunchAgents/dev.tickle.daemon.plist` and `launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/dev.tickle.daemon.plist`. Then a new PR sets `obsidian-backup.yaml` back to `Nelsons-MacBook-Air` (only that file, not a revert of the whole merge); when it merges, drop the local edit on the Air (`git -C ~/repos/system/dotfiles checkout HEAD -- tickle/jobs/obsidian-backup.yaml`), then pull right away (`--ff-only`). Between those two commands the Air's file names the Pro again, so run them together.
