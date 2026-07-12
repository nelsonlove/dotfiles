# claude — Claude Code user config

Synced portion of `~/.claude/`. Symlinked into place by `install.sh` via
`manifest.yaml` `home_symlinks` (`ln -sfn`, same as everything else).

This is the **single source of truth for `settings.json` + `hooks/` across
both hosts (mbp/mba)**. Machine-specific overrides go in
`~/.claude/settings.local.json` (per-host, not synced here), which Claude Code
merges on top of `settings.json`.

## What lives here

- `settings.json` — user-level settings: model, theme, permissions, `hooks`,
  `enabledPlugins` + `extraKnownMarketplaces` (plugins reinstall themselves
  from the marketplaces on a fresh machine — no plugin files are synced), and
  `autoMemoryDirectory`, which points auto-memory at the vault
  (`~/obsidian/00-09 System/03 LLMs & agents/03.17 Claude Code memories`) so
  memories ride Obsidian Sync across machines instead of this repo.
- `hooks/` — hook scripts referenced by `settings.json` (`block-edit-shared-files.sh`
  guards shared append-only vault files against Read→Edit races;
  `protect-new-repo.sh` auto-applies a "Protect main" ruleset after
  `gh repo create`). Symlinked to `~/.claude/hooks/` so both hosts run them.
- `skills/` — user-level skills (`pickle`, `tickle`, …). New skills written
  to `~/.claude/skills/` land here automatically through the symlink; commit
  them when they settle. Exception: `skills/ops` is a committed symlink to
  `~/src/ops` (the canonical `callumalpass/ops` clone) — on a fresh machine,
  `git clone https://github.com/callumalpass/ops ~/src/ops` makes it resolve.

## What deliberately does NOT live here

- **Secret contents** — `env.GITHUB_PERSONAL_ACCESS_TOKEN` and friends live in
  `settings.local.json`, whose real file sits in the JD tree at
  `09.11 Secrets/claude/` (iCloud-protected). This repo commits only a
  symlink to it (same pattern as gh/wrangler creds). If a secret shows up
  in `settings.json`, move it there before committing.
- `~/.claude.json` — OAuth tokens, trust dialogs. Machine-local.
- `~/.claude/projects/` — session transcripts (machine-local) and the
  per-project `memory/` entries, which on this machine are symlinks into the
  vault store above.
- Caches and runtime state: `plugins/cache/`, `shell-snapshots/`,
  `history.jsonl`, `statsig/`, `file-history/`, etc. All regenerate.

## Fresh machine

`install.sh` symlinks this dir's contents into `~/.claude/` (run it BEFORE
first `claude` launch, or it will warn-and-skip files Claude Code already
created); sign in to Claude Code (auth is per-machine). `settings.local.json`
resolves once iCloud has synced `09.11 Secrets/`; `skills/ops` resolves once
`~/src/ops` is cloned. Memories arrive via Obsidian Sync.
